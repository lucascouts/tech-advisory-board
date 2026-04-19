#!/usr/bin/env bash
# on-subagent-start.sh — SubagentStart hook (native pair of SubagentStop).
#
# Host-provided start timestamp is more accurate than TaskCreated's moment
# (which fires when the subagent is queued, not when it begins executing).
# We record started_at_subagent on the matching state-full.subagents_invoked[]
# entry so the timeline Gantt (§3.6) shows real wall-clock start times.
#
# Matching strategy:
#   1. task_id if provided by host
#   2. most recent entry with status == 'pending' and matching subagent_type
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin.
# Budget: <200ms. Non-blocking.
#
# Concurrency: read-modify-write on state-full.json goes through
# scripts/lib/json_atomic.py so two parallel subagent starts don't
# clobber each other's started_at_subagent stamps.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[[ -n "$INPUT" ]] || exit 0

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_update

try:
    ev = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
sessions_dir = sys.argv[2]

best = None
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        sf = os.path.join(sessions_dir, entry, "state-full.json")
        if os.path.isfile(sf):
            mtime = os.path.getmtime(sf)
            if best is None or mtime > best[0]:
                best = (mtime, entry, sf)
except OSError:
    sys.exit(0)

if not best:
    sys.exit(0)

_, _, sf_path = best

task_id = ev.get("task_id") or ev.get("id")
agent_type = ev.get("subagent_type") or ev.get("agent_type")
now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def set_started_at_subagent(full):
    subs = full.get("subagents_invoked") or []
    target = None
    if task_id:
        for s in subs:
            if s.get("task_id") == task_id or s.get("id") == task_id:
                target = s
                break
    if target is None and agent_type:
        for s in reversed(subs):
            if s.get("ended_at"):
                continue
            candidate_type = (
                s.get("type") or s.get("name") or s.get("subagent_type")
            )
            if candidate_type == agent_type:
                target = s
                break
    if target is not None and not target.get("started_at_subagent"):
        target["started_at_subagent"] = now_iso
    return full

try:
    atomic_update(Path(sf_path), set_started_at_subagent, default={},
                  timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass
PYEOF
