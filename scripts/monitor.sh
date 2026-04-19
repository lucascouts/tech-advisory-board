#!/usr/bin/env bash
# monitor.sh — continuous session monitor for TAB.
#
# Complements scripts/statusline.sh. Where statusline is a pull-model snapshot
# re-rendered on every host tick, monitor emits a stream of JSON-line events
# as TAB state changes: phase transitions, subagent invocations/returns,
# budget crossings (warn/hard threshold), and MCP availability changes.
#
# Designed to be declared under the `monitors` key of .claude-plugin/plugin.json
# (Claude Code >= v2.1.105). The host keeps this process alive for the whole
# session, piping stdout into its native observability panel.
#
# Output contract: one JSON object per line (JSON Lines / ndjson). Every line
# carries at minimum:
#   { "at": "<ISO-8601>", "event": "<kind>", "session_id": "<id|null>", ... }
#
# Silent-exit rules:
#   - CLAUDE_CODE_REMOTE=true (host does not render monitors either)
#   - missing python3
#   - .tab/sessions/ does not exist
#
# Budget: idle poll is 2s; event emission is event-driven (no tight loop).
# Process exits cleanly on SIGTERM from the host.
set -uo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-false}" == "true" ]]; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    # Still emit a single heartbeat so the host knows the monitor attached
    printf '{"at":"%s","event":"attached","session_id":null,"note":"no-session-yet"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

# Trap SIGTERM so the host can shut us down cleanly.
trap 'exit 0' TERM INT

exec python3 - "$TAB_DIR/sessions" <<'PYEOF'
import json, os, sys, time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_append_ndjson

SESSIONS_DIR = sys.argv[1]
POLL_S = float(os.environ.get("TAB_MONITOR_POLL_S", "2.0"))

# Rotation caps for timeline-events.ndjson. See M2 in ANALISE-CRITICA.md.
# Browsers start struggling on synchronous parse beyond ~5-8MB, and the
# render-timeline.sh HTML does a single fetch. 10k lines is generous
# (≈100 bytes/event means ~1MB for 10k), so the 5MB bytes cap will fire
# first in normal use.
TIMELINE_MAX_LINES = int(os.environ.get("TAB_TIMELINE_MAX_LINES", "10000"))
TIMELINE_MAX_BYTES = int(os.environ.get("TAB_TIMELINE_MAX_BYTES", "5000000"))
TIMELINE_MAX_ROT   = int(os.environ.get("TAB_TIMELINE_MAX_ROTATIONS", "3"))

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def emit(event, session_id, **extra):
    line = {"at": now(), "event": event, "session_id": session_id, **extra}
    encoded = json.dumps(line, separators=(",", ":"))
    sys.stdout.write(encoded + "\n")
    sys.stdout.flush()
    # §3.6 — mirror into the session's timeline-events.ndjson so the
    # timeline HTML can replay the stream without a live host connection.
    # Rotates when either 10k lines or 5 MB is reached, keeping 3 old
    # generations. This caps total disk use at ~20 MB per session while
    # keeping the most recent events immediately available to the HTML.
    if session_id:
        try:
            atomic_append_ndjson(
                Path(SESSIONS_DIR) / session_id / "timeline-events.ndjson",
                line,
                max_lines=TIMELINE_MAX_LINES,
                max_bytes=TIMELINE_MAX_BYTES,
                max_rotations=TIMELINE_MAX_ROT,
                timeout_seconds=1.0,
            )
        except (OSError, TimeoutError):
            pass

def find_newest_session():
    best = None
    try:
        for entry in os.listdir(SESSIONS_DIR):
            if entry == "archived":
                continue
            sf = os.path.join(SESSIONS_DIR, entry, "state-full.json")
            if os.path.isfile(sf):
                mtime = os.path.getmtime(sf)
                if best is None or mtime > best[0]:
                    best = (mtime, entry, sf)
    except OSError:
        return None
    return best

def load_state(session_id):
    sd = os.path.join(SESSIONS_DIR, session_id)
    state = {}
    full = {}
    try:
        with open(os.path.join(sd, "state.json")) as f:
            state = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
    try:
        with open(os.path.join(sd, "state-full.json")) as f:
            full = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
    return state, full

emit("attached", None, poll_s=POLL_S)

prev_snapshot = None
prev_session_id = None
warned_soft = False
aborted_hard = False

while True:
    candidate = find_newest_session()
    if candidate is None:
        time.sleep(POLL_S)
        continue

    _, session_id, sf_path = candidate
    state, full = load_state(session_id)

    if session_id != prev_session_id:
        emit("session-activated", session_id,
             mode=state.get("mode"),
             phase=state.get("phase_completed"))
        prev_session_id = session_id
        prev_snapshot = None
        warned_soft = False
        aborted_hard = False

    phase = state.get("phase_completed")
    next_phase = state.get("next_phase")
    mode = state.get("mode")
    bc = state.get("budget_consumed") or {}
    cost = float(bc.get("cost_usd") or 0.0)
    cfg = state.get("config_snapshot") or {}
    budget_cfg = cfg.get("budget") or {}
    max_cost = float(budget_cfg.get("max_cost_per_session_usd") or 5.0)
    warn_at = float(budget_cfg.get("warn_at_usd") or (0.6 * max_cost))

    subagents = full.get("subagents_invoked") or []
    active_subagents = [s for s in subagents if s.get("ended_at") is None]
    active_count = len(active_subagents)

    snapshot = {
        "phase": phase,
        "next_phase": next_phase,
        "mode": mode,
        "active_count": active_count,
        "active_ids": [s.get("id") for s in active_subagents],
        "total_subagents": len(subagents),
    }

    if prev_snapshot is None:
        emit("snapshot", session_id,
             phase=phase, next_phase=next_phase, mode=mode,
             cost_usd=round(cost, 4), max_cost_usd=max_cost,
             active_count=active_count)
    else:
        if snapshot["phase"] != prev_snapshot["phase"]:
            emit("phase-advanced", session_id,
                 from_phase=prev_snapshot["phase"],
                 to_phase=snapshot["phase"],
                 next_phase=snapshot["next_phase"])
        if snapshot["total_subagents"] > prev_snapshot["total_subagents"]:
            started = subagents[prev_snapshot["total_subagents"]:]
            for s in started:
                emit("subagent-started", session_id,
                     agent_id=s.get("id"),
                     agent_type=s.get("type") or s.get("name"),
                     phase=phase)
        if snapshot["active_count"] < prev_snapshot["active_count"]:
            emit("subagent-returned", session_id,
                 active_count=snapshot["active_count"],
                 phase=phase)

    # Budget threshold events — emit once each
    if not warned_soft and cost >= warn_at and cost < max_cost:
        warned_soft = True
        emit("budget-warn", session_id,
             cost_usd=round(cost, 4), warn_at_usd=warn_at,
             max_cost_usd=max_cost)
    if not aborted_hard and cost >= max_cost:
        aborted_hard = True
        emit("budget-exceeded", session_id,
             cost_usd=round(cost, 4), max_cost_usd=max_cost)

    prev_snapshot = snapshot
    time.sleep(POLL_S)
PYEOF
