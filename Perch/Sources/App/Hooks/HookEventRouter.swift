import Foundation
import Darwin

// MARK: - Event routing
// Coding-agent events route to a per-agent task ("integration_claude",
// "integration_codex", "integration_opencode", "integration_zcode",
// "integration_generic"). Payloads carry `agent: claude|codex|opencode|zcode|
// generic`; missing/unknown defaults to claude for backwards compatibility.
// View switches only happen if that agent is the currently focused Pip.
// When not focused: state updates animate the mini bot in the pill; badge shown for alerts.

extension HookServer {
    // MARK: - Event → AppState
    // Coding-agent events route to a per-agent task ("integration_claude",
    // "integration_codex", "integration_opencode", "integration_zcode",
    // "integration_generic"). Payloads carry `agent: claude|codex|opencode|zcode|
    // generic`; missing/unknown defaults to claude for backwards compatibility.
    // View switches only happen if that agent is the currently focused Pip.
    // When not focused: state updates animate the mini bot in the pill; badge shown for alerts.

    /// Normalises the `agent` field of a hook payload to a task id.
    func taskId(forAgent agent: String?) -> String {
        switch (agent ?? "claude").lowercased() {
        case "codex":    return "integration_codex"
        case "opencode": return "integration_opencode"
        case "zcode", "z-code": return "integration_zcode"
        case "generic", "other", "unknown": return "integration_generic"
        default:         return "integration_claude"
        }
    }

    /// Default display name for an agent task (used when its session resets).
    func defaultName(forTaskId id: String) -> String {
        switch id {
        case "integration_codex":    return "Codex"
        case "integration_opencode": return "OpenCode"
        case "integration_zcode":    return "Zcode"
        case "integration_generic":  return "Agent"
        default:                     return "VS Code"
        }
    }

    @MainActor
    func processEvent(name: String, payload: [String: Any]) {
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
                PerchLog.write("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
                return
            }
        }

        let focused = state.focusId == taskId

        switch name {

        case "SessionStart":
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            PerchLog.write("SessionStart [\(taskId)] \(projectName) (\(sessionId.prefix(8)))")
            if state.isPresent { expandIfNeeded(to: .overview) }
            SoundEngine.shared.play("work")

        case "UserPromptSubmit":
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            state.updateTask(id: taskId, state: .thinking)
            if let prompt = payload["prompt"] as? String, !prompt.isEmpty {
                appendStep(id: taskId, step: String(prompt.prefix(60)))
            }
            if state.isPresent { expandIfNeeded(to: .overview) }

        case "PreToolUse":
            upsertTask(id: taskId, projectName: projectName, cwd: cwd)
            state.updateTask(id: taskId, state: .working)
            let tool = payload["tool_name"] as? String ?? "Tool"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = frenchStep(tool: tool, input: input)
            appendStep(id: taskId, step: step)
            PerchLog.write("PreToolUse [\(taskId)] \(step)")

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
    func expandIfNeeded(to view: IslandView) {
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
    func processPermissionRequest(fd: Int32, payload: [String: Any]) {
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
        PerchLog.write("PermissionRequest \(tool): \(command)")

        if pendingApprovalFD >= 0 {
            let old = pendingApprovalFD
            Task.detached { [weak self] in
                // "ask" → perch-hook outputs nothing → Claude Code re-asks
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                close(old)
            }
        }
        pendingApprovalFD = fd

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
    func upsertTask(id: String, projectName: String, cwd: String = "") {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].name = projectName
        if !cwd.isEmpty { state.tasks[idx].sessionCwd = cwd }
    }

    // MARK: - Badge helpers

    @MainActor
    func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    /// Resets an agent task to idle, clears steps and restores its default name.
    @MainActor
    func clearSession(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps = []
        state.tasks[idx].stepIndex = 0
        state.tasks[idx].name = defaultName(forTaskId: id)
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 20 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    // MARK: - Project name alias mapping

    func aliasProjectName(_ name: String) -> String {
        let aliases: [String: String] = [
            "perch": "Perch",
        ]
        return aliases[name.lowercased()] ?? name
    }

    // MARK: - French step labels

    func frenchStep(tool: String, input: [String: Any]) -> String {
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
}
