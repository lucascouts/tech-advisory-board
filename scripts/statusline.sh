#!/usr/bin/env bash
# statusline.sh — subagent status line for long TAB sessions.
# Reads the newest state-full.json under <cwd>/TAB/sessions/ and prints
# a single concise line. Silent when no TAB session is active. Budget:
# <1000ms (enforced by host timeout). Caches parsed state between calls
# via a tempfile under ${CLAUDE_PLUGIN_DATA}/.statusline-cache.
#
# This is the *pull-model* snapshot — re-rendered every host tick. For a
# *push-model* event stream (phase transitions, subagent lifecycle, budget
# thresholds) see scripts/monitor.sh, declared under the `monitors` key of
# plugin.json. The two complement each other: statusline is the always-on
# header; monitor is the scrolling event log.
set -uo pipefail

# Fast path: when we're in a cloud/remote session, the host does not
# render the status line at all — bail early.
if [[ "${CLAUDE_CODE_REMOTE:-false}" == "true" ]]; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

CACHE_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/tech-advisory-board}"
CACHE_FILE="$CACHE_DIR/.statusline-cache"

python3 - "$TAB_DIR/sessions" "$CACHE_FILE" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys

sessions_dir, cache_file = sys.argv[1], sys.argv[2]

# Find newest non-archived session with a state-full.json
candidates = []
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        sf = os.path.join(sessions_dir, entry, "state-full.json")
        if os.path.isfile(sf):
            candidates.append((os.path.getmtime(sf), entry, sf))
except Exception:
    sys.exit(0)

if not candidates:
    sys.exit(0)

candidates.sort(reverse=True)
_, session_id, sf_path = candidates[0]

# Also read hot state for budget + phase (smaller, authoritative for latest phase)
state_path = os.path.join(sessions_dir, session_id, "state.json")
state = {}
try:
    with open(state_path) as f:
        state = json.load(f)
except Exception:
    pass

phase = state.get("phase_completed") or "(pre-bootstrap)"
next_phase = state.get("next_phase") or ""
mode = state.get("mode", "?")
bc = state.get("budget_consumed") or {}
cost = bc.get("cost_usd", 0.0)

# Active-subagents count from state-full.json (rough — counts recent entries)
try:
    with open(sf_path) as f:
        full = json.load(f)
    active = sum(1 for s in (full.get("subagents_invoked") or [])
                 if s.get("ended_at") is None)
except Exception:
    active = 0

# Get budget max from config_snapshot (safe — default 5.0)
max_cost = (state.get("config_snapshot", {})
                 .get("budget", {})
                 .get("max_cost_per_session_usd", 5.0))
pct = (cost / max_cost * 100.0) if max_cost else 0.0

line = f"[TAB:{mode}] {session_id} · {phase}"
if next_phase:
    line += f" → {next_phase}"
if active:
    line += f" · {active} active"
line += f" · ${cost:.2f}/{max_cost:.2f} ({pct:.0f}%)"

# Truncate to 200 chars per §21.3
if len(line) > 200:
    line = line[:197] + "..."

print(line)
PYEOF
