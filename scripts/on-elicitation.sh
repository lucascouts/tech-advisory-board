#!/usr/bin/env bash
# on-elicitation.sh — Elicitation / ElicitationResult hook (Claude Code ≥ v2.1.76).
#
# Records every AskUserQuestion round into the newest TAB session's
# telemetry.json.elicitations[]. Powers the discard-triage instrumentation
# (§3.2.1) and the post-research clarification cycle.
#
# Event payload arrives on stdin as JSON. We only persist a minimal
# projection (kind, question_id, at, answered, response_length) so the
# file stays small across long sessions.
#
# Silent-exit on: missing python3, missing TAB/sessions, malformed stdin.
# Budget: <200ms. Never blocks.
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

# Find newest non-archived session
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
tel_path = os.path.join(session_dir, "telemetry.json")

try:
    with open(tel_path) as f:
        tel = json.load(f)
except Exception:
    tel = {}

tel.setdefault("elicitations", [])

record = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "kind": ev.get("hook_event_name") or ev.get("event") or "Elicitation",
    "question_id": ev.get("question_id") or ev.get("id"),
    "answered": bool(ev.get("response") or ev.get("answer")),
}
response_text = ev.get("response") or ev.get("answer") or ""
if isinstance(response_text, str):
    record["response_length"] = len(response_text)

tel["elicitations"].append(record)

try:
    with open(tel_path, "w") as f:
        json.dump(tel, f, indent=2, ensure_ascii=False)
except OSError:
    pass
PYEOF
