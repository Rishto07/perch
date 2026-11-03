#!/bin/sh
# Install Perch hooks for Codex CLI (macOS/Linux).
# Merges Codex lifecycle hooks into ~/.codex/hooks.json without touching
# anyone else's entries. Dated backup first, like the Claude installer.
# Usage: sh agents/codex/install.sh [--uninstall]
set -eu

HOOK_BIN="${HOOK_BIN:-$HOME/Library/Application Support/Perch/perch-hook}"
SETTINGS="$HOME/.codex/hooks.json"
UNINSTALL=0
[ "${1:-}" = "--uninstall" ] && UNINSTALL=1

if [ ! -x "$HOOK_BIN" ]; then
  echo "error: perch-hook not found at $HOOK_BIN" >&2
  echo "Launch Perch once first (it installs perch-hook), or set HOOK_BIN." >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
echo "backup: $SETTINGS.bak-$STAMP"

export HOOK_BIN UNINSTALL SETTINGS
/usr/bin/python3 - <<'EOF'
import json, os

settings_path = os.environ["SETTINGS"]
hook_bin = os.environ["HOOK_BIN"]
uninstall = os.environ["UNINSTALL"] == "1"
cmd = 'PERCH_AGENT=codex "%s"' % hook_bin.replace('"', '\\"')
events = ["SessionStart", "SessionEnd", "UserPromptSubmit",
          "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "Notification", "Stop", "StopFailure"]

with open(settings_path) as f:
    data = json.load(f) or {}
hooks = data.get("hooks") or {}

def is_ours(entry):
    for h in entry.get("hooks", []):
        c = h.get("command", "")
        if "perch-hook" in c:
            return True
    return False

for ev in events:
    keep = [e for e in hooks.get(ev, []) if not is_ours(e)]
    if not uninstall:
        keep.append({"matcher": "", "hooks": [
            {"type": "command", "command": cmd, "timeout": 10}]})
    if keep:
        hooks[ev] = keep
    elif ev in hooks:
        del hooks[ev]

data["hooks"] = hooks
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("uninstalled" if uninstall else "installed: %s" % settings_path)
EOF
