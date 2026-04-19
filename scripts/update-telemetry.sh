#!/usr/bin/env bash
# update-telemetry.sh — PostToolUse hook (matcher: Write, if: Write(./.tab/**)).
# Bumps an "artifacts_written" counter in telemetry.json for the affected
# TAB session. Non-blocking: never fails the host session.
#
# Input: JSON on stdin from the host hook invocation. Fields used:
#   tool_input.file_path — the path that was written
#
# Concurrency: reads and writes go through scripts/lib/json_atomic.py so
# parallel hook invocations serialize on the telemetry file's flock.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat || echo '{}')

python3 - "$INPUT" <<'PYEOF' 2>/dev/null || exit 0
import json, os, re, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_update

try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

file_path = ((payload.get("tool_input") or {}).get("file_path") or "")
if not file_path:
    sys.exit(0)

# Expect a path like <project>/.tab/sessions/<session>/<file>
m = re.search(r"(.*/.tab/sessions/[^/]+)", file_path)
if not m:
    sys.exit(0)
session_dir = m.group(1)
telemetry_path = Path(session_dir) / "telemetry.json"

def bump(tel):
    totals = tel.setdefault("totals", {})
    totals["artifacts_written"] = int(totals.get("artifacts_written", 0)) + 1
    totals["last_artifact"] = file_path
    totals["last_artifact_at"] = datetime.now(timezone.utc).isoformat()
    return tel

try:
    atomic_update(
        telemetry_path,
        bump,
        default={
            "session_id": os.path.basename(session_dir),
            "phases": [],
            "totals": {
                "tokens_in": 0, "tokens_out": 0, "cost_usd": 0.0,
                "subagents_invoked": 0, "mcp_queries_total": 0,
                "artifacts_written": 0,
            },
        },
        timeout_seconds=2.0,
    )
except (OSError, TimeoutError):
    pass

# Non-blocking: exit 0 regardless
PYEOF
