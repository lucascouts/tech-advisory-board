#!/usr/bin/env bash
# on-stop-failure.sh — StopFailure hook (Claude Code >= v2.1.78).
#
# Fires when the host terminates a turn because of an upstream API failure,
# tool error, or unrecoverable exception — NOT the same as the Stop hook,
# which fires on a clean end-of-turn.
#
# TAB's risk here is mid-phase death (especially during cross-examination or
# auditor verification) leaving state-full.json partially written and no
# resume hint emitted. This hook:
#   1. Detects the newest active TAB session
#   2. Writes a crash marker file (session/crash.json) with error context
#   3. Emits an additionalContext resume hint so a follow-up session can
#      surface the interrupted deliberation
#
# Budget: <400ms. Degrades silently if TAB/ is absent. Exit 0 always —
# StopFailure must not amplify the original failure.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

# Stop-failure payload arrives on stdin as JSON. Capture (safely) — may be
# absent if the host version is older.
PAYLOAD="${TAB_STOPFAILURE_PAYLOAD:-}"
if [[ -z "$PAYLOAD" ]] && [[ -t 0 ]]; then
    PAYLOAD="{}"
elif [[ -z "$PAYLOAD" ]]; then
    PAYLOAD="$(cat 2>/dev/null || true)"
fi
[[ -z "$PAYLOAD" ]] && PAYLOAD="{}"

python3 - "$TAB_DIR/sessions" "$PAYLOAD" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone

sessions_dir = sys.argv[1]
raw_payload = sys.argv[2] if len(sys.argv) > 2 else "{}"

try:
    payload = json.loads(raw_payload)
except (ValueError, TypeError):
    payload = {}

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Locate newest non-archived session with a state.json
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

_, session_id, state_path = best
session_dir = os.path.dirname(state_path)

try:
    with open(state_path) as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    state = {}

crash = {
    "at": now(),
    "session_id": session_id,
    "phase_at_crash": state.get("phase_completed"),
    "next_phase_intended": state.get("next_phase"),
    "mode": state.get("mode"),
    "error_kind": payload.get("error_kind") or payload.get("kind"),
    "error_message": payload.get("error_message") or payload.get("message"),
    "tool_in_flight": payload.get("tool") or payload.get("tool_name"),
    "subagent_in_flight": payload.get("subagent_id"),
}
# Strip None values so crash.json stays compact
crash = {k: v for k, v in crash.items() if v is not None}

crash_path = os.path.join(session_dir, "crash.json")
# Append history if crash.json already exists
history = []
if os.path.isfile(crash_path):
    try:
        with open(crash_path) as f:
            prev = json.load(f)
        if isinstance(prev, dict) and "history" in prev:
            history = prev["history"]
        elif isinstance(prev, dict):
            history = [prev]
        elif isinstance(prev, list):
            history = prev
    except (OSError, json.JSONDecodeError):
        history = []

history.append(crash)
try:
    with open(crash_path, "w") as f:
        json.dump({"session_id": session_id, "history": history[-10:]},
                  f, indent=2, sort_keys=True)
except OSError:
    pass

# Resume hint for the next turn (if the session is resumable)
phase = crash.get("phase_at_crash") or "(pre-bootstrap)"
next_phase = crash.get("next_phase_intended") or "(unknown)"
hint = (
    f"TAB StopFailure: session {session_id} crashed at phase '{phase}' "
    f"heading to '{next_phase}'. Crash record written to "
    f"'{os.path.relpath(crash_path, os.getcwd())}'. To resume, invoke "
    f"/tech-advisory-board:tab with the original question — the Moderator "
    f"will detect the interrupted state via detect-interrupted.sh. Do NOT "
    f"re-run the crashed phase from scratch; reuse state-full.json."
)

sys.stdout.write(json.dumps({"additionalContext": hint}))
PYEOF
