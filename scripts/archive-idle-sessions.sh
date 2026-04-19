#!/usr/bin/env bash
# archive-idle-sessions.sh — SessionEnd hook.
# Redundant safety net: invokes init-dir (which archives idle sessions)
# so that archival happens even if the user never triggered the tab skill.
# Non-blocking. <500ms budget.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"

[[ -d "$TAB_DIR/sessions" ]] || exit 0

INIT_BIN="${CLAUDE_PLUGIN_ROOT:-}/bin/init-dir"
[[ -x "$INIT_BIN" ]] || exit 0

"$INIT_BIN" --base "${CLAUDE_PROJECT_DIR:-$PWD}" >/dev/null 2>&1 || true

exit 0
