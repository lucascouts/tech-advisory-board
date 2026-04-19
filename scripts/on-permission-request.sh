#!/usr/bin/env bash
# on-permission-request.sh — PermissionRequest hook.
#
# Auto-approves read-only tool calls (Read / Glob / Grep) targeted at
# `.tab/**`. During a long deliberation, the Moderator repeatedly re-reads
# state.json, synthesis.json, telemetry.json, and ADR index. Interactive
# permission prompts break the flow without increasing safety — these
# paths are TAB's own artifacts and the operation is read-only.
#
# Scope boundary: the `if:` filter on the hook entry in hooks.json
# already restricts this handler to paths under `.tab/**`. Writes and
# destructive tools (Edit, Bash, Write) are never auto-approved here.
#
# Budget: <100ms. Silent-exit on malformed stdin.
set -uo pipefail

# Drain stdin so the host doesn't block; we don't actually need to
# inspect the payload — the matcher + `if:` already scoped us.
cat >/dev/null 2>&1 || true

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
