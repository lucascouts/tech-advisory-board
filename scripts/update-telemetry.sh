#!/usr/bin/env bash
# update-telemetry.sh — PostToolUse hook (matcher: Write, if: Write(./TAB/**)).
# Bumps an "artifacts_written" counter in telemetry.json for the affected
# TAB session. Non-blocking: never fails the host session.
#
# Input: JSON on stdin from the host hook invocation. Fields used:
#   tool_input.file_path — the path that was written
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat || echo '{}')

python3 - "$INPUT" <<'PYEOF' 2>/dev/null || exit 0
import json, os, re, sys
from datetime import datetime, timezone

try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

file_path = ((payload.get("tool_input") or {}).get("file_path") or "")
if not file_path:
    sys.exit(0)

# Expect a path like <project>/TAB/sessions/<session>/<file>
m = re.search(r"(.*/TAB/sessions/[^/]+)", file_path)
if not m:
    sys.exit(0)
session_dir = m.group(1)

telemetry_path = os.path.join(session_dir, "telemetry.json")
telemetry = {
    "session_id": os.path.basename(session_dir),
    "phases": [],
    "totals": {"tokens_in": 0, "tokens_out": 0, "cost_usd": 0.0,
               "subagents_invoked": 0, "mcp_queries_total": 0,
               "artifacts_written": 0},
}

if os.path.isfile(telemetry_path):
    try:
        with open(telemetry_path) as f:
            telemetry = json.load(f)
    except Exception:
        pass

totals = telemetry.setdefault("totals", {})
totals["artifacts_written"] = int(totals.get("artifacts_written", 0)) + 1
totals["last_artifact"] = file_path
totals["last_artifact_at"] = datetime.now(timezone.utc).isoformat()

try:
    with open(telemetry_path, "w") as f:
        json.dump(telemetry, f, indent=2, ensure_ascii=False)
except Exception:
    pass

# Non-blocking: exit 0 regardless
PYEOF
