#!/usr/bin/env bash
# check-gitignore-tab.sh — Determine whether the project's .gitignore
# already covers the .tab/ data directory.
#
# Emits a JSON payload on stdout that the Moderator (Phase -1) uses to
# decide whether to prompt the user once ("Add `.tab/` to .gitignore?").
# Status values:
#   already_ignored  — .tab/ matched by an entry (.tab or .tab/)
#   not_ignored      — .gitignore exists but does not cover .tab/
#   missing_gitignore— no .gitignore at the project root
#   opted_out        — user previously declined (flag in .tab/config.json)
#   not_git          — project is not a git repo (skip prompt silently)
#
# Budget: <100ms. Silent on errors (exits 0 with status="error").
set -uo pipefail

BASE="${CLAUDE_PROJECT_DIR:-$PWD}"
if git_root=$(git -C "$BASE" rev-parse --show-toplevel 2>/dev/null); then
    BASE="$git_root"
else
    printf '{"status":"not_git"}\n'
    exit 0
fi

GITIGNORE="$BASE/.gitignore"
CONFIG_JSON="$BASE/.tab/config.json"

# Check opt-out flag.
if [[ -f "$CONFIG_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    opted=$(python3 -c '
import json, sys
try:
    with open("'"$CONFIG_JSON"'") as f:
        c = json.load(f)
    print("1" if c.get("gitignore_prompt_seen") else "0")
except Exception:
    print("0")
' 2>/dev/null || echo 0)
    if [[ "$opted" == "1" ]]; then
        printf '{"status":"opted_out"}\n'
        exit 0
    fi
fi

if [[ ! -f "$GITIGNORE" ]]; then
    printf '{"status":"missing_gitignore","gitignore_path":"%s"}\n' "$GITIGNORE"
    exit 0
fi

# A line that exactly matches .tab, .tab/, or /.tab covers the directory.
if grep -Eq '^\s*/?\.tab/?\s*($|#)' "$GITIGNORE" 2>/dev/null; then
    printf '{"status":"already_ignored","gitignore_path":"%s"}\n' "$GITIGNORE"
    exit 0
fi

printf '{"status":"not_ignored","gitignore_path":"%s"}\n' "$GITIGNORE"
