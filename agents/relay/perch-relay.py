#!/usr/bin/env python3
"""perch-relay.py — forward one hook event to Perch (macOS/Linux).

Reads a JSON object on stdin, tags it with the coding agent, and delivers it
to the Perch socket. Fire-and-forget: never blocks the caller, never fails
loudly. Observability only — blocking approvals stay Claude-only (perch-hook).

Usage:
    echo '{"hook_event_name":"PreToolUse",...}' | PERCH_AGENT=codex python3 perch-relay.py
    echo '...' | python3 perch-relay.py --agent opencode

Sockets tried in order (first that accepts wins):
    ~/Library/Application Support/Perch/perch.sock   (GitHub build)
    ~/Library/Containers/com.perch.PerchAppStore/Data/perch.sock  (App Store build)
"""
import sys
import json
import os
import socket

SOCKETS = [
    "~/Library/Application Support/Perch/perch.sock",
    "~/Library/Containers/com.perch.PerchAppStore/Data/perch.sock",
]

AGENTS = {"claude", "codex", "opencode", "zcode", "generic"}


def normalise_agent(raw: str) -> str:
    a = (raw or "").strip().lower()
    if a in ("claude", "claude-code", "claudecode", ""):
        return "claude"
    if a in ("opencode", "open-code"):
        return "opencode"
    if a in ("zcode", "z-code"):
        return "zcode"
    if a in ("codex",):
        return "codex"
    if a in ("generic", "other", "unknown"):
        return "generic"
    return "generic"  # somebody's agent: show it, don't drop it


def main() -> None:
    agent = "claude"
    args = sys.argv[1:]
    if "--agent" in args:
        i = args.index("--agent")
        if i + 1 < len(args):
            agent = args[i + 1]
    agent = normalise_agent(os.environ.get("PERCH_AGENT", agent))

    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return
    if not isinstance(payload, dict):
        return

    payload.setdefault("agent", agent)
    if not payload.get("cwd"):
        try:
            payload["cwd"] = os.getcwd()
        except Exception:
            pass
    # PermissionRequest from a non-Claude agent must never block: downgrade to
    # a plain working ping so the pill still lights up.
    if payload.get("hook_event_name") == "PermissionRequest" and payload["agent"] != "claude":
        payload["hook_event_name"] = "PreToolUse"
        payload.setdefault("tool_name", "Approval")

    line = (json.dumps(payload) + "\n").encode()
    for sock_path in SOCKETS:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.3)
            s.connect(os.path.expanduser(sock_path))
            s.sendall(line)
            s.close()
            return
        except Exception:
            continue
    # Perch isn't running — exit cleanly, never block the agent.


main()
