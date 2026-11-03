#!/bin/sh
# perch-run — wrap ANY coding agent so Perch shows its session.
# Usage:
#   perch-run --agent zcode --prompt "refactor auth" -- zcode run --task refactor
#   perch-run -- codex exec "fix the flaky test"
#   PERCH_AGENT=freebuff perch-run -- freebuff "add dark mode"
#
# Sends SessionStart + UserPromptSubmit, runs the command, then Stop (or
# StopFailure on non-zero exit). Fire-and-forget: Perch closed costs nothing.
set -eu

AGENT="${PERCH_AGENT:-generic}"
PROMPT=""
if [ "${1:-}" = "--agent" ]; then AGENT="$2"; shift 2; fi
if [ "${1:-}" = "--prompt" ]; then PROMPT="$2"; shift 2; fi
if [ "${1:-}" = "--" ]; then shift; fi
if [ "$#" -eq 0 ]; then echo "usage: perch-run [--agent NAME] [--prompt TEXT] -- <command…>" >&2; exit 2; fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RELAY_BIN="$HOME/Library/Application Support/Perch/perch-hook"
RELAY_PY="$SCRIPT_DIR/../relay/perch-relay.py"
if [ ! -x "$RELAY_BIN" ]; then RELAY_BIN=""; fi

send() { # $1 = event JSON
  if [ -n "$RELAY_BIN" ]; then
    printf '%s\n' "$1" | PERCH_AGENT="$AGENT" "$RELAY_BIN" >/dev/null 2>&1 || true
  else
    printf '%s\n' "$1" | PERCH_AGENT="$AGENT" /usr/bin/python3 "$RELAY_PY" >/dev/null 2>&1 || true
  fi
}

SESSION="wrap-$$-$(date +%s)"
CWD="$(pwd)"
ESCAPED_PROMPT="$(printf '%s' "${PROMPT:-$*}" | sed 's/"/\\"/g')"

send "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\"}"
send "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\",\"prompt\":\"$ESCAPED_PROMPT\"}"

CODE=0
"$@" || CODE=$?

if [ "$CODE" -eq 0 ]; then
  send "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\"}"
else
  send "{\"hook_event_name\":\"StopFailure\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\"}"
fi
exit "$CODE"
