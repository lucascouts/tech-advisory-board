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
#
# Concurrency: telemetry.json and state-full.json are both updated under
# scripts/lib/json_atomic.py flocks. Multiple parallel SubagentStop events
# (common in Complete+ where 4-5 champions + 3-5 advisors return close
# together) serialize correctly, so totals don't lose increments and the
# matching step in state-full doesn't double-close entries.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

INPUT=$(cat || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_update

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
task_id = (
    payload.get("task_id")
    or payload.get("id")
    or payload.get("invocation_id")
)

# ── telemetry.json: totals rollup ────────────────────────────────────────
telemetry_path = Path(session_dir) / "telemetry.json"

def roll_totals(tel):
    totals = tel.setdefault("totals", {})
    totals["subagents_invoked"] = int(totals.get("subagents_invoked", 0)) + 1
    tokens_in = usage.get("input_tokens")
    tokens_out = usage.get("output_tokens")
    cost_usd = usage.get("cost_usd")
    if isinstance(tokens_in, (int, float)):
        totals["tokens_in"] = float(totals.get("tokens_in", 0)) + tokens_in
    if isinstance(tokens_out, (int, float)):
        totals["tokens_out"] = float(totals.get("tokens_out", 0)) + tokens_out
    if isinstance(cost_usd, (int, float)):
        totals["cost_usd"] = float(totals.get("cost_usd", 0.0)) + cost_usd
    totals["last_subagent_type"] = subagent_type
    totals["last_subagent_ended_at"] = ended_at
    return tel

try:
    atomic_update(telemetry_path, roll_totals, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass

# ── state-full.json: close matching pending entry, or append fallback ────
sf_path = Path(session_dir) / "state-full.json"

def _derive_duration_ms(s_started_at, s_ended_at):
    if s_started_at is None:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            t0 = datetime.strptime(s_started_at.rstrip("Z") + "Z", fmt)
            t1 = datetime.strptime(s_ended_at.rstrip("Z") + "Z", fmt)
            return int((t1 - t0).total_seconds() * 1000)
        except (ValueError, TypeError):
            continue
    return None

def close_or_append(sf):
    subs = sf.setdefault("subagents_invoked", [])
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
                derived = _derive_duration_ms(s.get("started_at"), ended_at)
                if derived is not None:
                    s["duration_ms"] = derived
            if usage:
                s["usage"] = usage
            closed = True
            break
    if not closed:
        entry = {
            "subagent_type": subagent_type,
            "started_at": started_at,
            "ended_at": ended_at,
            "duration_ms": duration_ms,
            "usage": usage or None,
        }
        entry = {k: v for k, v in entry.items() if v is not None}
        subs.append(entry)
    return sf

try:
    atomic_update(sf_path, close_or_append, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    pass
PYEOF
