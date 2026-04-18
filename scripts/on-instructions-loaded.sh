#!/usr/bin/env bash
# on-instructions-loaded.sh — InstructionsLoaded hook (Claude Code ≥ v2.1.83).
#
# Re-injects the locked `session_language` (§3.5.3) whenever the host
# re-loads instructions. This covers: session start re-hydration after
# a /resume, post-compact rehydration (complementing rehydrate-state.sh),
# and CLAUDE.md changes mid-session.
#
# Matchers configured in hooks/hooks.json: session_start, compact.
# Budget: <300ms. Silent on missing TAB session.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

python3 - "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys

sessions_dir = sys.argv[1]

candidates = []
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        path = os.path.join(sessions_dir, entry)
        sf = os.path.join(path, "state-full.json")
        if os.path.isfile(sf):
            candidates.append((os.path.getmtime(sf), path, sf))
except Exception:
    sys.exit(0)

if not candidates:
    sys.exit(0)

candidates.sort(reverse=True)
_, session_dir, sf_path = candidates[0]
session_id = os.path.basename(session_dir)

try:
    with open(sf_path) as f:
        sf = json.load(f)
except Exception:
    sys.exit(0)

# Prefer the locked language; fall back to state.json.language if state-full
# was not yet populated.
language = (sf.get("session_language") or "").strip()
if not language:
    state_path = os.path.join(session_dir, "state.json")
    try:
        with open(state_path) as f:
            st = json.load(f)
        language = (st.get("language") or "").strip()
    except Exception:
        pass

if not language:
    sys.exit(0)

print(json.dumps({
    "additionalContext": (
        f"TAB session `{session_id}` has session_language LOCKED to `{language}`. "
        f"Every Moderator, Champion, Advisor, Auditor turn stays in this language. "
        f"Do NOT re-detect from user input; if the user switches language mid-session, "
        f"emit an AskUserQuestion to confirm before switching."
    )
}))
PYEOF
