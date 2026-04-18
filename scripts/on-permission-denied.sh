#!/usr/bin/env bash
# on-permission-denied.sh — PermissionDenied hook (Claude Code ≥ v2.1.89).
#
# Appends to <session>/denials.ndjson so auto-mode runs can audit which
# tools were blocked mid-debate (referenced in automation.md §7.3).
# Especially relevant for Auditor runs that hit denied MCP tools.
#
# Silent-exit on: missing python3, missing TAB/sessions, malformed stdin.
# Budget: <150ms. Non-blocking.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/TAB"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[[ -n "$INPUT" ]] || exit 0

python3 - "$TAB_DIR/sessions" <<PYEOF 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone

payload_raw = """$INPUT"""
sessions_dir = sys.argv[1]

try:
    ev = json.loads(payload_raw)
except Exception:
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
                best = (mtime, entry)
except OSError:
    sys.exit(0)

if not best:
    sys.exit(0)

session_dir = os.path.join(sessions_dir, best[1])
out_path = os.path.join(session_dir, "denials.ndjson")

record = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "tool_name": ev.get("tool_name") or ev.get("tool"),
    "subagent_type": ev.get("subagent_type") or ev.get("agent_type"),
    "reason": ev.get("reason") or ev.get("message"),
    "phase": ev.get("phase"),
}

try:
    with open(out_path, "a") as f:
        f.write(json.dumps(record, separators=(",", ":")) + "\n")
except OSError:
    pass
PYEOF
