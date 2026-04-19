#!/usr/bin/env bash
# on-teammate-idle.sh — TeammateIdle hook (Claude Code Agent Teams).
#
# Fires when a teammate participating in a real Agent Teams cross-exam
# becomes idle (no message produced within the host-defined window).
# We log the event into <session>/telemetry.json.teammate_idles[] for
# debugging; no autonomous remediation is attempted (the Moderator
# decides whether to nudge or close the round in the main thread).
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin.
# Budget: <200ms. Non-blocking.
#
# Concurrency: writes via scripts/lib/json_atomic.py so parallel idles
# in multi-teammate rounds don't lose records.
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
from json_atomic import atomic_update

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
        tf = os.path.join(sessions_dir, entry, "telemetry.json")
        if os.path.isfile(tf):
            mtime = os.path.getmtime(tf)
            if best is None or mtime > best[0]:
                best = (mtime, entry, tf)
except OSError:
    sys.exit(0)

if not best:
    sys.exit(0)

_, _, tf_path = best

record = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "teammate": ev.get("teammate") or ev.get("agent") or ev.get("name"),
    "idle_seconds": ev.get("idle_seconds"),
    "round": ev.get("round"),
    "reason": ev.get("reason"),
}

def append_idle(tel):
    tel.setdefault("teammate_idles", []).append(record)
    return tel

try:
    atomic_update(Path(tf_path), append_idle, default={}, timeout_seconds=1.5)
except (OSError, TimeoutError):
    pass
PYEOF
