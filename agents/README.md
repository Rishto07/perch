# Perch for every coding agent

Perch's island used to listen to Claude Code only. It now routes events by an
**`agent` tag** to a per-agent pill:

| `agent`    | Pill             | Colour    | How events arrive |
|------------|------------------|-----------|-------------------|
| `claude`   | VS Code          | `#F5F6F8` | `~/.claude/settings.json` → `perch-hook` / `perch-hook.exe` (installed by the app) |
| `codex`    | Codex            | `#34D399` | `agents/codex/install.sh` / `install.ps1` → same relay with `PERCH_AGENT=codex` |
| `opencode` | OpenCode         | `#F472B6` | `agents/opencode/perch.ts` plugin |
| `zcode`    | Zcode            | `#A78BFA` | generic wrapper with `-Agent zcode` (no hooks API) |
| `generic`  | Agent            | `#94A3B8` | `agents/generic/perch-run.sh` / `perch-run.ps1` around any command |
| *(missing)*| VS Code (Claude) | —         | backwards compatible default |

Anything else (e.g. `freebuff`) lands on the **generic** pill — shown, never dropped.

## Protocol (both platforms)

One JSON object per line, UTF-8, `\n`-terminated:

```json
{
  "agent": "codex",
  "hook_event_name": "PreToolUse",
  "session_id": "sess_abc",
  "cwd": "/path/to/project",
  "prompt": "user text (UserPromptSubmit)",
  "message": "notification / stop text",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" }
}
```

Only `hook_event_name` is required. Unknown events are ignored. `agent` is
optional (defaults to `claude`).

**Events:** `SessionStart` · `UserPromptSubmit` · `PreToolUse` · `PostToolUse` ·
`PostToolUseFailure` · `Notification` · `Stop` · `StopFailure` · `SessionEnd` ·
`SubagentStart` · `SubagentStop` · `PermissionRequest` (Claude-only).

**Transports:**
- macOS: Unix socket `~/Library/Application Support/Perch/perch.sock`
  (GitHub build) or `~/Library/Containers/com.perch.PerchAppStore/Data/perch.sock`
  (App Store build). See `agents/relay/perch-relay.py`.
- Windows: named pipe `\\.\pipe\perch-<sid>` via
  `%LOCALAPPDATA%\Perch\bin\perch-hook.exe <Event> <agent>` on stdin.

**Rules every adapter follows** (the "never block the agent" contract):
1. Fire-and-forget with a short timeout (~300 ms connect). Perch closed → exit 0.
2. Only Claude's `PermissionRequest` waits for a decision (up to ~110 s).
   Every other agent's approval-shaped event is observability-only — the
   terminal stays in charge, the pill just lights up.

## Setup per agent

### Codex CLI
- Easiest: Settings → Other coding agents → Install (or Connect all).
  Detects the CLI, backs up `~/.codex/hooks.json`, merges, shows the diff.
- Manual: `sh agents/codex/install.sh` (backs up `~/.codex/hooks.json`,
  merges, `--uninstall` to remove). Override relay with `HOOK_BIN=…`.
- Windows: `powershell -ExecutionPolicy Bypass -File agents\codex\install.ps1`
  (`-Uninstall` to remove). Needs one Perch launch first (installs the relay).
- `agents/codex/hooks.json` is the same config as documentation.

### OpenCode
Easiest: Settings → Other coding agents → Install. Manual fallback below.
Copy `agents/opencode/perch.ts` to `~/.config/opencode/plugins/perch.ts`
(or `<project>/.opencode/plugins/perch.ts`) and register it in
`opencode.json` via `"plugin"`. Needs a Perch launch first (relay).

### Zcode (and Freebuff, or anything without hooks)
No hooks API → wrap the command:
- macOS/Linux: `sh agents/generic/perch-run.sh --agent zcode --prompt "task" -- zcode …`
- Windows: `agents\generic\perch-run.ps1 -Agent zcode -Prompt "task" -- zcode …`
- Exit code decides the end state: `0` → finished jump, otherwise error.
