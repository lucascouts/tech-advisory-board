#!/usr/bin/env bash
# apply-gitignore-tab.sh — Apply the user's choice on whether to ignore
# .tab/ in git. Invoked by the Moderator after asking the user once.
#
# Usage:
#   apply-gitignore-tab.sh --ignore       # append `.tab/` to .gitignore
#   apply-gitignore-tab.sh --opt-out      # persist flag; do not ask again
#
# Idempotent. Does nothing if the entry already exists or if the flag
# is already set.
set -euo pipefail

MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ignore)   MODE="ignore" ;;
        --opt-out)  MODE="opt_out" ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -z "$MODE" ]] && { echo "apply-gitignore-tab: --ignore or --opt-out required" >&2; exit 2; }

BASE="${CLAUDE_PROJECT_DIR:-$PWD}"
if git_root=$(git -C "$BASE" rev-parse --show-toplevel 2>/dev/null); then
    BASE="$git_root"
fi

GITIGNORE="$BASE/.gitignore"
CONFIG_JSON="$BASE/.tab/config.json"

if [[ "$MODE" == "ignore" ]]; then
    if [[ ! -f "$GITIGNORE" ]] || ! grep -Eq '^\s*/?\.tab/?\s*($|#)' "$GITIGNORE" 2>/dev/null; then
        {
            [[ -s "$GITIGNORE" ]] && tail -c1 "$GITIGNORE" | read -r _ || printf '\n'
            printf '# TAB plugin data (sessions, decisions, cache)\n.tab/\n'
        } >> "$GITIGNORE"
        echo "apply-gitignore-tab: appended .tab/ to $GITIGNORE"
    else
        echo "apply-gitignore-tab: .tab/ already ignored (no change)"
    fi
fi

# Persist opt-out flag (also set on --ignore so we don't ask again).
if command -v python3 >/dev/null 2>&1; then
    mkdir -p "$(dirname "$CONFIG_JSON")"
    python3 - "$CONFIG_JSON" <<'PYEOF'
import json, os, sys
p = sys.argv[1]
try:
    with open(p) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
cfg["gitignore_prompt_seen"] = True
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
fi
