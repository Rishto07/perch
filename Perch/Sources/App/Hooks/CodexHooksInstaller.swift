import Foundation

// MARK: - Codex hooks installer

extension HookServer {
    // MARK: Codex (~/.codex/hooks.json, Codex matcher schema)

    func codexHookCommand(event: String) -> String {
        let exe = Self.hookScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(exe)\" \(event) codex"
    }

    func previewCodexHooks(install: Bool) throws -> String {
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

    func writeCodexHooks(install: Bool) throws -> String {
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

}
