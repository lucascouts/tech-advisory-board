#!/usr/bin/env bash
# on-reactive-change.sh — shared handler for CwdChanged and FileChanged
# hooks (Claude Code >= v2.1.83).
#
# CwdChanged fires when the host pivots into or out of a git worktree
# (EnterWorktree / ExitWorktree). TAB uses worktrees for Rechallenge
# isolation (M5), so this hook re-locates .tab/ and re-injects a session
# digest into the Moderator's context.
#
# FileChanged fires when a tracked TAB artifact (ADR, synthesis.json,
# state.json) is modified by something other than the Moderator — e.g.
# an IDE edit, a git rebase, or a script. We surface the change so the
# Moderator can decide whether to re-read or reject the mutation.
#
# The host passes the event name via the `CLAUDE_HOOK_EVENT` env var;
# the JSON payload is on stdin. Both paths share the same "rehydrate and
# report" skeleton.
#
# Budget: <500ms. Exit 0 on any failure — these are best-effort events.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

TAB_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.tab"
EVENT="${CLAUDE_HOOK_EVENT:-Unknown}"

PAYLOAD="$(cat 2>/dev/null || echo '{}')"

python3 - "$TAB_DIR" "$EVENT" "$PAYLOAD" <<'PYEOF' 2>/dev/null || exit 0
import json, os, sys

tab_dir = sys.argv[1]
event = sys.argv[2]
try:
    payload = json.loads(sys.argv[3])
except (ValueError, TypeError):
    payload = {}

sessions_dir = os.path.join(tab_dir, "sessions")
if not os.path.isdir(sessions_dir):
    # New cwd has no TAB yet — emit a one-shot hint only on CwdChanged so
    # the Moderator knows to re-run init-dir if needed.
    if event == "CwdChanged":
        sys.stdout.write(json.dumps({
            "additionalContext": (
                f"TAB CwdChanged: new cwd has no .tab/ workspace yet "
                f"(`{tab_dir}` absent). Run `init-dir` if this cwd "
                f"should host a TAB session."
            )
        }))
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
                best = (mtime, entry, sf)
except OSError:
    sys.exit(0)

if best is None:
    sys.exit(0)

_, session_id, state_path = best
state = {}
try:
    with open(state_path) as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    pass

phase = state.get("phase_completed") or "(pre-bootstrap)"
next_phase = state.get("next_phase") or "?"
mode = state.get("mode") or "?"

if event == "CwdChanged":
    from_cwd = payload.get("from") or payload.get("old_cwd")
    to_cwd = payload.get("to") or payload.get("new_cwd") or os.getcwd()
    hint = (
        f"TAB CwdChanged: cwd moved from `{from_cwd}` to `{to_cwd}`. "
        f"Active session `{session_id}` (mode={mode}, phase={phase} → "
        f"{next_phase}) is now rooted at `{tab_dir}`. Rechallenge "
        f"worktrees remain isolated — do not reach back into the "
        f"previous cwd's .tab/ directory."
    )
elif event == "FileChanged":
    changed_path = (
        payload.get("path") or payload.get("file") or "<unknown>"
    )
    change_kind = (
        payload.get("kind") or payload.get("change_type") or "modified"
    )
    origin = payload.get("source") or payload.get("origin") or "external"
    # Focus on TAB artifacts; everything else is noise we don't echo back.
    rel = os.path.relpath(changed_path, os.getcwd()) \
          if changed_path and changed_path != "<unknown>" else changed_path
    is_tab = isinstance(rel, str) and rel.startswith(".tab/")
    if not is_tab:
        sys.stderr.write(
            f"[TAB:on-reactive-change] ignoring FileChanged outside .tab/: {rel}\n"
        )
        sys.exit(0)
    is_adr = "/decisions/" in rel
    is_synthesis = rel.endswith("/synthesis.json")
    is_state = rel.endswith("/state.json") or rel.endswith("/state-full.json")
    what = ("ADR" if is_adr
            else "synthesis" if is_synthesis
            else "state" if is_state
            else "artifact")
    hint = (
        f"TAB FileChanged: {what} `{rel}` was {change_kind} by "
        f"`{origin}` outside the Moderator's control. Re-read the file "
        f"before issuing the next tool call that depends on its "
        f"contents. Session `{session_id}` digest: phase={phase} → "
        f"{next_phase}, mode={mode}."
    )
else:
    sys.exit(0)

sys.stdout.write(json.dumps({"additionalContext": hint}))
PYEOF
