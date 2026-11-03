import Foundation

// MARK: - PerchLog
// Unified file logger for Perch. Replaces the old nbLog / n8nLog helpers.
// Writes to ~/Library/Logs/Perch/perch.log and truncates the file when it
// grows past 1 MB so logs stay bounded.

enum PerchLog {
    private static let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Perch", isDirectory: true)
    private static let logURL = logDirectory.appendingPathComponent("perch.log")

    static func write(_ message: String) {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Bounded log a single MB at a time — drop the whole file rather than grow forever.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 1_000_000 {
            try? Data().write(to: logURL, options: .atomic)
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(stamp)] \(message)\n".utf8)
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
                return
            }
        }
        try? data.write(to: logURL)
    }
}
