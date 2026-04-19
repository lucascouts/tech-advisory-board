#!/usr/bin/env bash
# on-notification.sh — Notification hook (host lifecycle event).
#
# Routes failed Rechallenge sessions to the configured push channel via
# the channel MCP server. Only fires when the most recent session
# under .tab/sessions/ has state.json.status == "failed" AND originated
# from the rechallenge skill (state.json.kind == "rechallenge" or
# config.json.skill == "rechallenge").
#
# This script is the implementation of rechallenge-protocol.md §11
# ("Failure emits a Notification hook AND leaves the session archived").
#
# ENV_SCRUB caveat: under CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1, the MCP
# server channel runs in degraded mode (no transport env vars
# reachable) and the call is a silent no-op. See
# docs/TROUBLESHOOTING.md → "`channel` push is not sending messages".
#
# Silent-exit on: missing python3, missing .tab/sessions, malformed stdin,
# nothing to notify. Budget: <300ms. Non-blocking.
set -uo pipefail

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
[[ -d "$TAB_DIR/sessions" ]] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"

python3 - "$TAB_DIR/sessions" "$INPUT" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(
    os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "scripts", "lib"))
from json_atomic import atomic_append_ndjson

sessions_dir = sys.argv[1]
payload_raw = sys.argv[2] if len(sys.argv) > 2 else ""

try:
    ev = json.loads(payload_raw) if payload_raw else {}
except Exception:
    ev = {}

# Only act on permission_prompt / generic notifications (not idle pings).
ntype = (ev.get("notification_type") or ev.get("type") or "").lower()
if ntype in ("idle", "session_idle"):
    sys.exit(0)

best = None
try:
    for entry in os.listdir(sessions_dir):
        if entry == "archived":
            continue
        p = os.path.join(sessions_dir, entry)
        if not os.path.isdir(p):
            continue
        sj = os.path.join(p, "state.json")
        if os.path.isfile(sj):
            mtime = os.path.getmtime(sj)
            if best is None or mtime > best[0]:
                best = (mtime, entry, p, sj)
except OSError:
    sys.exit(0)

if not best:
    sys.exit(0)

_, session_id, session_path, sj_path = best

try:
    with open(sj_path) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)

status = (state.get("status") or "").lower()
if status != "failed":
    sys.exit(0)

# Confirm rechallenge origin.
kind = (state.get("kind") or state.get("skill") or "").lower()
if kind != "rechallenge":
    cj = os.path.join(session_path, "config.json")
    if os.path.isfile(cj):
        try:
            with open(cj) as f:
                cfg = json.load(f)
            kind = (cfg.get("skill") or cfg.get("kind") or "").lower()
        except Exception:
            pass
if kind != "rechallenge":
    sys.exit(0)

# Build a one-line verdict summary.
adr = state.get("adr_path") or state.get("adr") or "unknown ADR"
reason = state.get("failure_reason") or state.get("error") or "unknown failure"
text = f"Rechallenge failed for {adr} — {reason}. Session: {session_id}."
deep_link = state.get("remote_session_url") or None

# Append a timeline event so the failure trail survives even if push fails.
# Same rotation caps as scripts/monitor.sh (see M2 in ANALISE-CRITICA.md).
event = {
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "kind": "notification-routed",
    "session_id": session_id,
    "adr": adr,
    "reason": reason,
}
try:
    atomic_append_ndjson(
        Path(session_path) / "timeline-events.ndjson",
        event,
        max_lines=int(os.environ.get("TAB_TIMELINE_MAX_LINES", "10000")),
        max_bytes=int(os.environ.get("TAB_TIMELINE_MAX_BYTES", "5000000")),
        max_rotations=int(os.environ.get("TAB_TIMELINE_MAX_ROTATIONS", "3")),
        timeout_seconds=1.0,
    )
except (OSError, TimeoutError):
    pass

# Emit additionalContext requesting the Moderator to invoke the MCP tool.
# We do not call the MCP server directly from a hook — the host runtime
# is the only privileged caller for mcp__* tools.
envelope = {
    "additionalContext": (
        "channel notification queued: rechallenge failure. "
        f"Severity: critical. Text: {text}. "
        f"Deep link: {deep_link or '(none — set CLAUDE_CODE_REMOTE_SESSION_ID for clickable link)'}. "
        "If interactive, call mcp__channel__sendMessage with this text."
    )
}
sys.stdout.write(json.dumps(envelope, ensure_ascii=False))
PYEOF
