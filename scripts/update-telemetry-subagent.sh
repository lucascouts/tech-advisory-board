#!/usr/bin/env bash
# update-telemetry-subagent.sh — SubagentStop hook.
# Increments subagents_invoked counter in telemetry.json and appends an
# entry to state-full.json.subagents_invoked[] for the latest non-archived
# TAB session. Non-blocking.
#
# Input: JSON on stdin from the host hook invocation. Fields potentially
# consumed (best-effort; host payload varies):
#   subagent_type        — fully-qualified subagent id
#   started_at / ended_at — ISO-8601 timestamps
#   duration_ms          — if provided
#   usage                — token / cost rollup
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

INPUT=$(cat || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone

try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
sessions_dir = sys.argv[2]

# Find newest non-archived session
candidates = []
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        path = os.path.join(sessions_dir, entry)
        state = os.path.join(path, "state.json")
        if os.path.isfile(state):
            candidates.append((os.path.getmtime(state), path))
except Exception:
    sys.exit(0)

if not candidates:
    sys.exit(0)

candidates.sort(reverse=True)
session_dir = candidates[0][1]

subagent_type = (
    payload.get("subagent_type")
    or (payload.get("agent") or {}).get("type")
    or payload.get("agent_type")
    or "unknown"
)
ended_at = payload.get("ended_at") or datetime.now(timezone.utc).isoformat()
started_at = payload.get("started_at")
duration_ms = payload.get("duration_ms")
usage = payload.get("usage") or {}

# Update telemetry.json
telemetry_path = os.path.join(session_dir, "telemetry.json")
telemetry = {}
if os.path.isfile(telemetry_path):
    try:
        with open(telemetry_path) as f:
            telemetry = json.load(f)
    except Exception:
        telemetry = {}

totals = telemetry.setdefault("totals", {})
totals["subagents_invoked"] = int(totals.get("subagents_invoked", 0)) + 1
# Running token / cost accumulators (best-effort)
tokens_in = usage.get("input_tokens")
tokens_out = usage.get("output_tokens")
cost_usd = usage.get("cost_usd")
if isinstance(tokens_in, (int, float)):
    totals["tokens_in"] = float(totals.get("tokens_in", 0)) + tokens_in
if isinstance(tokens_out, (int, float)):
    totals["tokens_out"] = float(totals.get("tokens_out", 0)) + tokens_out
if isinstance(cost_usd, (int, float)):
    totals["cost_usd"] = float(totals.get("cost_usd", 0.0)) + cost_usd
totals.setdefault("last_subagent_type", subagent_type)
totals["last_subagent_type"] = subagent_type
totals["last_subagent_ended_at"] = ended_at

try:
    with open(telemetry_path, "w") as f:
        json.dump(telemetry, f, indent=2, ensure_ascii=False)
except Exception:
    pass

# Append to state-full.json.subagents_invoked[]
sf_path = os.path.join(session_dir, "state-full.json")
sf = {}
if os.path.isfile(sf_path):
    try:
        with open(sf_path) as f:
            sf = json.load(f)
    except Exception:
        sf = {}

entry = {
    "subagent_type": subagent_type,
    "started_at": started_at,
    "ended_at": ended_at,
    "duration_ms": duration_ms,
    "usage": usage or None,
}
# Drop None-valued keys for compactness
entry = {k: v for k, v in entry.items() if v is not None}

subs = sf.setdefault("subagents_invoked", [])
# Best-effort: if there is an open entry for the same type without
# ended_at, close it rather than duplicating. With the TaskCreated hook in
# place (Claude Code >= v2.1.84) the pending entry carries the real
# started_at and task_id — we reuse them and only append a fallback entry
# if no match is found (older hosts).
task_id = payload.get("task_id") or payload.get("id") \
          or payload.get("invocation_id")
closed = False
for s in reversed(subs):
    matches_task_id = (task_id is not None
                       and s.get("task_id") == task_id)
    matches_type_open = (s.get("subagent_type") == subagent_type
                         and s.get("ended_at") is None)
    if matches_task_id or matches_type_open:
        s["ended_at"] = ended_at
        if duration_ms is not None:
            s["duration_ms"] = duration_ms
        elif s.get("started_at"):
            # Derive duration when the host did not pass one and we now
            # have real started_at from TaskCreated.
            try:
                from datetime import datetime
                fmt = "%Y-%m-%dT%H:%M:%SZ"
                t0 = datetime.strptime(s["started_at"].rstrip("Z") + "Z", fmt)
                t1 = datetime.strptime(ended_at.rstrip("Z") + "Z", fmt)
                s["duration_ms"] = int((t1 - t0).total_seconds() * 1000)
            except (ValueError, TypeError):
                pass
        if usage:
            s["usage"] = usage
        closed = True
        break
if not closed:
    subs.append(entry)

try:
    with open(sf_path, "w") as f:
        json.dump(sf, f, indent=2, ensure_ascii=False)
except Exception:
    pass
PYEOF
