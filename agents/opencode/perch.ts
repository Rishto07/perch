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
  const line = Buffer.from(JSON.stringify({ agent: AGENT, ...event }) + "\n");
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
