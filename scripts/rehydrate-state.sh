#!/usr/bin/env bash
# rehydrate-state.sh — PostCompact hook.
# After the host compacts the context window, inject a digest of the
# latest TAB session's state-full.json so the Moderator can recover
# phase, mode, budget, and top claims without re-reading files.
#
# Budget: <3s. Silent when no TAB session is active.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"

if [[ ! -d "$TAB_DIR/sessions" ]]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

python3 - "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys

sessions_dir = sys.argv[1]

# Find newest non-archived session
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

# Also read hot state.json for phase + budget
state_path = os.path.join(session_dir, "state.json")
state = {}
try:
    with open(state_path) as f:
        state = json.load(f)
except Exception:
    pass

phase = state.get("phase_completed") or "(pre-bootstrap)"
next_phase = state.get("next_phase") or "?"
mode = state.get("mode") or "?"
bc = state.get("budget_consumed") or {}
cost = bc.get("cost_usd", 0.0)

# §3.5.3 language lock — re-inject the session_language recorded in Phase 1
# so champions / advisors keep consistent output after compaction.
# Precedence: state-full.session_language > state.language > empty.
session_language = (sf.get("session_language") or state.get("language") or "").strip()

# Digest claims_registry — top 8 by confidence + recency
registry = sf.get("claims_registry") or []
# Order: high-conf first, then med-conf, then low-conf, then unverified
order = {"high-conf": 0, "med-conf": 1, "low-conf": 2, "unverified": 3}
def sort_key(c):
    return (order.get(c.get("confidence"), 9), -int(c.get("recorded_at_epoch") or 0))

top = sorted(registry, key=sort_key)[:8]

# Subagents status
subs = sf.get("subagents_invoked") or []
active = sum(1 for s in subs if s.get("ended_at") is None)
total_subs = len(subs)

lines = [
    f"TAB PostCompact digest — session `{session_id}`:",
    f"  mode: {mode}  phase_completed: {phase}  → next: {next_phase}",
    f"  cost: ${cost:.2f}  subagents: {active} active / {total_subs} total",
]

if session_language:
    lines.append(
        f"  session_language: {session_language} (LOCKED in Phase 1 — do NOT re-detect; "
        f"all Moderator, Champion, Advisor, Auditor output stays in this language)"
    )

if top:
    lines.append("  top claims from state-full.json claims_registry:")
    for c in top:
        cid = c.get("id", "?")
        conf = c.get("confidence", "?")
        claim = (c.get("claim") or "").strip().replace("\n", " ")
        if len(claim) > 140:
            claim = claim[:137] + "..."
        lines.append(f"    [{conf}] ({cid}) {claim}")

lines.append(
    "Re-read state-full.json from the session dir if you need the full "
    "claims registry, champion presentations, or cross-exam transcripts."
)

print(json.dumps({"additionalContext": "\n".join(lines)}))
PYEOF
