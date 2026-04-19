#!/usr/bin/env bash
# on-permission-denied.sh — PermissionDenied hook (Claude Code ≥ v2.1.89).
#
# Appends to <session>/denials.ndjson so auto-mode runs can audit which
# tools were blocked mid-debate (referenced in automation.md §7.3).
# Especially relevant for Auditor runs that hit denied MCP tools.
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin.
# Budget: <150ms. Non-blocking.
#
# Concurrency: NDJSON append goes through scripts/lib/json_atomic.py
# so simultaneous denials from parallel advisors produce one clean
# record per event.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[[ -n "$INPUT" ]] || exit 0

python3 - "$INPUT" "$TAB_DIR/sessions" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_append_ndjson

try:
    ev = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
sessions_dir = sys.argv[2]

best = None
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        sf = os.path.join(sessions_dir, entry, "state.json")
        if os.path.isfile(sf):
            mtime = os.path.getmtime(sf)
            if best is None or mtime > best[0]:
                best = (mtime, entry)
except OSError:
    sys.exit(0)

if not best:
    sys.exit(0)

session_dir = os.path.join(sessions_dir, best[1])
out_path = Path(session_dir) / "denials.ndjson"

record = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "tool_name": ev.get("tool_name") or ev.get("tool"),
    "subagent_type": ev.get("subagent_type") or ev.get("agent_type"),
    "reason": ev.get("reason") or ev.get("message"),
    "phase": ev.get("phase"),
}

try:
    # denials.ndjson is per-session so it rarely grows unbounded, but
    # a misbehaving hook or auto-mode can cause pathological spam.
    # Rotation caps match the timeline envelope (see M2).
    atomic_append_ndjson(
        out_path,
        record,
        max_lines=int(os.environ.get("TAB_DENIALS_MAX_LINES", "10000")),
        max_bytes=int(os.environ.get("TAB_DENIALS_MAX_BYTES", "5000000")),
        max_rotations=int(os.environ.get("TAB_DENIALS_MAX_ROTATIONS", "3")),
        timeout_seconds=1.0,
    )
except (OSError, TimeoutError):
    pass
PYEOF
