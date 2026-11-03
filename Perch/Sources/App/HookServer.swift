import Foundation
import Darwin
import AppKit

// MARK: - HookServer
// Listens on a Unix domain socket for events from perch-hook (coding-agent hooks).
// Thread-safe: socket I/O on background threads, state updates dispatched to main queue.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory paths
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch")
    }
    static var socketPath: String {
        #if APPSTORE
        // Container home root keeps path ≤ 103 bytes (sun_path limit on macOS is 104 incl. NUL)
        // /Users/someone/Library/Containers/com.perch.PerchAppStore/Data/perch.sock = ~70 bytes ✓
        return NSHomeDirectory() + "/perch.sock"
        #else
        return supportDir.appendingPathComponent("perch.sock").path
        #endif
    }
    // hookScriptPath is only used by the non-App Store build.
    // App Store build derives the command from the panel-selected claudeURL in buildHooksData(claudeURL:).
    static var hookScriptPath: String { supportDir.appendingPathComponent("perch-hook").path }

    // No approval blocking state — notch is notification-only, user answers in VS Code

    private var serverFD: Int32 = -1
    private var pendingApprovalFD: Int32 = -1   // held open while user decides
    private var activeSessionId: String? = nil  // current agent session

    private init() {}

    // MARK: - Start

    func start() {
        // Ensure support directory exists before socket server tries to bind
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        #if !APPSTORE
        installHookScript()
        #endif
        Thread.detachNewThread { self.serverThread() }
    }

    // MARK: - Socket server (background thread)

    private func serverThread() {
        let path = Self.socketPath
        // sun_path on macOS is 104 bytes including the NUL terminator → max 103 usable bytes
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else {
            NSLog("HookServer: socket path too long (\(path.utf8.count) bytes, max \(maxSunPathBytes)): \(path)")
            return
        }
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        guard Darwin.listen(fd, 10) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
        }
    }

    // MARK: - Client handler (background thread)

    private func handleClient(fd: Int32) {
        // Read newline-delimited JSON
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        if eventName == "PermissionRequest" {
            // Hold fd open — Claude Code waits for our decision (up to 120s)
            Task { @MainActor in self.processPermissionRequest(fd: fd, payload: payload) }
        } else {
            Task { @MainActor in self.processEvent(name: eventName, payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
    }


    // MARK: - Event → AppState
    // Coding-agent events route to a per-agent task ("integration_claude",
    // "integration_codex", "integration_opencode", "integration_zcode",
    // "integration_generic"). Payloads carry `agent: claude|codex|opencode|zcode|
    // generic`; missing/unknown defaults to claude for backwards compatibility.
    // View switches only happen if that agent is the currently focused Pip.
    // When not focused: state updates animate the mini bot in the pill; badge shown for alerts.

    /// Normalises the `agent` field of a hook payload to a task id.
    private func taskId(forAgent agent: String?) -> String {
        switch (agent ?? "claude").lowercased() {
        case "codex":    return "integration_codex"
        case "opencode": return "integration_opencode"
        case "zcode", "z-code": return "integration_zcode"
        case "generic", "other", "unknown": return "integration_generic"
        default:         return "integration_claude"
        }
    }

    /// Default display name for an agent task (used when its session resets).
    private func defaultName(forTaskId id: String) -> String {
        switch id {
        case "integration_codex":    return "Codex"
        case "integration_opencode": return "OpenCode"
        case "integration_zcode":    return "Zcode"
        case "integration_generic":  return "Agent"
        default:                     return "VS Code"
        }
    }

    @MainActor
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let taskId = taskId(forAgent: payload["agent"] as? String)
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        // The VSCode-only filter is a Claude-era restriction. Adapters for other
        // agents (Codex, OpenCode, Zcode, generic wrapper) run in any terminal,
        // so only Claude payloads without an explicit agent tag keep the filter.
        if taskId == "integration_claude" && payload["agent"] == nil {
            let termProgram = payload["term_program"] as? String ?? ""
            let bundleId    = payload["bundle_id"]    as? String ?? ""
            let isVSCode = termProgram.lowercased().contains("vscode") ||
                           bundleId.lowercased().contains("vscode")
            guard isVSCode else {
                nbLog("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
                return
            }
        }

        let focused = state.focusId == taskId

        switch name {

        case "SessionStart":
            activeSessionId = sessionId
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            nbLog("SessionStart [\(taskId)] \(projectName) (\(sessionId.prefix(8)))")
            if state.isPresent { expandIfNeeded(to: .overview) }
            SoundEngine.shared.play("work")

        case "UserPromptSubmit":
            activeSessionId = sessionId
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            state.updateTask(id: taskId, state: .thinking)
            if let prompt = payload["prompt"] as? String, !prompt.isEmpty {
                appendStep(id: taskId, step: String(prompt.prefix(60)))
            }
            if state.isPresent { expandIfNeeded(to: .overview) }

        case "PreToolUse":
            activeSessionId = sessionId
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            state.updateTask(id: taskId, state: .working)
            let tool = payload["tool_name"] as? String ?? "Tool"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = frenchStep(tool: tool, input: input)
            appendStep(id: taskId, step: step)
            nbLog("PreToolUse [\(taskId)] \(step)")

        case "PostToolUse":
            state.updateTask(id: taskId, state: .working)

        case "PostToolUseFailure":
            state.updateTask(id: taskId, state: .working)
            appendStep(id: taskId, step: "⚠ failed")

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let lower = message.lowercased()
            if lower.contains("rate limit") || lower.contains("limite d") {
                state.updateTask(id: taskId, state: .ratelimit)
                SoundEngine.shared.play("rate")
            } else if message.hasSuffix("?") {
                state.updateTask(id: taskId, state: .question)
                appendStep(id: taskId, step: message)
            }

        case "Stop":
            state.updateTask(id: taskId, state: .finished)
            if let message = payload["message"] as? String, !message.isEmpty {
                appendStep(id: taskId, step: String(message.prefix(60)))
            }
            SoundEngine.shared.play("finish")
            if focused {
                expandIfNeeded(to: .finished)
            } else {
                setPillBadge(id: taskId, badge: .finished)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [taskId] in
                state.updateTask(id: taskId, state: .idle)
                self.clearPillBadge(id: taskId)
            }

        case "StopFailure":
            state.updateTask(id: taskId, state: .error)
            SoundEngine.shared.play("error")
            if focused {
                expandIfNeeded(to: .error)
            } else {
                setPillBadge(id: taskId, badge: .error)
            }

        case "SessionEnd":
            activeSessionId = nil
            state.updateTask(id: taskId, state: .idle)
            clearSession(id: taskId)

        case "SubagentStart":
            appendStep(id: taskId, step: "+ subagent")

        case "SubagentStop":
            appendStep(id: taskId, step: "• subagent done")

        default:
            break
        }
    }

    // MARK: - Helpers

    @MainActor
    private func expandIfNeeded(to view: IslandView) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            // Only force-switch view for alerts — leave user on their current view otherwise
            if isAlert { state.view = view }
        } else if isAlert {
            // Alerts always force-expand
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            // Non-alert work events: reveal compact only, never force-expand
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        // Already compact and non-alert: Pip state update is enough, no expand
    }

    // MARK: - Permission request (blocking — the agent waits for a decision)

    @MainActor
    private func processPermissionRequest(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        let taskId = taskId(forAgent: payload["agent"] as? String)
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
        let rawName   = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        // Blocking approvals stay Claude-only for now: other agents have no
        // stable blocking hook contract, so their PermissionRequest payloads are
        // answered with "ask" (terminal takes over) and shown as a working state.
        guard taskId == "integration_claude" else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            state.updateTask(id: taskId, state: .working)
            return
        }

        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""
        let isVSCode = termProgram.lowercased().contains("vscode") ||
                       bundleId.lowercased().contains("vscode")
        guard isVSCode else {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        let tool = payload["tool_name"] as? String ?? "Tool"
        var command = tool
        if let input = payload["tool_input"] as? [String: Any] {
            command = input["command"] as? String ?? tool
        }
        nbLog("PermissionRequest \(tool): \(command)")

        if pendingApprovalFD >= 0 {
            let old = pendingApprovalFD
            Task.detached { [weak self] in
                // "ask" → perch-hook outputs nothing → Claude Code re-asks
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                close(old)
            }
        }
        pendingApprovalFD = fd
        activeSessionId = sessionId

        upsertTask(id: "integration_claude", projectName: projectName, cwd: cwd)
        state.updateTask(id: "integration_claude", state: .approval)
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool, command: command, agentTaskId: "integration_claude")
        state.isPinned = true
        SoundEngine.shared.play("approval")

        // Approval always forces the island open — user must be able to respond
        state.focusId = "integration_claude"
        expandIfNeeded(to: .approval)

        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.pendingApprovalFD == captured else { return }
            // "ask" → perch-hook outputs nothing → Claude Code re-asks rather than denying
            self.sendApprovalDecision("ask")
        }
    }

    /// Called by ApprovalView buttons. Writes the decision to the waiting perch-hook and cleans up.
    @MainActor
    func sendApprovalDecision(_ decision: String) {
        let fd = pendingApprovalFD
        pendingApprovalFD = -1

        let json: String
        switch decision {
        case "allow":  json = #"{"permissionDecision":"allow"}"#
        case "always": json = #"{"permissionDecision":"always"}"#
        case "ask":    json = #"{"permissionDecision":"ask"}"#
        default:       json = #"{"permissionDecision":"deny"}"#
        }

        if fd >= 0 {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: json)
                close(fd)
            }
        }

        let state = AppState.shared
        let taskId = state.pendingApproval?.agentTaskId ?? "integration_claude"
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: taskId, state: .working)
        clearPillBadge(id: taskId)
        state.view = state.tasks.isEmpty ? .empty : .overview
    }

    /// Updates an agent task with the current session project name and cwd.
    @MainActor
    private func upsertTask(id: String, projectName: String, cwd: String = "") {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].name = projectName
        if !cwd.isEmpty { state.tasks[idx].sessionCwd = cwd }
    }

    // MARK: - Badge helpers

    @MainActor
    private func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    private func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    /// Resets an agent task to idle, clears steps and restores its default name.
    @MainActor
    private func clearSession(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps = []
        state.tasks[idx].stepIndex = 0
        state.tasks[idx].name = defaultName(forTaskId: id)
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    private func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 20 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    // MARK: - Project name alias mapping

    private func aliasProjectName(_ name: String) -> String {
        let aliases: [String: String] = [
            "perch": "Perch",
        ]
        return aliases[name.lowercased()] ?? name
    }

    // MARK: - French step labels

    private func frenchStep(tool: String, input: [String: Any]) -> String {
        let labels: [String: String] = [
            "Bash":       "Exécute",
            "Read":       "Lit",
            "Write":      "Écrit",
            "Edit":       "Modifie",
            "Glob":       "Cherche",
            "Grep":       "Recherche",
            "WebSearch":  "Recherche web",
            "WebFetch":   "Récupère",
            "TodoWrite":  "Tâches",
            "Task":       "Agent",
            "LS":         "Liste",
            "MultiEdit":  "Modifie",
            "NotebookEdit": "Notebook",
        ]
        let label = labels[tool] ?? tool
        if let cmd = input["command"] as? String {
            let short = String(cmd.prefix(40))
            return "\(label) · \(short)"
        } else if let path = input["path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
        } else if let file = input["file_path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: file).lastPathComponent)"
        } else if let query = input["query"] as? String {
            return "\(label) · \(String(query.prefix(40)))"
        }
        return label
    }

    // MARK: - Logging

    private func nbLog(_ message: String) {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Perch")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("nb.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }

    private func sendLine(fd: Int32, text: String) {
        let bytes = Array((text + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    // MARK: - perch-hook script installation

    func installHookScript() {
        #if APPSTORE
        // In App Store mode the script is written during settings hook installation
        // (requires NSOpenPanel to ~/.claude chosen by the user)
        #else
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // perch-hook: shell wrapper (always exits 0, calls perch-hook.py via python3)
        let wrapperURL = URL(fileURLWithPath: Self.hookScriptPath)
        try? perchHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        // perch-hook.py: Python relay
        let pyURL = wrapperURL.deletingLastPathComponent().appendingPathComponent("perch-hook.py")
        try? perchHookPythonGitHub.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)
        #endif
    }

    // MARK: - Outdated hook detection

    /// True for a hook command installed by Perch.
    static func isOwnHookCommand(_ cmd: String) -> Bool {
        cmd.contains("perch-hook") || cmd.contains("Perch")
    }

    /// Returns true if settings.json has a Perch PermissionRequest hook with timeout < 120s.
    static func hooksNeedUpdate() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any],
              let permReqHooks = hooks["PermissionRequest"] as? [[String: Any]] else {
            return false
        }
        for matcher in permReqHooks {
            if let hookList = matcher["hooks"] as? [[String: Any]] {
                for hook in hookList {
                    if let cmd = hook["command"] as? String,
                       Self.isOwnHookCommand(cmd),
                       let timeout = hook["timeout"] as? Int,
                       timeout < 120 {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Claude Code settings.json hook installer

    private var _pendingHooksData: Data?

    /// Returns preview JSON without writing — call writeClaudeHooks() to confirm.
    func previewClaudeHooks() throws -> String {
        let data = try buildHooksData()
        _pendingHooksData = data
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes the hooks to disk (call after user confirms preview).
    func writeClaudeHooks() throws {
        guard let data = _pendingHooksData else { return }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Backup first
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        let backupURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.bak-\(stamp)")
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        _pendingHooksData = nil
    }

    private func buildHooksData() throws -> Data {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }
        let hookPath = Self.hookScriptPath
        #if APPSTORE
        // Sandboxed apps create quarantined files; /bin/sh bypasses the quarantine flag
        let quotedCmd = "/bin/sh \"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        #else
        let quotedCmd = "\"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        #endif
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains { Self.isOwnHookCommand(($0["command"] as? String) ?? "") } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    func uninstallClaudeHooks() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        Self.isOwnHookCommand(($0["command"] as? String) ?? "")
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
    }

    // MARK: - App Store: hooks via security-scoped bookmark

    #if APPSTORE
    /// Writes perch-hook script and updates settings.json in one shot.
    /// claudeURL must be a URL from NSOpenPanel (sandbox access is granted immediately — no security scope needed).
    func installAndWriteClaudeHooksAppStore(claudeURL: URL) throws {
        let data = try buildHooksData(claudeURL: claudeURL)

        // Write perch-hook (shell wrapper) + perch-hook.py (Python relay) into ~/.claude/perch/
        let perchDir = claudeURL.appendingPathComponent("perch")
        try FileManager.default.createDirectory(at: perchDir, withIntermediateDirectories: true)
        let wrapperURL = perchDir.appendingPathComponent("perch-hook")
        try perchHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        let pyURL = perchDir.appendingPathComponent("perch-hook.py")
        try perchHookPythonAppStore.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)

        // Write settings.json (with backup)
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let backupURL = claudeURL.appendingPathComponent("settings.json.bak-\(formatter.string(from: Date()))")
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try data.write(to: settingsURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: "perchHooksInstalled")
    }

    func uninstallClaudeHooksAppStore(claudeURL: URL) throws {
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        Self.isOwnHookCommand(($0["command"] as? String) ?? "")
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
        UserDefaults.standard.set(false, forKey: "perchHooksInstalled")
    }

    private func buildHooksData(claudeURL: URL) throws -> Data {
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }
        // Derive hook path from the panel-selected claudeURL (real ~/.claude, not container)
        let hookPath = claudeURL.appendingPathComponent("perch/perch-hook").path
        let quotedCmd = "/bin/sh \"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains {
                Self.isOwnHookCommand(($0["command"] as? String) ?? "")
            } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }
    #endif
}

    // MARK: - Other coding agents (Codex, OpenCode, …)

    // Mirror of agents/opencode/perch.ts — keep in sync. Installed to
    // ~/.config/opencode/plugins/perch.ts by previewOpenCodeHooks/writeOpenCodeHooks.
    // Line endings are normalized on use and a single trailing newline is
    // appended, so the installed file is byte-identical to agents/opencode/perch.ts
    // (and to what the Windows installer writes): checkouts on Windows carry CRLF,
    // the plugin file itself is always written with LF.
    private var opencodePluginText: String {
        opencodePlugin.replacingOccurrences(of: "\r\n", with: "\n") + "\n"
    }

    private let opencodePlugin = """
// Perch plugin for OpenCode — shows OpenCode sessions in the notch/island.
//
// Install:
//   1. Copy this file to `~/.config/opencode/plugins/perch.ts`
//      (or `<project>/.opencode/plugins/perch.ts` for one repo).
//   2. Register it in `opencode.json`: { "plugin": ["./plugins/perch.ts"] }
//      (path relative to the config file; global config uses the ~/.config copy).
//   3. Launch Perch once so the relay exists.
//
// How it works: OpenCode hook points are mapped to Perch event names and piped
// as one JSON line to the Perch relay (macOS socket relay, Windows
// perch-hook.exe). Every send is fire-and-forget with a short timeout — a dead
// Perch costs milliseconds, never a blocked session. Observability only: there
// is no blocking approval path for OpenCode, the terminal stays in charge.
//
// Mapping:
//   session.created      -> SessionStart
//   tool.execute.before  -> PreToolUse (+ UserPromptSubmit flavour via prompt)
//   tool.execute.after   -> PostToolUse
//   session.idle         -> Stop
//   session.deleted      -> SessionEnd

import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "node:child_process";
import * as os from "node:os";
import * as path from "node:path";

const AGENT = "opencode";

function relayCandidates(): string[][] {
  const home = os.homedir();
  if (process.platform === "win32") {
    const exe = path.join(
      process.env.LOCALAPPDATA || path.join(home, "AppData", "Local"),
      "Perch",
      "bin",
      "perch-hook.exe",
    );
    return [[exe]];
  }
  return [
    [path.join(home, "Library", "Application Support", "Perch", "perch-hook")],
    ["python3", path.join(home, ".config", "opencode", "plugins", "perch-relay.py")],
  ];
}

function send(event: Record<string, unknown>): void {
  const line = Buffer.from(JSON.stringify({ agent: AGENT, ...event }) + "\\n");
  const extraEnv =
    process.platform === "win32" ? {} : { PERCH_AGENT: AGENT };
  for (const [bin, ...args] of relayCandidates()) {
    try {
      const r = spawnSync(bin, [...args, (event.hook_event_name as string) || "", AGENT], {
        input: line,
        timeout: 800,
        stdio: ["pipe", "ignore", "ignore"],
        env: { ...process.env, ...extraEnv },
      });
      if (!r.error) return; // delivered (or Perch closed but relay exited 0)
    } catch {
      // try the next candidate
    }
  }
}

const cwdOf = (input: any): string => {
  try {
    return input?.session?.cwd || input?.cwd || process.cwd();
  } catch {
    return "";
  }
};

export const Hook: Plugin = async () => ({
  "session.created": async (input: any) => {
    send({
      hook_event_name: "SessionStart",
      session_id: String(input?.session?.id ?? input?.sessionID ?? "unknown"),
      cwd: cwdOf(input),
    });
  },

  "tool.execute.before": async (input: any, output: any) => {
    const tool = String(input?.tool ?? output?.tool ?? "Tool");
    const args = output?.args ?? input?.args ?? {};
    send({
      hook_event_name: "PreToolUse",
      session_id: String(input?.session?.id ?? input?.sessionID ?? "unknown"),
      cwd: cwdOf(input),
      tool_name: tool,
      tool_input: typeof args === "object" && args !== null ? args : { input: String(args) },
    });
  },

  "tool.execute.after": async (input: any, output: any) => {
    const err = output?.error || input?.error;
    send({
      hook_event_name: err ? "PostToolUseFailure" : "PostToolUse",
      session_id: String(input?.session?.id ?? input?.sessionID ?? "unknown"),
      cwd: cwdOf(input),
      tool_name: String(input?.tool ?? output?.tool ?? "Tool"),
    });
  },

  "session.idle": async (input: any) => {
    send({
      hook_event_name: "Stop",
      session_id: String(input?.session?.id ?? input?.sessionID ?? "unknown"),
      cwd: cwdOf(input),
    });
  },

  "session.deleted": async (input: any) => {
    send({
      hook_event_name: "SessionEnd",
      session_id: String(input?.session?.id ?? input?.sessionID ?? "unknown"),
      cwd: cwdOf(input),
    });
  },
});
"""

    // Claude keeps its own installer above; this section covers the rest with
    // the same backup-then-diff-then-write guarantees. Zcode and anything
    // without a hooks API are status-only (the UI shows the wrapper command).

    /// Setup status for one agent, shown in Settings → Other coding agents.
    struct AgentSetupStatus {
        var id: String
        var name: String
        var cliDetected: Bool
        var installed: Bool
        var settingsPath: String
        var detail: String
        var canAuto: Bool
    }

    private static func cliOnPath(_ name: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "command -v \(name) >/dev/null 2>&1"]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }
        return proc.terminationStatus == 0
    }

    private static func readJSONFile(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF] as [UInt8]) { bytes.removeFirst(3) }
        if bytes.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw NSError(domain: "PerchHooks", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(url.path) isn't valid JSON. Fix or move it, then try again — Perch won't overwrite it."
            ])
        }
        return json
    }

    private static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in data {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func fileFingerprint(_ url: URL) -> String {
        (try? Data(contentsOf: url)).map { fnv1a($0) } ?? fnv1a(Data())
    }

    private static func datedBackupURL(for url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-\(stamp).bak\(ext)")
    }

    /// Setup status for Codex, OpenCode, Zcode and the generic wrapper.
    func agentsStatus() -> [AgentSetupStatus] {
        var out: [AgentSetupStatus] = []

        // Codex
        let codexURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
        let codexInstalled: Bool = {
            guard let data = try? Data(contentsOf: codexURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else { return false }
            for matchers in hooks.values {
                for matcher in (matchers as? [[String: Any]]) ?? [] {
                    let inner = (matcher["hooks"] as? [[String: Any]]) ?? []
                    if inner.contains(where: { Self.isOwnHookCommand(($0["command"] as? String) ?? "") }) {
                        return true
                    }
                }
            }
            return false
        }()
        let codexCLI = Self.cliOnPath("codex")
        out.append(AgentSetupStatus(
            id: "codex", name: "Codex", cliDetected: codexCLI, installed: codexInstalled,
            settingsPath: codexURL.path,
            detail: codexInstalled ? "Hooked in — Codex sessions show up in the island."
                : codexCLI ? "Codex CLI found. Install the hooks to light up its pill."
                : "Codex CLI not on PATH. Install it, then come back.",
            canAuto: true
        ))

        // OpenCode
        let pluginURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/perch.ts")
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")
        let pluginCurrent = (try? Data(contentsOf: pluginURL)) == opencodePluginText.data(using: .utf8)
        let configRegistered: Bool = {
            guard let json = try? Self.readJSONFile(configURL),
                  let plugins = json["plugin"] as? [String] else { return false }
            return plugins.contains { $0.contains("perch") }
        }()
        let openInstalled = pluginCurrent && configRegistered
        let openCLI = Self.cliOnPath("opencode")
        out.append(AgentSetupStatus(
            id: "opencode", name: "OpenCode", cliDetected: openCLI, installed: openInstalled,
            settingsPath: configURL.path,
            detail: openInstalled ? "Plugin active — OpenCode sessions show up in the island."
                : pluginURLExists() && !pluginCurrent ? "An older Perch plugin is there — reinstall to update it."
                : openCLI ? "OpenCode CLI found. Install the plugin to light up its pill."
                : "OpenCode CLI not on PATH. The plugin still works if you use OpenCode.",
            canAuto: true
        ))

        // Status-only agents
        out.append(AgentSetupStatus(
            id: "zcode", name: "Zcode", cliDetected: Self.cliOnPath("zcode"), installed: false,
            settingsPath: "",
            detail: "No hooks API — wrap its command so Perch can watch. Example: perch-run --agent zcode -- zcode …",
            canAuto: false
        ))
        out.append(AgentSetupStatus(
            id: "generic", name: "Anything else", cliDetected: false, installed: false,
            settingsPath: "",
            detail: "No hooks API — wrap any command: perch-run -- <command>.",
            canAuto: false
        ))
        return out
    }

    private func pluginURLExists() -> Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/perch.ts").path)
    }

    // MARK: - Agent hook preview/write (Codex + OpenCode)

    private var _pendingCodexData: Data?
    private var _pendingCodexFingerprint: String?
    private var _pendingOpenPlugin: (text: String?, remove: Bool)?
    private var _pendingOpenConfig: (text: String?, removeEntry: Bool)?
    private var _pendingOpenFingerprint: String?

    /// Display text for the Settings diff area. Call writeAgentHooks() to confirm.
    func previewAgentHooks(agent: String, install: Bool) throws -> String {
        switch agent {
        case "codex": return try previewCodexHooks(install: install)
        case "opencode": return try previewOpenCodeHooks(install: install)
        default: throw NSError(domain: "PerchHooks", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "\(agent) has no automatic setup — see the hint."
        ])
        }
    }

    /// Writes after previewAgentHooks(). Returns a human summary.
    func writeAgentHooks(agent: String, install: Bool) throws -> String {
        switch agent {
        case "codex": return try writeCodexHooks(install: install)
        case "opencode": return try writeOpenCodeHooks(install: install)
        default: throw NSError(domain: "PerchHooks", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "\(agent) has no automatic setup — see the hint."
        ])
        }
    }

    // MARK: Codex (~/.codex/hooks.json, Codex matcher schema)

    private func codexHookCommand(event: String) -> String {
        let exe = Self.hookScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(exe)\" \(event) codex"
    }

    private func previewCodexHooks(install: Bool) throws -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
        var settings = try Self.readJSONFile(url)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
        ]
        if install {
            for (event, timeout) in events {
                var existing = hooks[event] as? [[String: Any]] ?? []
                existing.removeAll { matcher in
                    ((matcher["hooks"] as? [[String: Any]]) ?? []).contains {
                        Self.isOwnHookCommand(($0["command"] as? String) ?? "")
                    }
                }
                existing.append(["matcher": "", "hooks": [
                    ["type": "command", "command": codexHookCommand(event: event), "timeout": timeout]
                ]])
                hooks[event] = existing
            }
        } else {
            for key in hooks.keys {
                if var matchers = hooks[key] as? [[String: Any]] {
                    matchers.removeAll { matcher in
                        ((matcher["hooks"] as? [[String: Any]]) ?? []).contains {
                            Self.isOwnHookCommand(($0["command"] as? String) ?? "")
                        }
                    }
                    if matchers.isEmpty { hooks.removeValue(forKey: key) }
                    else { hooks[key] = matchers }
                }
            }
        }
        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        _pendingCodexData = data
        _pendingCodexFingerprint = Self.fileFingerprint(url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func writeCodexHooks(install: Bool) throws -> String {
        guard let data = _pendingCodexData, let fp = _pendingCodexFingerprint else { return "Nothing to write." }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
        guard Self.fileFingerprint(url) == fp else {
            throw NSError(domain: "PerchHooks", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\(url.path) changed since the preview. Nothing was written — review the new diff."
            ])
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.copyItem(at: url, to: Self.datedBackupURL(for: url))
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        _pendingCodexData = nil
        _pendingCodexFingerprint = nil
        _ = install
        return install ? "Codex hooks installed in ~/.codex/hooks.json" : "Codex hooks removed."
    }

    // MARK: OpenCode (~/.config/opencode/plugins/perch.ts + opencode.json)

    private func previewOpenCodeHooks(install: Bool) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pluginURL = home.appendingPathComponent(".config/opencode/plugins/perch.ts")
        let configURL = home.appendingPathComponent(".config/opencode/opencode.json")
        if install {
            var lines: [String] = []
            let current = try? Data(contentsOf: pluginURL)
            if current != opencodePluginText.data(using: .utf8) {
                lines.append("Write \(pluginURL.path) (\(max(1, opencodePluginText.components(separatedBy: "\n").count - 1)) lines, the Perch plugin)\(FileManager.default.fileExists(atPath: pluginURL.path) ? " — backs up the old one first" : "")")
                _pendingOpenPlugin = (opencodePluginText, false)
            } else {
                _pendingOpenPlugin = nil
            }
            var configNote = ""
            do {
                var config = try Self.readJSONFile(configURL)
                var plugins = config["plugin"] as? [String] ?? []
                if !plugins.contains(where: { $0.contains("perch") }) {
                    plugins.append("./plugins/perch.ts")
                    config["plugin"] = plugins
                    let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
                    configNote = String(data: data, encoding: .utf8) ?? ""
                    _pendingOpenConfig = (configNote, false)
                } else {
                    _pendingOpenConfig = nil
                }
            } catch {
                configNote = "NOTE: \(configURL.path) isn't plain JSON — the plugin will be installed, but register it yourself: \"plugin\": [\"./plugins/perch.ts\"]."
                _pendingOpenConfig = nil
            }
            if !configNote.isEmpty { lines.append(configNote) }
            if lines.isEmpty { lines.append("No change.") }
            _pendingOpenFingerprint = "\(Self.fileFingerprint(pluginURL)):\(Self.fileFingerprint(configURL))"
            return lines.joined(separator: "\n")
        } else {
            _pendingOpenPlugin = (nil, true)
            _pendingOpenConfig = (nil, true)
            _pendingOpenFingerprint = "\(Self.fileFingerprint(pluginURL)):\(Self.fileFingerprint(configURL))"
            return "Remove \(pluginURL.path) and unregister it from \(configURL.path)."
        }
    }

    private func writeOpenCodeHooks(install: Bool) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pluginURL = home.appendingPathComponent(".config/opencode/plugins/perch.ts")
        let configURL = home.appendingPathComponent(".config/opencode/opencode.json")
        guard let fp = _pendingOpenFingerprint,
              "\(Self.fileFingerprint(pluginURL)):\(Self.fileFingerprint(configURL))" == fp else {
            throw NSError(domain: "PerchHooks", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Something changed since the preview. Nothing was written — review the new diff."
            ])
        }
        var notes: [String] = []
        if install {
            if let pending = _pendingOpenPlugin {
                if FileManager.default.fileExists(atPath: pluginURL.path) {
                    try? FileManager.default.copyItem(at: pluginURL, to: Self.datedBackupURL(for: pluginURL))
                    notes.append("old plugin backed up")
                }
                try pending.text?.write(to: pluginURL, atomically: true, encoding: .utf8)
                notes.append("plugin written")
            }
            if let pending = _pendingOpenConfig, let text = pending.text {
                if FileManager.default.fileExists(atPath: configURL.path) {
                    try? FileManager.default.copyItem(at: configURL, to: Self.datedBackupURL(for: configURL))
                }
                try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: configURL, atomically: true, encoding: .utf8)
                notes.append("opencode.json registered")
            }
        } else {
            if FileManager.default.fileExists(atPath: pluginURL.path) {
                try? FileManager.default.removeItem(at: pluginURL)
                notes.append("plugin removed")
            }
            if var config = try? Self.readJSONFile(configURL),
               var plugins = config["plugin"] as? [String] {
                let before = plugins.count
                plugins.removeAll { $0.contains("perch") }
                if plugins.count != before {
                    try? FileManager.default.copyItem(at: configURL, to: Self.datedBackupURL(for: configURL))
                    if plugins.isEmpty { config.removeValue(forKey: "plugin") }
                    else { config["plugin"] = plugins }
                    if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
                       let text = String(data: data, encoding: .utf8) {
                        try? text.write(to: configURL, atomically: true, encoding: .utf8)
                    }
                    notes.append("opencode.json unregistered")
                }
            }
        }
        _pendingOpenPlugin = nil
        _pendingOpenConfig = nil
        _pendingOpenFingerprint = nil
        _ = install
        return notes.isEmpty ? "No change." : (install ? "OpenCode connected (" : "OpenCode disconnected (") + notes.joined(separator: ", ") + ")."
    }

    // MARK: - Notification names for hook server → controller communication

extension Notification.Name {
    static let hookExpand = Notification.Name("perch.hookExpand")
}

// MARK: - perch-hook shell wrapper (same for both GitHub and App Store)
// Invoked by Claude Code via /bin/sh or directly via shebang.
// Always exits 0 — never blocks Claude Code.
// Checks xcode-select before running python3 to avoid triggering the
// "install developer tools" dialog on machines without Xcode CLI tools.

private let perchHookShellWrapper = """
#!/bin/sh
# Perch hook relay — always exits 0, never blocks Claude Code
HOOK_DIR="$(dirname "$0")"
if xcode-select -p >/dev/null 2>&1; then
    out=$(/usr/bin/python3 "$HOOK_DIR/perch-hook.py" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        printf '%s\\n' "$out"
    fi
fi
exit 0
"""

// MARK: - perch-hook Python relay (GitHub / non-sandboxed version)

private let perchHookPythonGitHub = """
#!/usr/bin/env python3
# perch-hook.py — Perch hook relay for Claude Code (GitHub version)
# Reads JSON from stdin, forwards to Perch via Unix socket, translates response.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()
    # Agent tag — lets Perch route to the right pill. Claude's installer leaves
    # this as "claude"; other agents override via PERCH_AGENT (see agents/).
    payload.setdefault('agent', os.environ.get('PERCH_AGENT', 'claude'))

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Application Support/Perch/perch.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Perch's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Perch'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        # Claude Code will handle the absence of output (re-ask or default behaviour)
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""

// MARK: - perch-hook Python relay (App Store — socket in sandboxed container)

private let perchHookPythonAppStore = """
#!/usr/bin/env python3
# perch-hook.py — Perch (App Store) hook relay for Claude Code
# Socket lives inside the sandboxed container; script runs outside the sandbox.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()
    # Agent tag — lets Perch route to the right pill. Claude's installer leaves
    # this as "claude"; other agents override via PERCH_AGENT (see agents/).
    payload.setdefault('agent', os.environ.get('PERCH_AGENT', 'claude'))

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Containers/com.perch.PerchAppStore/Data/perch.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Perch's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Perch'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        sys.exit(0)

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""
