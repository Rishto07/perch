import Foundation

// MARK: - Embedded payloads
// The hook relay wrapper, the two Python relay scripts, and the OpenCode
// plugin, embedded verbatim so installs are byte-identical on every machine.

// MARK: - OpenCode plugin (~/.config/opencode/plugins/perch.ts)

let opencodePlugin = """
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
  const line = Buffer.from(JSON.stringify({ agent: AGENT, ...event }) + "\\n");
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
"""

// MARK: - perch-hook shell wrapper (same for both GitHub and App Store)

// MARK: - perch-hook shell wrapper (same for both GitHub and App Store)
// Invoked by Claude Code via /bin/sh or directly via shebang.
// Always exits 0 — never blocks Claude Code.
// Checks xcode-select before running python3 to avoid triggering the
// "install developer tools" dialog on machines without Xcode CLI tools.

let perchHookShellWrapper = """
#!/bin/sh
# Perch hook relay — always exits 0, never blocks Claude Code
HOOK_DIR="$(dirname "$0")"
if xcode-select -p >/dev/null 2>&1; then
    out=$(/usr/bin/python3 "$HOOK_DIR/perch-hook.py" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        printf '%s\\n' "$out"
    fi
fi
exit 0
"""

// MARK: - perch-hook Python relay (GitHub / non-sandboxed version)

let perchHookPythonGitHub = """
#!/usr/bin/env python3
# perch-hook.py — Perch hook relay for Claude Code (GitHub version)
# Reads JSON from stdin, forwards to Perch via Unix socket, translates response.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()
    # Agent tag — lets Perch route to the right pill. Claude's installer leaves
    # this as "claude"; other agents override via PERCH_AGENT (see agents/).
    payload.setdefault('agent', os.environ.get('PERCH_AGENT', 'claude'))

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Application Support/Perch/perch.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Perch's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Perch'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        # Claude Code will handle the absence of output (re-ask or default behaviour)
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""

// MARK: - perch-hook Python relay (App Store — socket in sandboxed container)

let perchHookPythonAppStore = """
#!/usr/bin/env python3
# perch-hook.py — Perch (App Store) hook relay for Claude Code
# Socket lives inside the sandboxed container; script runs outside the sandbox.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()
    # Agent tag — lets Perch route to the right pill. Claude's installer leaves
    # this as "claude"; other agents override via PERCH_AGENT (see agents/).
    payload.setdefault('agent', os.environ.get('PERCH_AGENT', 'claude'))

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Containers/com.perch.PerchAppStore/Data/perch.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Perch's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Perch'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        sys.exit(0)

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""
