#!/usr/bin/env bash
# on-worktree-create.sh — WorktreeCreate hook.
#
# Fires when Claude Code creates a new worktree (typically from the
# rechallenge skill, which isolates ADR re-tests). Appends an event to
# <session>/worktrees.ndjson so the maintainer can audit worktree
# lifecycle without relying on Bash exit status from EnterWorktree.
#
# Payload (host-provided JSON on stdin, best-effort):
#   worktree_path — absolute path to the new worktree (required per doc)
#   session_id    — host session id (not TAB session id)
#
# Budget: <200ms. Exit 0 on any failure — observability is best-effort
# and never gates session progress.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" create <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
try:
    from json_atomic import atomic_append_ndjson
except ImportError:
    sys.exit(0)

try:
    payload = json.loads(sys.argv[1])
except (ValueError, TypeError):
    sys.exit(0)
sessions_dir = sys.argv[2]
action = sys.argv[3]

best = None
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        sf = os.path.join(sessions_dir, entry, "state.json")
        if os.path.isfile(sf):
            mtime = os.path.getmtime(sf)
            if best is None or mtime > best[0]:
                best = (mtime, entry, sf)
except OSError:
    sys.exit(0)

if best is None:
    sys.exit(0)

session_dir = os.path.dirname(best[2])
event = {
    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "action": action,
    "worktree_path": payload.get("worktree_path"),
    "host_session_id": payload.get("session_id"),
}

try:
    atomic_append_ndjson(
        Path(session_dir) / "worktrees.ndjson",
        event,
        timeout_seconds=2.0,
    )
except (OSError, TimeoutError, TypeError):
    pass
PYEOF
