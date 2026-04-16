#!/usr/bin/env bash
# validate-on-stop.sh — Stop hook.
# When the assistant tries to stop, auto-detect the latest non-archived
# TAB session and run validate-synthesis-json.sh + validate-claims.sh on
# its synthesis.json. If a synthesis exists and fails hard-fail
# assertions, block the stop with exit 2 and a feedback message so the
# Moderator re-emits a valid synthesis.
#
# When no TAB session is active, when no synthesis.json has been produced
# yet, or when the latest session is a pending Rechallenge without a
# synthesis, exit 0 silently.
#
# Budget: <8s. Non-blocking on script errors (only blocks on real
# validator failures).
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

# Find newest non-archived session with a synthesis.json
LATEST=$(python3 - "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || echo ""
import os, sys
sessions = sys.argv[1]
candidates = []
try:
    for entry in os.listdir(sessions):
        if entry == "archived":
            continue
        path = os.path.join(sessions, entry)
        synth = os.path.join(path, "synthesis.json")
        if os.path.isfile(synth):
            candidates.append((os.path.getmtime(synth), path))
except Exception:
    sys.exit(0)
candidates.sort(reverse=True)
if candidates:
    print(candidates[0][1])
PYEOF
)

if [[ -z "$LATEST" ]]; then
    # No TAB synthesis to validate — not a TAB session, nothing to do.
    exit 0
fi

SYNTH="$LATEST/synthesis.json"

# Run synthesis validator (structural)
VS_OUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis-json.sh" "$SYNTH" 2>&1)
VS_RC=$?

# Run claims validator (data quality)
VC_OUT=$("${CLAUDE_PLUGIN_ROOT}/scripts/validate-claims.sh" --session "$LATEST" 2>&1)
VC_RC=$?

if [[ $VS_RC -eq 0 && $VC_RC -eq 0 ]]; then
    # Everything passes — allow stop silently.
    exit 0
fi

# Something failed — build feedback for the Moderator and block stop.
python3 - "$LATEST" "$VS_RC" "$VS_OUT" "$VC_RC" "$VC_OUT" <<'PYEOF'
import json, sys

session = sys.argv[1]
vs_rc = int(sys.argv[2])
vs_out = sys.argv[3]
vc_rc = int(sys.argv[4])
vc_out = sys.argv[5]

lines = [
    f"TAB Stop gate: synthesis in '{session}' did not pass validation.",
    f"  validate-synthesis-json.sh exit={vs_rc}",
    f"  validate-claims.sh exit={vc_rc}",
    "",
    "Fix the synthesis.json before closing the session. Details:",
]
if vs_rc != 0 and vs_out.strip():
    lines.append("--- validate-synthesis-json.sh ---")
    lines.append(vs_out.strip()[:2000])
if vc_rc != 0 and vc_out.strip():
    lines.append("--- validate-claims.sh ---")
    lines.append(vc_out.strip()[:2000])

feedback = "\n".join(lines)
# Stop hook: use top-level decision "block" with a reason the Moderator will see.
print(json.dumps({
    "decision": "block",
    "reason": feedback
}))
PYEOF

# Exit 0 because we already emitted structured JSON on stdout to block.
# (Stop hooks: decision=block via JSON is preferred over exit 2.)
exit 0
