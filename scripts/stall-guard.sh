#!/usr/bin/env bash
# stall-guard.sh — background monitor that detects subagents stuck
# without a SubagentStop after a configurable threshold (default 30min).
#
# Declared under the `monitors` key of .claude-plugin/plugin.json
# (via monitors/monitors.json; Claude Code ≥ v2.1.105). The host
# keeps this process alive for the session and routes every stdout
# line to Claude as a notification.
#
# Why this is needed even with host-side stall detection:
#   Claude Code ≥ v2.1.113 kills subagents that stall mid-stream
#   after 10 minutes. Stalls BEFORE first token (MCP hangs during
#   setup, external service rate-limits) are not covered, and
#   hosts older than v2.1.113 lack the native timeout entirely.
#   This guard fires at 30min — well past the native 10min — so
#   it only triggers as a second line of defense.
#
# Output contract: one JSON line per detected stall. Shape:
#   {"at":"<iso>","event":"stall-detected","session_id":"...",
#    "subagent_type":"...","started_at":"...","age_seconds":1820,
#    "threshold_seconds":1800}
#
# Also appends the same record to <session>/stalls.json so audit
# survives the host process.
#
# Silent-exit rules (match scripts/monitor.sh):
#   - CLAUDE_CODE_REMOTE=true  (host doesn't render monitors remotely)
#   - python3 missing
#   - .tab/sessions/ missing
#
# Tunables (env):
#   TAB_STALL_THRESHOLD_SECONDS  — default 1800 (30 min)
#   TAB_STALL_POLL_SECONDS       — default 60
set -uo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-false}" == "true" ]]; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
if [[ ! -d "$TAB_DIR/sessions" ]]; then
    # Emit an attached heartbeat and exit; host keeps no-op monitors
    # out of the stream.
    printf '{"at":"%s","event":"stall-guard-attached","note":"no-session-yet"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

trap 'exit 0' TERM INT

exec python3 - "$TAB_DIR/sessions" <<'PYEOF'
import json, os, sys, time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_append_ndjson

SESSIONS_DIR = sys.argv[1]
THRESHOLD_S = int(os.environ.get("TAB_STALL_THRESHOLD_SECONDS", "1800"))
POLL_S = float(os.environ.get("TAB_STALL_POLL_SECONDS", "60"))

# Dedupe: emit each (session_id, task_id) stall at most once per process
# life. We re-emit if the age crosses a second multiple of THRESHOLD_S
# (i.e. still stuck 60 min later).
_seen = {}   # (sid, task_id) -> last_bucket_emitted

def now_utc():
    return datetime.now(timezone.utc)

def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_iso(s):
    if not s:
        return None
    try:
        # Accept both "...Z" and "...+00:00" forms
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None

def iter_sessions():
    try:
        for entry in os.listdir(SESSIONS_DIR):
            if entry == "archived":
                continue
            path = os.path.join(SESSIONS_DIR, entry)
            if os.path.isdir(path):
                yield entry, path
    except OSError:
        return

def check_session(sid, session_path, now):
    sf = os.path.join(session_path, "state-full.json")
    if not os.path.isfile(sf):
        return
    try:
        with open(sf) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return

    for entry in data.get("subagents_invoked", []) or []:
        if not isinstance(entry, dict):
            continue
        if entry.get("ended_at") is not None:
            continue
        # Prefer the more accurate started_at_subagent (SubagentStart
        # payload) over started_at (TaskCreated payload).
        started_at = parse_iso(entry.get("started_at_subagent")
                               or entry.get("started_at"))
        if started_at is None:
            continue
        age = (now - started_at).total_seconds()
        if age < THRESHOLD_S:
            continue

        task_id = entry.get("task_id") or entry.get("id") or entry.get("invocation_id")
        key = (sid, task_id, entry.get("subagent_type"))
        # Emit at threshold crossing and every THRESHOLD_S after that.
        bucket = int(age // THRESHOLD_S)
        if _seen.get(key) == bucket:
            continue
        _seen[key] = bucket

        record = {
            "at": iso(now),
            "event": "stall-detected",
            "session_id": sid,
            "subagent_type": entry.get("subagent_type"),
            "task_id": task_id,
            "started_at": iso(started_at),
            "age_seconds": int(age),
            "threshold_seconds": THRESHOLD_S,
            "bucket": bucket,
            "note": (
                "Subagent has not reported SubagentStop within the stall "
                "threshold. Host native stall detection (Claude Code "
                "≥ v2.1.113) kills at ~10 min; this is a second-line "
                "alert at 30 min+."
            ),
        }

        # Stream to host (becomes a notification for Claude)
        sys.stdout.write(json.dumps(record, separators=(",", ":")) + "\n")
        sys.stdout.flush()

        # Persist to <session>/stalls.json — ndjson so a long session
        # with multiple stalls keeps an audit trail.
        try:
            atomic_append_ndjson(
                Path(session_path) / "stalls.ndjson",
                record,
                max_lines=1000,
                max_bytes=500_000,
                max_rotations=2,
                timeout_seconds=1.0,
            )
        except (OSError, TimeoutError):
            pass

# Heartbeat on attach
sys.stdout.write(json.dumps({
    "at": iso(now_utc()),
    "event": "stall-guard-attached",
    "threshold_seconds": THRESHOLD_S,
    "poll_seconds": POLL_S,
}, separators=(",", ":")) + "\n")
sys.stdout.flush()

while True:
    now = now_utc()
    for sid, path in iter_sessions():
        check_session(sid, path, now)
    time.sleep(POLL_S)
PYEOF
