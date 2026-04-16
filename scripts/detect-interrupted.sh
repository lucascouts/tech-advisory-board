#!/usr/bin/env bash
# detect-interrupted.sh — SessionStart hook.
# Checks for interrupted TAB sessions in <cwd>/TAB/sessions/ and emits a
# hint that the Moderator will see on session start. Silent when no
# interrupted session is found. Never fails the host session.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"

if ! command -v python3 >/dev/null 2>&1; then
    # One-time visible warning: plugin degrades without python3. Emit
    # additionalContext (non-blocking) so the Moderator surfaces it to
    # the user on first session start.
    printf '%s' '{"additionalContext":"TAB: python3 is not available in PATH. Lifecycle hooks, validators and cost computation require python3 >= 3.9. Install it or the plugin will degrade silently (no resume-detection, no Stop-gate validation, no telemetry). See README Requirements."}'
    exit 0
fi

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

RESULT=$("${CLAUDE_PLUGIN_ROOT:-}/bin/tab-resume-session" \
    --tab-dir "$TAB_DIR" --window-hours 24 2>/dev/null || echo '{"status":"no-sessions"}')

STATUS=$(python3 -c "
import json, sys
try:
    d = json.loads('''$RESULT''')
    print(d.get('status', 'no-sessions'))
except Exception:
    print('no-sessions')
")

if [[ "$STATUS" != "ok" ]]; then
    exit 0
fi

COUNT=$(python3 -c "
import json
d = json.loads('''$RESULT''')
print(len(d.get('candidates', [])))
")

if [[ "${COUNT:-0}" -lt 1 ]]; then
    exit 0
fi

# Emit additionalContext for the Moderator
python3 <<PYEOF
import json
d = json.loads('''$RESULT''')
cands = d.get('candidates', [])
lines = ["TAB: $COUNT interrupted session(s) detected. Resume candidates:"]
for c in cands[:3]:
    lines.append(
        f"  - {c.get('session_id')}: phase={c.get('phase_completed')} "
        f"→ next={c.get('next_phase')} "
        f"(idle {c.get('idle_hours')}h, mode={c.get('mode')})"
    )
lines.append("If the user invokes /tech-advisory-board:tab, offer to resume.")
print(json.dumps({"additionalContext": "\n".join(lines)}))
PYEOF
