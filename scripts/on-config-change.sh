#!/usr/bin/env bash
# on-config-change.sh — ConfigChange hook.
#
# Fires when Claude Code detects a mutation to one of the configuration
# surfaces: user_settings, project_settings, local_settings,
# policy_settings, or skills. Records the event into
# state-full.json.config_changes[] for the current session so that the
# Moderator can note "config shifted mid-session" if a decision relies
# on a now-stale config_snapshot.
#
# Payload (host-provided JSON on stdin, best-effort):
#   source      — one of user_settings | project_settings | local_settings | policy_settings | skills
#   file_path   — absolute path to the mutated file (optional)
#
# Budget: <200ms. Exit 0 on any failure — telemetry is best-effort.
#
# Non-blocking: ConfigChange is an observability hook, never gate the
# session on it.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_update

try:
    payload = json.loads(sys.argv[1])
except (ValueError, TypeError):
    sys.exit(0)
sessions_dir = sys.argv[2]

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
    "source": payload.get("source") or "unknown",
}
fp = payload.get("file_path")
if fp:
    event["file_path"] = fp

sf_path = Path(session_dir) / "state-full.json"

def append_change(sf):
    sf.setdefault("config_changes", []).append(event)
    return sf

try:
    atomic_update(sf_path, append_change, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass
PYEOF
