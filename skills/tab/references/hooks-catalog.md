---
version: 2.1
last_updated: 2026-04-19
scope: Block 6 — automation hooks
audience: TAB maintainers, operators, advanced users
---

# Hooks Catalog

TAB ships a `hooks/hooks.json` at the plugin root that wires **21 host
lifecycle events** to plugin-local scripts. This document is the
operational reference — what each hook does, what it receives, what it
returns, and how to test it in isolation.

**Rule:** plugin-shipped agents cannot declare hooks (§3.1). All hooks
live at plugin root (`hooks/hooks.json`) or in the skill frontmatter.

## 1. Event map

| Event | Matcher / `if:` | Script | Purpose | Budget | Blocking? |
|---|---|---|---|---|---|
| `SessionStart` | — | `detect-interrupted.sh` + inline `node` check | Resume hint + runtime deps warning | 5s / 2s | no |
| `UserPromptSubmit` | — | `inject-tab-context.sh` | Pre-inject project context on TAB-triggering prompts (gated by `strict_paths`) | 5s | no |
| `PreCompact` | — | `flush-state.sh` | Persist state + block auto-compaction during critical phases | 3s | **yes** (critical phases) |
| `PostCompact` | — | `rehydrate-state.sh` | Re-inject state-full digest into Moderator context | 4s | no |
| `PostToolUse` | `if: Write(**/.tab/sessions/**)` | `update-telemetry.sh` | Increment `telemetry.json.totals.artifacts_written` | 3s | no |
| `PostToolUseFailure` | `matcher: mcp__.*__.*\|WebFetch\|WebSearch` | `on-tool-failure.sh` | Capture tool errors to `telemetry.json.mcp_failures[]`; fallback hint after 3× | 3s | no |
| `TaskCreated` | — | `on-task-created.sh` | Open pending subagent entry in `state-full.json` | 2s | no |
| `SubagentStart` | — | `on-subagent-start.sh` | Record spawn timing for Gantt timeline | 2s | no |
| `SubagentStop` | — | `update-telemetry-subagent.sh` | Close subagent entry; update cost/time totals | 3s | no |
| `Stop` | — | `validate-on-stop.sh` | Gate close-session on hard-fail assertions | 10s | **yes** on hard-fail |
| `StopFailure` | — | `on-stop-failure.sh` | Capture Stop-gate rejection in `crash.json`; emit resume hint | 4s | no |
| `CwdChanged` | — | `on-reactive-change.sh` | Re-locate `.tab/` after EnterWorktree/ExitWorktree; re-inject digest | 2s | no |
| `FileChanged` | `matcher: config.json\|index.md\|synthesis.json\|state.json\|state-full.json` | `on-reactive-change.sh` | React to external mutations of TAB artifacts | 2s | no |
| `InstructionsLoaded` | `matcher: session_start` | `on-instructions-loaded.sh` | Re-inject `session_language` lock at startup | 2s | no |
| `InstructionsLoaded` | `matcher: compact` | `on-instructions-loaded.sh` | Re-inject `session_language` lock after compaction | 2s | no |
| `Elicitation` | — | `on-elicitation.sh` | Register `AskUserQuestion` round in `telemetry.json.elicitations[]` | 2s | no |
| `ElicitationResult` | — | `on-elicitation.sh` | Capture user answer metadata | 2s | no |
| `PermissionDenied` | — | `on-permission-denied.sh` | Append blocked tool to `<session>/denials.ndjson` | 2s | no |
| `PermissionRequest` | `matcher: Read\|Glob\|Grep`, `if: Read/Glob/Grep(**/.tab/**)` | `on-permission-request.sh` | Auto-approve read-only access to `.tab/**` | 2s | returns `allow` |
| `SessionEnd` | — | `archive-idle-sessions.sh` | Archive idle sessions (redundant safety net) | 10s | no |
| `Notification` | — | `on-notification.sh` | Route failed Rechallenge sessions through `channel` MCP push | 3s | no |
| `TeammateIdle` | — | `on-teammate-idle.sh` | Append teammate stalls during Agent Teams cross-exam to `telemetry.json.teammate_idles[]` | 2s | no |

Unless marked otherwise, all hooks exit 0 — none block the host session.

## 2. Per-hook details

### 2.1 `SessionStart` — `detect-interrupted.sh` + node check

**Script 1** (`detect-interrupted.sh`):

- **Input:** JSON on stdin with `session_id`, `transcript_path`, `cwd`,
  `permission_mode`, `hook_event_name`.
- **Logic:** invokes
  `${CLAUDE_PLUGIN_ROOT}/bin/resume-session --tab-dir <cwd>/.tab
  --window-hours 24`. When at least one candidate is found, emits
  `{"additionalContext": "..."}` describing up to three.
- **Output:** empty or a JSON envelope for the host.
- **Failure:** missing `python3` → emits a visible warning and exits 0.
  Missing `.tab/` dir → silent exit 0.

**Script 2** (inline) — checks `command -v node`. Missing → stderr
warning only (`"TAB warning: node not in PATH; LSP servers and some
MCP bridges will be unavailable"`). Always exits 0.

**Manual test:**
```bash
CLAUDE_PROJECT_DIR=/path/to/project \
    ${CLAUDE_PLUGIN_ROOT}/scripts/detect-interrupted.sh < /dev/null
```

### 2.2 `UserPromptSubmit` → `inject-tab-context.sh`

- **Matcher availability:** `UserPromptSubmit` does NOT accept matchers
  in `hooks.json`. The script fires on every prompt and self-gates.
- **Trigger regex** (case-insensitive): `/tech-advisory-board:`,
  `\btab\b`, `which (database|framework|library|stack|orm|runtime)`,
  `(should i use|que devo usar|qual usar)`, `compare .+ (vs|versus|or) `,
  `analise (esse|este) projeto`.
- **`strict_paths` gate:** if `CLAUDE_PLUGIN_OPTION_strict_paths=true`
  AND the prompt is not a manual `/tech-advisory-board:...` invocation,
  the hook demands a project manifest (`package.json`, `pyproject.toml`,
  etc.) in `cwd` before firing. Default is `false`, preserving greenfield.
- **Output:** `{"additionalContext": "..."}` summarizing manifests,
  stack, git branch. Silent otherwise.

### 2.3 `PreCompact` → `flush-state.sh`

Persists the newest non-archived session's state snapshot before
compaction, and in critical phases (cross-exam / auditor) emits
`{"decision":"block"}` to veto the compaction. Host honors `decision`
from `PreCompact` since Claude Code ≥ v2.1.105.

### 2.4 `PostCompact` → `rehydrate-state.sh`

After compaction, reads `state-full.json` and emits an
`additionalContext` digest (phase, mode, open subagents, last claim).
Keeps the Moderator's mental model intact across the truncation.

### 2.5 `PostToolUse` (`Write(**/.tab/sessions/**)`) → `update-telemetry.sh`

- **Input:** host JSON with `tool_name`, `tool_input`, `tool_response`.
  Uses `tool_input.file_path`.
- **Logic:** increments `telemetry.json.totals.artifacts_written`,
  updates `last_artifact` + `last_artifact_at`.

### 2.6 `PostToolUseFailure` (MCP / WebSearch / WebFetch) → `on-tool-failure.sh`

- **Matcher:** regex `mcp__.*__.*|WebFetch|WebSearch` — intentionally
  broad to cover any MCP swap (Tavily, Exa, Kagi, etc.).
- **Input:** host JSON with `tool_name`, `tool_input`, `tool_use_id`,
  `error`, `is_interrupt`.
- **Logic:** classifies the error (`timeout` / `5xx` / `rate-limit` /
  `interrupt` / `error` / `unknown`) and appends
  `{at, tool, error_type, is_interrupt}` to
  `telemetry.json.mcp_failures[]`. When a single tool accumulates ≥3
  failures in the session, emits an `additionalContext` hint suggesting
  fallback to `WebSearch` and `[unverified]` claim tagging.
- **Schema:** `schemas/telemetry.schema.json` — `mcp_failures[]`
  property with enum on `error_type`.
- **Manual test:**
  ```bash
  echo '{"tool_name":"mcp__perplexity__perplexity_search","error":"HTTP 500 timeout","is_interrupt":false}' \
    | ${CLAUDE_PLUGIN_ROOT}/scripts/on-tool-failure.sh
  ```

### 2.7 `TaskCreated` → `on-task-created.sh`

Opens a pending subagent entry in `state-full.json.subagents[]` with
`started_at_task`, `subagent_type`, `parent_task_id`. Counterpart of
§2.9 which closes the entry.

### 2.8 `SubagentStart` → `on-subagent-start.sh`

Records the actual spawn timestamp (distinct from `TaskCreated` which
fires at dispatch). Feeds the Gantt chart in the timeline HTML.

### 2.9 `SubagentStop` → `update-telemetry-subagent.sh`

Closes the subagent entry with `ended_at`, `tokens_in`, `tokens_out`,
`cost_usd`, `turns`. Rolls the per-agent cost into
`telemetry.json.totals.cost_usd_by_agent`.

### 2.10 `Stop` → `validate-on-stop.sh`

The session close-gate. Runs `validate-synthesis-json.sh` against the
newest synthesis. Hard-fail assertions → exit 2, which blocks the
session from closing and the Moderator must correct. Soft warnings →
exit 0 with a written warning appended to the synthesis.

### 2.11 `StopFailure` → `on-stop-failure.sh`

Fires when `Stop` rejects. Writes `<session>/crash.json` with the exact
rejection reason and emits an `additionalContext` telling the Moderator
to correct and re-close.

### 2.12 `CwdChanged` → `on-reactive-change.sh`

Fires on EnterWorktree / ExitWorktree. Re-locates `.tab/` under the new
cwd, re-injects the active session digest, and tells the Moderator not
to reach back into the previous cwd's `.tab/`.

### 2.13 `FileChanged` — matcher on TAB artifacts → `on-reactive-change.sh`

- **Matcher:** `config.json|index.md|synthesis.json|state.json|state-full.json`
  (regex over basename). Narrow matcher reduces noise from unrelated
  file watchers.
- **Script gating:** internally confirms `rel.startswith(".tab/")` and
  logs a stderr line when it receives a path outside `.tab/`
  (telemetry-only; exits 0 either way).

### 2.14 `InstructionsLoaded` (`session_start` / `compact`) → `on-instructions-loaded.sh`

Fires after CLAUDE.md is loaded at session start and again after
compaction re-reads it. Re-injects the locked `session_language` (see
§3.5.3 of the main skill) so the Moderator stays in the user's
preferred language across context rebuilds.

### 2.15 `Elicitation` → `on-elicitation.sh`

Records an `AskUserQuestion` round (the question text, multiple-choice
options, dispatcher) in `telemetry.json.elicitations[]`.

### 2.16 `ElicitationResult` → `on-elicitation.sh`

Captures the user's answer, response time, and whether the user picked
a suggested option or typed free text.

### 2.17 `PermissionDenied` → `on-permission-denied.sh`

Appends the denied tool invocation (`tool_name`, `subagent_type`,
`reason`, `phase`) to `<session>/denials.ndjson`. Used by the §7.3
observability recipe in `automation.md` to tune CI allow-lists.

### 2.18 `PermissionRequest` (`Read/Glob/Grep` on `.tab/**`) → `on-permission-request.sh`

- **Matcher + `if:`:** scoped to `Read | Glob | Grep` reaching into
  `**/.tab/**`. Writes and destructive tools are NOT covered here.
- **Output:** always emits
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`.
  Auto-approves the read. Reason: the Moderator re-reads its own
  artifacts dozens of times per session; interactive prompts add
  friction without adding safety.

### 2.19 `SessionEnd` → `archive-idle-sessions.sh`

Redundant safety net. Invokes `init-dir --base <cwd>` which sweeps
idle sessions (older than `session_archive_idle_hours`, default 24)
into `.tab/sessions/archived/`.

### 2.20 `Notification` → `on-notification.sh`

Routes failed Rechallenge sessions to the `channel` MCP push
channel. Implementation of `rechallenge-protocol.md §11`.

- **Input:** JSON on stdin with at least `notification_type` (e.g.
  `permission_prompt`, `idle`).
- **Logic:** locates the most recent `.tab/sessions/<id>/state.json`;
  if `status=="failed"` AND the session originated from the
  `rechallenge` skill (state or config file confirms), assembles a
  one-line verdict summary and emits an `additionalContext` envelope
  asking the Moderator to call `mcp__channel__sendMessage`. Also
  appends a `notification-routed` entry to
  `<session>/timeline-events.ndjson`.
- **ENV_SCRUB:** under `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, the MCP
  server has no transport env vars and `sendMessage` returns
  `degraded: true` — the routing is a silent no-op. The archived
  session remains the source of truth (see
  `docs/TROUBLESHOOTING.md`).
- **Output:** empty (idle/non-rechallenge events) or a JSON envelope
  with `additionalContext`.
- **Failure:** missing `python3` → silent exit 0. Malformed payload →
  silent exit 0.
- **Manual test:**
  ```bash
  echo '{"notification_type":"permission_prompt","message":"test"}' \
      | bash scripts/on-notification.sh
  echo "exit=$?"
  ```

### 2.21 `TeammateIdle` → `on-teammate-idle.sh`

Captures teammate-stall events during real Agent Teams cross-exam
(Claude Code ≥ v2.1.32 with
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). The script appends each
event to the most-recent session's
`telemetry.json.teammate_idles[]` for post-mortem debugging. It does
not interfere with the round — the Moderator (in the main thread)
decides whether to nudge or close. See
`skills/tab/references/agent-teams-mode.md` for the activation gates
and the broader Agent Teams contract.

- **Input:** JSON on stdin with `teammate` (or `agent`/`name`),
  `idle_seconds`, optional `round` and `reason`.
- **Logic:** appends one row to `telemetry.json.teammate_idles[]`.
- **Output:** empty.
- **Failure:** missing `python3` or session → silent exit 0.

## 3. Scheduled rechallenge re-cron (SessionStart safety net)

`bin/schedule-rechallenge` emits an envelope with three activation
paths: `routines_spec` (cloud-persistent, preferred for schedules > 7d),
`native_cron_spec` (CronCreate, session-bound, auto-expires after 7d),
and `loop_fallback_prompt` (last resort). The SessionStart re-cron
recipe below is a **user opt-in** for native CronCreate schedules whose
metadata has `active: true`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "timeout": 10,
            "command": "bash -c 'for s in $(find $CLAUDE_PROJECT_DIR/.tab/decisions -name \"*.schedule.json\" 2>/dev/null); do python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); print(d.get(\\\"native_cron_spec\\\",{}).get(\\\"input\\\",{}).get(\\\"prompt\\\")) if d.get(\\\"active\\\") and d.get(\\\"activation_path\\\")==\\\"native\\\" else None\" \"$s\"; done'"
          }
        ]
      }
    ]
  }
}
```

Routines (`--activation routines`) do not need this safety net — they
persist cloud-side.

## 4. Exit-code contract

| Exit | Semantic |
|---|---|
| 0 | Success. If stdout is valid JSON, the host parses it for directives (`additionalContext`, `decision`, `hookSpecificOutput`, etc.). |
| 2 | Block the triggering action. Used deliberately by `validate-on-stop.sh` on hard-fail and by `flush-state.sh` during critical phases. |
| Other | Non-blocking error. Logged; session continues. |

**TAB convention:** all non-blocking hooks exit 0 even on internal
failure. A hook that fails to read `.tab/config.json` should not break
the user's Claude Code session.

## 5. Output size cap

Host caps hook stdout at 10,000 characters. TAB hooks stay well under —
the largest output (`additionalContext` from `rehydrate-state.sh` or
`detect-interrupted.sh`) is a few hundred characters.

## 6. Disabling TAB hooks

1. **Plugin disable** — `/plugin disable tech-advisory-board` removes
   all TAB hooks from the event chain.
2. **Selective hook disable** — edit the user's
   `~/.claude/settings.json` to set `"hooks": null` for a specific
   event under an override block.

## 7. Related documents

- `scripts/*.sh` — hook implementations
- `hooks/hooks.json` — declarative wiring
