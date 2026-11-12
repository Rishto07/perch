<div align="center">

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/media/logo-light.png"><img src="docs/media/logo.png" alt="Perch" width="280"></picture>

# Perch

**A tiny AI coding-agent companion that lives at the top of your screen.**

Perch gives AI coding agents a lightweight persistent interface so you don't have to constantly switch between terminals, editors, and agent windows. Pip watches your sessions in your Mac's notch — or at the top of the screen on Windows — and lets you approve, answer, chat, and drop files without leaving what you're doing.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Tauri 2](https://img.shields.io/badge/Tauri-2-FFC131?logo=tauri&logoColor=black)
![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)
![GitHub stars](https://img.shields.io/github/stars/rishto07/perch?style=social)

**Latest release:** [Perch v0.1.1](https://github.com/Rishto07/perch/releases/tag/v0.1.1) — Universal 2 macOS + Windows x64

</div>

---

## What is Perch?

Perch is a small, always-visible companion for AI coding-agent sessions. Pip lives in the island at the top of your screen and surfaces what your agents are doing, what they need from you, and integrations you care about — in one glance.

**Who is it for?** Developers using Claude Code, Codex CLI, OpenCode, Zcode, or other shell agents who want session visibility and approvals without tabbing back to terminals.

## Features

- **Agent session visibility** — live pills per agent (Claude Code, Codex, OpenCode, Zcode, Claude App, plus a generic wrapper for anything else).
- **Permission approval** — Claude Code requests surface in the island with **Deny / Allow**.
- **Agent launch** — opening an agent starts its desktop app (VS Code for Claude sessions; Codex / OpenCode / Zcode CLIs via terminal where present); double-click a pill to launch, single-click to focus.
- **Smart agent switching** — when an agent starts or submits a prompt, Perch focuses that pill automatically; manual clicks are respected and alerts never steal the view.
- **Pip companion** — cursor-following eyes, mini-bot birds that flutter on hover, hop on click, gain personality per agent, and react to state transitions.
- **Built-in chat** — ask your provider from the island (Claude, OpenAI, Gemini, Mistral, Groq, OpenRouter, Ollama, …). Keys stay in the Keychain / Credential Manager.
- **File drop** — drop a file on the island; Pip swallows it for chat context or file-drop flows.
- **Window context (macOS)** — drag Pip onto a window to attach it as chat context.
- **Integrations** — optional cards for Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com.
- **Sounds** — 28 handcrafted WAVs shared between the macOS and Windows apps.
- **Private by design** — no telemetry, no account. The app only talks to services you configure.

## Download

### macOS — Perch v0.1.1 (Universal 2)

One download for Apple Silicon and Intel:

[Perch-macOS-0.1.1.dmg](https://github.com/Rishto07/perch/releases/download/v0.1.1/Perch-macOS-0.1.1.dmg)

### Windows — Perch v0.1.1 (x64)

[Perch-Windows-0.1.1-setup.exe](https://github.com/Rishto07/perch/releases/download/v0.1.1/Perch-Windows-0.1.1-setup.exe)

Full release page: [https://github.com/Rishto07/perch/releases/tag/v0.1.1](https://github.com/Rishto07/perch/releases/tag/v0.1.1)

## Platform support

| Platform | Status | Architecture | Distribution |
|----------|--------|--------------|--------------|
| macOS | Available | Universal 2 (`arm64` + `x86_64`) | DMG |
| Windows | Available | x64 | NSIS installer |
| Linux | Not released | — | — |

## Security / first launch

**macOS:** v0.1.1 is built unsigned (`CODE_SIGNING_ALLOWED=NO` in CI) and is not notarized. If Gatekeeper blocks the app, open **System Settings → Privacy & Security → Open Anyway** once (or right-click `Perch.app` → **Open**). The build intentionally ships unsigned until signing/notarization secrets are configured.

**Windows:** v0.1.1 is also unsigned and may trigger Microsoft SmartScreen/Defender. Only proceed past the prompt if you downloaded the installer from the official GitHub release and verified its checksum below.

## SHA-256 verification

```text
Windows:
E82909EE6C03538375C19990D6DD2885B5A893922781E0FF9477F0BEBC570D5A

macOS:
385A13D12FB9D03A07710C2DF1D34775BA55E64CE114A7B5D625FCD59D67BD54
```

PowerShell (Windows):

```powershell
Get-FileHash .\Perch-Windows-0.1.1-setup.exe -Algorithm SHA256
```

macOS:

```bash
shasum -a 256 Perch-macOS-0.1.1.dmg
```

Compare the output against the values above.

## Setup

Both apps share setup: Perch icon in the menu bar (macOS) or system tray (Windows) → **Settings…**

| What | Why | Where it goes |
|------|-----|---------------|
| Claude Code hooks | Live sessions + approvals | `~/.claude/settings.json` — Perch backs up, merges, and shows the diff before writing |
| Codex / OpenCode / Zcode / generic | Live sessions for other agents | Settings → Other coding agents → Install; adapters in [`agents/`](agents/) |
| Chat provider key | Chat + questions about files | Keychain (macOS) / Credential Manager (Windows) |
| Integrations | Pills and detail cards | Same stores, all optional |

If Perch isn't running, hooks exit immediately — your agents are never blocked.

## Agent integrations

Perch routes events by an `agent` tag to a per-agent pill.

| Agent | Pill | Events |
|-------|------|--------|
| Claude Code (`claude`) | VS Code | `~/.claude/settings.json` → `perch-hook` / `perch-hook.exe` (installed by the app) |
| OpenAI Codex (`codex`) | Codex | `agents/codex/install.sh` / `install.ps1` → same relay with `PERCH_AGENT=codex` |
| OpenCode (`opencode`) | OpenCode | `agents/opencode/perch.ts` plugin |
| Zcode (`zcode`) | Zcode | generic wrapper with `-Agent zcode` (no hooks API) |
| Anything else (`generic`, missing, unknown) | Claude App | `agents/generic/perch-run.sh` / `perch-run.ps1` around any command |

See [`agents/README.md`](agents/README.md) for the JSON protocol, transports, and the "never block the agent" contract. Full adapters live in `agents/codex/`, `agents/opencode/`, and `agents/generic/`; `agents/relay/` holds the macOS Unix-socket relay.

## Architecture

- **macOS** — native **Swift 6 / SwiftUI / AppKit** app (`Perch/`, XcodeGen project). Zero third-party dependencies. Pip is drawn in code (`Canvas` + `TimelineView`); sounds play from 28 WAVs in `Perch/Resources/sounds/`. Keychain for secrets.
- **Windows** — **Tauri 2** app (`windows/`): Rust backend + TypeScript/Vite frontend. Same island state machine, same sounds, Canvas-2D Pip. Credential Manager for secrets, CEF host policy (`tauri.conf.json` CSP).
- **Agent communication** — hook payloads carry `agent: claude|codex|opencode|zcode|generic` and route to the matching pill. macOS: Unix socket (`perch.sock`). Windows: named pipe (`\\.\pipe\perch-<sid>`) via `perch-hook.exe`. Only Claude's `PermissionRequest` blocks for approval — every other agent is observability-only.

## Pip

Pip is the animated island character shared by both apps. Cursor-tracking eyes, idle breathing/blinking, emotes, a launch greeting, and 28 sounds. The Windows mini-bot birds additionally follow your cursor, flutter on hover, hop on click (3 rapid clicks = dizzy), and "flock-react" when Pip gets excited — with a small personality per agent (wink/happy/proud/yawn). The `Pill` cards and the pip draw are both generated in code — no images or Lottie.

## Development

### macOS (Swift)

Requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/rishto07/perch.git
cd perch/Perch && xcodegen && open Perch.xcodeproj   # then ⌘R
```

Never edit `Perch.xcodeproj` by hand — change `project.yml` and re-run `xcodegen`. Geometry checks:

```bash
bash scripts/test-screen-geometry.sh
```

Release builds use Xcode archives; unsigned CI builds use `CODE_SIGNING_ALLOWED=NO`.

### Windows (Tauri)

Requirements: [Rust](https://rustup.rs), Node 20+, MSVC build tools, WebView2 (ships with Windows 10/11).

```powershell
cd perch/windows
npm install
npm run tauri dev      # live-reloading dev app
npm run pack           # NSIS installer → windows/release/
```

`npm run dev` alone serves the island in a browser for visual iterations. `npm run icons` regenerates the app/tray icons from `scripts/gen-icons.mjs`.

CI: `build.yml` (macOS), `release.yml` (tag `v*` → Universal DMG, `workflow_dispatch` supported), `windows.yml` (Windows build check + installer). Tests: `cargo test --workspace`, `npm run build` (`tsc --noEmit` + Vite), and `scripts/test-screen-geometry.sh`.

## Contributing

Issues and PRs are welcome — new integrations, emotes, sounds, and bug fixes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Roadmap

- **Planned:** Apple Developer signing + notarization; Windows code signing.
- **Exploring:** a dedicated `xcodebuild test` target; additional agent adapters.
- **Future:** distribution/updater improvements (Sparkle-style auto-updates).

## License

- **Code:** [Apache-2.0](LICENSE)
- **Brand/artwork:** Perch's name (Perch), character (Pip — drawn in code), icons (`windows/scripts/gen-icons.mjs`), and sounds (synthesized by `windows/scripts/gen-sounds.mjs`). See [LICENSE-ASSETS.md](LICENSE-ASSETS.md) and [NOTICE](NOTICE).

<div align="center">

**If Pip made you smile, a ⭐ helps a lot.**

[Repository](https://github.com/rishto07/perch)

</div>
