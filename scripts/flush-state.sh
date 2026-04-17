#!/usr/bin/env bash
# flush-state.sh — PreCompact hook.
#
# Two responsibilities:
#   1. Emit a reminder to the Moderator to write state.json + state-full.json
#      BEFORE the host reclaims context. The hook cannot dump Moderator
#      context itself, but it can force a persistence checkpoint by
#      injecting a high-priority note.
#   2. **BLOCK compaction** when the session is mid-cross-examination
#      (Phase 4). Cross-exam requires every champion's full presentation
#      in-context to produce counter-defenses; losing that mid-phase
#      corrupts the debate. Claude Code >= v2.1.105 honours
#      `{"decision":"block","reason":"..."}` on stdout as a PreCompact veto.
#
# Budget: hard cap 2000ms. Degrades gracefully (exit 0 = allow compaction)
# if TAB/ is absent or anything goes wrong — the veto is opt-in, never the
# default.
set -uo pipefail

# Hard self-timeout in case python3 hangs (e.g. filesystem stall). 2s
# leaves 1s of host-side budget for hook dispatch.
(sleep 2 && kill -TERM $$ 2>/dev/null) &
WATCHDOG=$!
trap 'kill $WATCHDOG 2>/dev/null; exit 0' TERM EXIT

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

python3 - "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys

sessions_dir = sys.argv[1]

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

state = {}
try:
    with open(state_path) as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    pass

phase = (state.get("phase_completed") or "").lower()
next_phase = (state.get("next_phase") or "").lower()

# Cross-exam phases — names intentionally broad so protocol renames do not
# silently disable the veto. Matches "cross-examination", "cross-exam",
# "phase-4", or explicit "champion-debate" (Phase 3→4 handoff).
CROSS_EXAM_MARKERS = ("cross-exam", "cross-examination", "phase-4",
                      "champion-debate")

def is_cross_exam(p):
    if not p:
        return False
    p = p.lower()
    return any(m in p for m in CROSS_EXAM_MARKERS)

# Audit phase (6.5) — auditor also needs full context
AUDITOR_MARKERS = ("phase-6.5", "auditor", "audit")

def is_auditor(p):
    if not p:
        return False
    p = p.lower()
    return any(m in p for m in AUDITOR_MARKERS)

veto = is_cross_exam(phase) or is_cross_exam(next_phase) \
       or is_auditor(next_phase)

if veto:
    reason = (
        f"TAB session {session_id} is mid-deliberation "
        f"(phase_completed='{state.get('phase_completed')}', "
        f"next_phase='{state.get('next_phase')}'). Compaction would "
        "truncate champion presentations or auditor evidence, corrupting "
        "the debate. Resume compaction after the phase closes "
        "(state-full.json will be re-written then)."
    )
    sys.stdout.write(json.dumps({
        "decision": "block",
        "reason": reason
    }))
    sys.exit(0)

# Non-blocking path — same behaviour as before: remind the Moderator to
# checkpoint.
hint = (
    "TAB PreCompact: context compaction is imminent. Before it runs, "
    "write the current session's state.json and state-full.json to "
    f"'{session_dir}'. Do NOT rely on in-context claims surviving "
    "compaction; the claims_registry in state-full.json is your source "
    "of truth."
)
sys.stdout.write(json.dumps({"additionalContext": hint}))
PYEOF
