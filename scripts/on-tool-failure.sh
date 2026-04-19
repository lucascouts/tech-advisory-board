#!/usr/bin/env bash
# on-tool-failure.sh — PostToolUseFailure hook (Claude Code ≥ v2.1.83).
#
# Fires when a tool call errors (5xx, timeout, exception, interrupt).
# Appends a structured entry to <session>/telemetry.json .mcp_failures[]
# so reliability metrics survive compaction. When 3+ failures of the
# same tool accumulate in one session, emit an additionalContext hint
# suggesting fallback to WebSearch (Researcher / Auditor observe it).
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin.
# Budget: <200ms. Non-blocking.
#
# Concurrency: writes via scripts/lib/json_atomic.py so parallel tool
# failures across advisors don't tear telemetry.json.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[[ -n "$INPUT" ]] || exit 0

python3 - "$TAB_DIR/sessions" "$INPUT" <<'PYEOF' 2>/dev/null || exit 0
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_update

sessions_dir = sys.argv[1]
try:
    ev = json.loads(sys.argv[2])
except (ValueError, TypeError):
    sys.exit(0)

tool = ev.get("tool_name") or ev.get("tool") or "<unknown>"
error = ev.get("error") or ev.get("error_message") or ""
is_interrupt = bool(
    ev.get("is_interrupt")
    or ev.get("interrupted")
    or "interrupt" in str(error).lower()
)

# Classify error type heuristically
err_str = str(error).lower()
if is_interrupt:
    error_type = "interrupt"
elif "timeout" in err_str or "timed out" in err_str:
    error_type = "timeout"
elif "5" in err_str[:3] and ("status" in err_str or "http" in err_str):
    error_type = "5xx"
elif "rate" in err_str and "limit" in err_str:
    error_type = "rate-limit"
elif not error:
    error_type = "unknown"
else:
    error_type = "error"

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
telemetry_path = Path(session_dir) / "telemetry.json"

record = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "tool": tool,
    "error_type": error_type,
    "is_interrupt": is_interrupt,
}

# Capture post-update state so we can compute same_tool count for the hint.
post_state = {"failures": []}

def append_failure(tel):
    failures = tel.get("mcp_failures")
    if not isinstance(failures, list):
        failures = []
        tel["mcp_failures"] = failures
    failures.append(record)
    post_state["failures"] = list(failures)
    return tel

try:
    atomic_update(telemetry_path, append_failure, default={}, timeout_seconds=2.0)
except (OSError, TimeoutError):
    sys.exit(0)

# Count same-tool failures; surface fallback hint after the 3rd
same_tool = [
    f for f in post_state["failures"]
    if isinstance(f, dict) and f.get("tool") == tool
]
if len(same_tool) >= 3:
    hint = (
        f"TAB PostToolUseFailure: `{tool}` has failed {len(same_tool)} times "
        f"in this session (latest error_type={error_type}). Consider falling "
        f"back to `WebSearch` / `WebFetch` for the next research step and "
        f"tagging affected claims [unverified]. See research-budget.md."
    )
    sys.stdout.write(json.dumps({"additionalContext": hint}))
PYEOF
