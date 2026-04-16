#!/usr/bin/env bash
# flush-state.sh — PreCompact hook.
# Emits a reminder to the Moderator to write state.json + state-full.json
# BEFORE the host reclaims context. The hook cannot dump Moderator context
# itself, but it can force a persistence checkpoint by injecting a
# high-priority note.
#
# Budget: <300ms. Degrades gracefully if TAB/ is absent.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

# Find the newest NON-archived session dir
LATEST=""
if command -v python3 >/dev/null 2>&1; then
    LATEST=$(python3 - "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || echo ""
import os, sys
sessions = sys.argv[1]
candidates = []
for entry in os.listdir(sessions):
    if entry == "archived":
        continue
    p = os.path.join(sessions, entry)
    state = os.path.join(p, "state.json")
    if os.path.isfile(state):
        candidates.append((os.path.getmtime(state), p))
candidates.sort(reverse=True)
if candidates:
    print(candidates[0][1])
PYEOF
)
fi

if [[ -z "$LATEST" ]]; then
    exit 0
fi

python3 <<PYEOF
import json
print(json.dumps({"additionalContext":
    "TAB PreCompact: context compaction is imminent. Before it runs, "
    "write the current session's state.json and state-full.json to "
    "'$LATEST'. Do NOT rely on in-context claims surviving compaction; "
    "the claims_registry in state-full.json is your source of truth."
}))
PYEOF
