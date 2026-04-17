#!/usr/bin/env bash
# on-task-created.sh — TaskCreated hook (Claude Code >= v2.1.84).
#
# Fires the instant the host dispatches an Agent / Task. Opens a pending
# entry in state-full.json.subagents_invoked[] with the real start timestamp
# so the downstream SubagentStop hook can close it (instead of estimating
# the start by subtracting duration_ms, which is what 0.2.x did).
#
# Payload (host-provided JSON on stdin, best-effort):
#   subagent_type       — canonical agent id (e.g. "tech-advisory-board:champion")
#   task_id             — unique invocation id
#   started_at          — ISO-8601 start time
#   description         — short task description from the dispatcher
#
# Budget: <200ms. Exit 0 on any failure — telemetry is best-effort.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone

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

subagent_type = (
    payload.get("subagent_type")
    or (payload.get("agent") or {}).get("type")
    or payload.get("agent_type")
    or "unknown"
)
task_id = (
    payload.get("task_id")
    or payload.get("id")
    or payload.get("invocation_id")
)
started_at = (
    payload.get("started_at")
    or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
)
description = payload.get("description") or payload.get("task")

sf_path = os.path.join(session_dir, "state-full.json")
sf = {}
if os.path.isfile(sf_path):
    try:
        with open(sf_path) as f:
            sf = json.load(f)
    except (OSError, json.JSONDecodeError):
        sf = {}

entry = {
    "subagent_type": subagent_type,
    "task_id": task_id,
    "started_at": started_at,
    "ended_at": None,
    "description": description,
}
entry = {k: v for k, v in entry.items() if v is not None or k == "ended_at"}

subs = sf.setdefault("subagents_invoked", [])
subs.append(entry)

try:
    with open(sf_path, "w") as f:
        json.dump(sf, f, indent=2, ensure_ascii=False)
except OSError:
    pass

# Also bump a lightweight counter in telemetry.json for observability
telemetry_path = os.path.join(session_dir, "telemetry.json")
telemetry = {}
if os.path.isfile(telemetry_path):
    try:
        with open(telemetry_path) as f:
            telemetry = json.load(f)
    except (OSError, json.JSONDecodeError):
        telemetry = {}

totals = telemetry.setdefault("totals", {})
totals["subagents_started"] = int(totals.get("subagents_started", 0)) + 1

try:
    with open(telemetry_path, "w") as f:
        json.dump(telemetry, f, indent=2, ensure_ascii=False)
except OSError:
    pass
PYEOF
