#!/usr/bin/env bash
# snapshot-worktrees.sh — diff `git worktree list --porcelain` against the
# previous snapshot and emit create / remove events for any deltas.
#
# Safety-net observer that runs on SubagentStart and SubagentStop.
# Catches worktree lifecycle that bypassed the EnterWorktree /
# ExitWorktree tools (and the WorktreeRemove hook), such as:
#
#   - an agent running `git worktree add` directly via Bash
#   - the harness creating an `isolation: worktree` sub-agent worktree
#     via its native code path
#   - worktrees created or removed between TAB sessions
#
# First run on a fresh session establishes the baseline silently — no
# events are emitted for pre-existing worktrees, only for changes
# observed after the baseline was recorded.
#
# Records carry `source: snapshot` so downstream consumers can tell
# them apart from `tool` and `remove` events.
#
# Budget: <300ms (one cheap `git worktree list` plus two atomic writes).
# Exit 0 on any failure — best-effort.
set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
TAB_DIR="${PROJECT_DIR}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

WT_OUT="$(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null || true)"
[[ -n "$WT_OUT" ]] || exit 0

python3 - "$WT_OUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
try:
    from json_atomic import atomic_append_ndjson, atomic_update
except ImportError:
    sys.exit(0)

raw = sys.argv[1]
sessions_dir = sys.argv[2]

# Parse porcelain output. Records are separated by blank lines, the first
# line of each record is `worktree <absolute-path>`.
current_paths = set()
for block in raw.split("\n\n"):
    for line in block.splitlines():
        if line.startswith("worktree "):
            current_paths.add(line[len("worktree "):].strip())
            break

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

session_dir = Path(os.path.dirname(best[2]))
snap_path = session_dir / "worktrees-snapshot.json"
ledger_path = session_dir / "worktrees.ndjson"

# Hold the snapshot's lock for the full diff-then-swap so two parallel
# SubagentStart / SubagentStop hooks can't both observe the same delta
# and double-log it.
baseline_first_run = [False]
created = []
removed = []

def diff_and_swap(prev):
    if not isinstance(prev, dict) or "paths" not in prev:
        baseline_first_run[0] = True
        return {"paths": sorted(current_paths)}
    prev_set = set(prev.get("paths") or [])
    created.extend(sorted(current_paths - prev_set))
    removed.extend(sorted(prev_set - current_paths))
    return {"paths": sorted(current_paths)}

try:
    atomic_update(snap_path, diff_and_swap, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    sys.exit(0)

if baseline_first_run[0]:
    sys.exit(0)

if not created and not removed:
    sys.exit(0)

now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def emit(action, path):
    record = {
        "at": now_iso,
        "action": action,
        "worktree_path": path,
        "source": "snapshot",
    }
    try:
        atomic_append_ndjson(ledger_path, record, timeout_seconds=2.0)
    except (OSError, TimeoutError, TypeError):
        pass

for p in created:
    emit("create", p)
for p in removed:
    emit("remove", p)
PYEOF
