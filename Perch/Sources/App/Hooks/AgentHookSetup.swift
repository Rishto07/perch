import Foundation

// MARK: - Agent hook preview/write (Codex + OpenCode)
// Claude keeps its own installer above; this section covers the rest with
// the same backup-then-diff-then-write guarantees. Zcode and anything
// without a hooks API are status-only (the UI shows the wrapper command).

extension HookServer {
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

}
