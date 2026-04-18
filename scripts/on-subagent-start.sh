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
# Silent-exit on: missing python3, missing TAB/sessions, malformed stdin.
# Budget: <200ms. Non-blocking.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[[ -n "$INPUT" ]] || exit 0

python3 - "$TAB_DIR/sessions" <<PYEOF 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone

payload_raw = """$INPUT"""
sessions_dir = sys.argv[1]

try:
    ev = json.loads(payload_raw)
except Exception:
    sys.exit(0)

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

_, session_id, sf_path = best

try:
    with open(sf_path) as f:
        full = json.load(f)
except Exception:
    sys.exit(0)

subs = full.get("subagents_invoked") or []
task_id = ev.get("task_id") or ev.get("id")
agent_type = ev.get("subagent_type") or ev.get("agent_type")
now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

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
        if (s.get("type") or s.get("name") or s.get("subagent_type")) == agent_type:
            target = s
            break

if target is None:
    sys.exit(0)

if not target.get("started_at_subagent"):
    target["started_at_subagent"] = now_iso

try:
    with open(sf_path, "w") as f:
        json.dump(full, f, indent=2, ensure_ascii=False)
except OSError:
    pass
PYEOF
