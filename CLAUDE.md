# Perch — guide for AI coding agents

Perch is a native macOS app: Pip, a small animated character living in the MacBook notch (or a top bar on other Macs / Windows), shows coding-agent sessions (Claude Code, Codex, OpenCode, Zcode, generic) and a few integrations, and lets the user approve, answer, chat and drop files from the notch.

## Where things are
- `Perch/Sources/App/` — all Swift code. `Perch/Resources/sounds/` — the 28 WAV sounds. `Perch/project.yml` — XcodeGen project (never edit the `.xcodeproj` by hand).
- `windows/` — the Windows port (Tauri 2 + Rust + TypeScript).
- `agents/` — multi-agent adapters: `agents/README.md` is the protocol doc; `codex/`, `opencode/`, `generic/` hold installers.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French, inherited).
- `design/prototype/perch-buddy.html` — original prototype, the visual source of truth. `design/captures/` — target screenshots.
- `docs/*.html` — the GitHub Pages site (privacy, terms, support, legal notice).

## Build
```
cd Perch && xcodegen && xcodebuild -scheme Perch -configuration Debug build
```

## Rules
- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. The character is drawn in code (`Canvas` + `TimelineView`), no Rive/Lottie/images.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block the agent: if the app doesn't answer, the hook exits immediately. Only Claude Code's `PermissionRequest` waits (blocking approvals stay Claude-only).
- Hook payloads carry `agent: claude|codex|opencode|zcode|generic` (missing → claude) and route to per-agent pills. Never drop unknown agents — they land on the generic pill.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a permission without an explicit click.
- Performance: 0 % CPU when the island is hidden.
- Keep the bundle identifiers `com.perch.Perch` / `com.perch.PerchAppStore` (Keychain items, preferences and permissions depend on them). Hook commands matching `HookServer.isOwnHookCommand` are ours to upgrade/remove.
- Visual changes must match the prototype and the screenshots in `design/captures/`.
