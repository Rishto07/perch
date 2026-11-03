import Foundation

// MARK: - Hook install support
// Shared helpers for the hook installers (Claude, Codex, OpenCode):
// hook command matching, JSON read/write helpers, fingerprints, backups.

extension HookServer {
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

    static func cliOnPath(_ name: String) -> Bool {
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

    static func readJSONFile(_ url: URL) throws -> [String: Any] {
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

    static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in data {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    static func fileFingerprint(_ url: URL) -> String {
        (try? Data(contentsOf: url)).map { fnv1a($0) } ?? fnv1a(Data())
    }

    static func datedBackupURL(for url: URL) -> URL {
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

}
