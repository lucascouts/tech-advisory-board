---
version: 1.0
last_updated: 2026-04-16
scope: Block 6 — automation hooks
audience: TAB maintainers, operators, advanced users
---

# Hooks Catalog

TAB ships a `hooks/hooks.json` at the plugin root that wires five host
lifecycle events to plugin-local scripts. This document is the
operational reference — what each hook does, what it receives, what it
returns, and how to test it in isolation.

**Rule:** plugin-shipped agents cannot declare hooks (§3.1). All hooks
live at plugin root (`hooks/hooks.json`) or in the skill frontmatter.

## 1. Event map

| Event | Script | Purpose | Budget | Blocking? |
|---|---|---|---|---|
| `SessionStart` | `scripts/detect-interrupted.sh` | Suggest resume of an interrupted TAB session | 5s | no |
| `UserPromptSubmit` | `scripts/inject-tab-context.sh` | Pre-inject project context when the prompt looks like a TAB trigger | 5s | no |
| `PreCompact` | `scripts/flush-state.sh` | Remind the Moderator to persist state before auto-compaction | 3s | no |
| `PostToolUse` (matcher `Write`, if `Write(**/TAB/sessions/**)`) | `scripts/update-telemetry.sh` | Increment `telemetry.json.totals.artifacts_written` after every session-artifact write | 3s | no |
| `SessionEnd` | `scripts/archive-idle-sessions.sh` | Redundant safety net: archive idle sessions even if the user never invoked the tab skill | 10s | no |

All hooks exit 0 unconditionally — none block the host.

## 2. Per-hook details

### 2.1 `SessionStart` → `detect-interrupted.sh`

**Input:** JSON on stdin with `session_id`, `transcript_path`, `cwd`,
`permission_mode`, `hook_event_name`.

**Logic:** invokes `${CLAUDE_PLUGIN_ROOT}/bin/tab-resume-session
--tab-dir <cwd>/TAB --window-hours 24`. If at least one candidate is
found, emits a JSON envelope with `additionalContext` describing up to
three candidates.

**Output (stdout):** either empty (no candidates) or a JSON object
`{"additionalContext": "..."}` that the host adds to the session's
initial context.

**Failure:** if `python3` is missing or the TAB/ dir does not exist,
the hook exits silently. Never blocks session start.

**Manual test:**
```bash
CLAUDE_PROJECT_DIR=/path/to/project \
    ${CLAUDE_PLUGIN_ROOT}/scripts/detect-interrupted.sh < /dev/null
```

### 2.2 `UserPromptSubmit` → `inject-tab-context.sh`

**Matcher availability:** `UserPromptSubmit` does NOT accept matchers in
`hooks.json`. The script fires on every prompt and self-gates.

**Trigger patterns** (regex, case-insensitive):

- `/tech-advisory-board:`
- `\btab\b`
- `which (database|framework|library|stack|orm|runtime)`
- `(should i use|que devo usar|qual usar)`
- `compare .+ (vs|versus|or) `
- `analise (esse|este) projeto`

When matched, runs `extract-context.sh --json` and emits
`{"additionalContext": "..."}` summarizing manifests, stack, git branch.

**Failure:** silent. Never blocks the prompt.

**Manual test:**
```bash
echo '{"user_prompt": "which database should I use for time-series?"}' \
    | ${CLAUDE_PLUGIN_ROOT}/scripts/inject-tab-context.sh
```

### 2.3 `PreCompact` → `flush-state.sh`

**Input:** JSON on stdin (contents not used — the hook does not need
the event payload, it only needs to know "compaction is about to
happen").

**Logic:** finds the newest non-archived session with a `state.json`,
emits an `additionalContext` prompting the Moderator to write
`state.json`/`state-full.json` BEFORE compaction claims its context.

**Why not write state directly?** Hooks cannot access the Moderator's
in-context claims registry. Only the Moderator can serialize them. The
hook's job is to fire the reminder at the right moment.

**Budget:** hard cap 300ms in normal operation; the host enforces
`timeout: 3` (seconds).

### 2.4 `PostToolUse` (Write on `**/TAB/sessions/**`) → `update-telemetry.sh`

**Input:** JSON on stdin from the host with `tool_name`, `tool_input`,
`tool_response`. The hook uses `tool_input.file_path`.

**Logic:** extracts the session directory from `file_path`, opens
`telemetry.json` (creates if absent), increments
`totals.artifacts_written`, updates `last_artifact` + `last_artifact_at`.

**Gate:** the `if: "Write(**/TAB/sessions/**)"` field restricts this
hook to Write tool invocations whose path matches the glob. The script
also sanity-checks the path pattern.

**Manual test:**
```bash
echo '{"tool_input": {"file_path": "/proj/TAB/sessions/s1/synthesis.json"}}' \
    | ${CLAUDE_PLUGIN_ROOT}/scripts/update-telemetry.sh
cat /proj/TAB/sessions/s1/telemetry.json  # artifacts_written == 1
```

### 2.5 `SessionEnd` → `archive-idle-sessions.sh`

**Logic:** invokes `tab-init-dir --base <cwd>` (which internally runs
the archival sweep). Idempotent. Never blocks session termination.

**Why not rely on Moderator-driven archival?** A user may open Claude
Code, never invoke TAB, and close it — in that scenario the Moderator
never ran, but previously interrupted sessions still should age out of
`sessions/` into `sessions/archived/`.

## 3. Scheduled rechallenge re-cron (SessionStart safety net)

`bin/tab-schedule-rechallenge` writes schedule metadata to
`<adr>.schedule.json` when a user opts into periodic rechallenge. The
host's `CronCreate` auto-expires recurring tasks after 7 days
. TAB's design allows a SessionStart
extension to re-cron any schedule with `active: true` whose last run
is older than the cron interval. This re-cron step is **not wired by
default** — opting in requires the user to add a second hook entry to
their personal `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 10,
            "command": "bash -c 'for s in $(find $CLAUDE_PROJECT_DIR/TAB/decisions -name \"*.schedule.json\" 2>/dev/null); do python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); print(d.get(\\\"activation_prompt\\\")) if d.get(\\\"active\\\") else None\" \"$s\"; done'"
          }
        ]
      }
    ]
  }
}
```

This is deliberately a user opt-in rather than a plugin default because
silently re-creating cron jobs at every session start is surprising
behavior — best to require explicit consent.

## 4. Exit-code contract

Plugin hooks follow the host's command-hook contract:

| Exit | Semantic |
|---|---|
| 0 | Success. If stdout is valid JSON, the host parses it for directives (`additionalContext`, `decision`, etc.) |
| 2 | Block the triggering action. Only used deliberately — TAB hooks never return 2 (all are non-blocking by design) |
| Other | Non-blocking error. Logged; session continues |

**TAB convention:** all hooks exit 0, even on internal failure. A
hook that fails to read `TAB/config.json` should not break the user's
Claude Code session.

## 5. Output size cap

Host caps hook stdout at 10,000 characters. TAB hooks stay well under
that — the largest output (`additionalContext` from
`detect-interrupted.sh`) is a few hundred characters.

## 6. Disabling TAB hooks

Two levers:

1. **Plugin disable** — `/plugin disable tech-advisory-board` removes
   all TAB hooks from the event chain.
2. **Selective hook disable** — edit the user's
   `~/.claude/settings.json` to set `"hooks": null` for a specific
   event under an override block, or rename
   `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` (not recommended — the next
   plugin update restores it).

## 7. Related documents

- `scripts/*.sh` — hook implementations
- `hooks/hooks.json` — declarative wiring
