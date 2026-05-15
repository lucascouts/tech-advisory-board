#!/usr/bin/env bash
# on-worktree-tool.sh — PostToolUse hook for EnterWorktree / ExitWorktree.
#
# Primary observer of worktree lifecycle when sub-agents use the
# EnterWorktree / ExitWorktree tools (e.g. the rechallenge skill).
# Captures host-provided tool_use_id so an Enter event can later be
# paired with its matching Exit, and duration_ms when the host
# attaches it. Records land in <session>/worktrees.ndjson alongside
# the WorktreeRemove and snapshot-based events.
#
# Why this hook (and not WorktreeCreate): the WorktreeCreate event in
# Claude Code is *productive* — the hook's stdout is consumed as the
# worktree path and the harness disables `git worktree add` whenever
# any plugin registers it. PostToolUse on the tool calls is purely
# observational and never interferes with the harness.
#
# Payload (host-provided JSON on stdin, fields used best-effort):
#   tool_name      — "EnterWorktree" or "ExitWorktree"
#   tool_use_id    — opaque id; pairs Enter with later Exit
#   tool_input     — { worktree_path | path | ... } (shape can evolve)
#   tool_response  — host result (may also carry the path)
#   duration_ms    — present on completed tool calls
#
# Budget: <200ms. Exit 0 on any failure — observability never gates.
set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
try:
    from json_atomic import atomic_append_ndjson
except ImportError:
    sys.exit(0)

try:
    payload = json.loads(sys.argv[1])
except (ValueError, TypeError):
    sys.exit(0)
sessions_dir = sys.argv[2]

tool_name = payload.get("tool_name") or ""
if tool_name not in ("EnterWorktree", "ExitWorktree"):
    sys.exit(0)

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

session_dir = os.path.dirname(best[2])

tool_input = payload.get("tool_input") or {}
tool_response = payload.get("tool_response")
response_dict = tool_response if isinstance(tool_response, dict) else {}

worktree_path = (
    tool_input.get("worktree_path")
    or tool_input.get("path")
    or response_dict.get("worktree_path")
    or response_dict.get("path")
)

event = {
    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "action": "enter" if tool_name == "EnterWorktree" else "exit",
    "worktree_path": worktree_path,
    "tool_use_id": payload.get("tool_use_id"),
    "duration_ms": payload.get("duration_ms"),
    "source": "tool",
}
event = {k: v for k, v in event.items() if v is not None}

try:
    atomic_append_ndjson(
        Path(session_dir) / "worktrees.ndjson",
        event,
        timeout_seconds=2.0,
    )
except (OSError, TimeoutError, TypeError):
    pass
PYEOF
