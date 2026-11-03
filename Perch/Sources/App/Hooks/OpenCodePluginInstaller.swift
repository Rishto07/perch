import Foundation

// MARK: - OpenCode plugin installer

extension HookServer {
    var opencodePluginText: String {
        opencodePlugin.replacingOccurrences(of: "\r\n", with: "\n") + "\n"
    }

    func pluginURLExists() -> Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/perch.ts").path)
    }

    // MARK: OpenCode (~/.config/opencode/plugins/perch.ts + opencode.json)

    func previewOpenCodeHooks(install: Bool) throws -> String {
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

    func writeOpenCodeHooks(install: Bool) throws -> String {
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
}
