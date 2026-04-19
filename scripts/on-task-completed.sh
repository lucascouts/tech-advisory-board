#!/usr/bin/env bash
# on-task-completed.sh — TaskCompleted hook (Claude Code ≥ v2.1.84).
#
# Fires when the host marks a task complete via TaskCompleted. Complements
# on-task-created.sh + update-telemetry-subagent.sh by:
#
#   1. Closing the matching entry in state-full.json.subagents_invoked[]
#      if SubagentStop didn't already (e.g. native stall timeout killed
#      the subagent mid-stream — the host may emit TaskCompleted without
#      a paired SubagentStop).
#   2. Incrementing telemetry.json.totals.tasks_completed for parity with
#      tasks_started from the TaskCreated hook.
#
# Both steps are idempotent. If SubagentStop already closed the entry
# with ended_at populated, this script leaves it untouched.
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin.
# Budget: <200ms. Non-blocking (never exits 2).
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

# Locate newest non-archived session
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

task_id = (
    payload.get("task_id")
    or payload.get("id")
    or payload.get("invocation_id")
)
success = payload.get("success", payload.get("ok", True))
now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
ended_at = payload.get("completed_at") or payload.get("ended_at") or now_iso

# ── state-full.json: close matching pending entry if still open ────────
sf_path = Path(session_dir) / "state-full.json"

def close_if_open(sf):
    subs = sf.setdefault("subagents_invoked", [])
    if not task_id:
        return sf
    for s in subs:
        matches = (
            s.get("task_id") == task_id
            or s.get("id") == task_id
            or s.get("invocation_id") == task_id
        )
        if matches and s.get("ended_at") is None:
            s["ended_at"] = ended_at
            s["closed_by"] = "TaskCompleted"
            if success is False:
                s["success"] = False
            break
    return sf

try:
    atomic_update(sf_path, close_if_open, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass

# ── telemetry.json: increment tasks_completed counter ──────────────────
telemetry_path = Path(session_dir) / "telemetry.json"

def bump_completed(tel):
    totals = tel.setdefault("totals", {})
    totals["tasks_completed"] = int(totals.get("tasks_completed", 0)) + 1
    if success is False:
        totals["tasks_failed"] = int(totals.get("tasks_failed", 0)) + 1
    return tel

try:
    atomic_update(telemetry_path, bump_completed, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass
PYEOF
