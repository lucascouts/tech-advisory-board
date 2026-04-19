# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-04-19

Initial public release of the **tech-advisory-board** Claude Code plugin —
a multi-agent advisory board for technical decisions (stack selection,
architecture choices, framework/database comparisons, project planning).

### Added

- **Skills (3)**
  - `tab` — main advisory board orchestrator. Champions debate, Advisors evaluate,
    Scout maps landscape. Five execution modes (Instant, Fast, Standard, Complete,
    Complete+) auto-selected by complexity.
  - `rechallenge` — re-tests a prior ADR for continued validity; verdicts
    are `still-valid` / `needs-revision` / `supersede`. Uses
    `disable-model-invocation: true` and triggers `EnterWorktree` when
    the host supports it.
  - `explain-synthesis` — human-readable walkthrough of a stored synthesis.

- **Subagents (5)**
  - `champion` — builds advocacy thesis for a candidate technology.
  - `advisor` — independent per-dimension evaluator.
  - `researcher` — fetches ecosystem data (versions, CVEs, community signals)
    via MCPs.
  - `auditor` — adversarial audit of near-final synthesis (mandatory in
    Complete / Complete+ / Rechallenge).
  - `supervisor` — conditional anti-consensus gate triggered when the Moderator
    detects consensus-theater signals.

- **MCP server**: `channel` — local stdio server scaffolding for inter-agent
  messaging (protocol `2025-06-18`). Bound via top-level `channels[]` entry
  in `.claude-plugin/plugin.json` with canonical `userConfig` surface
  (`telegram_bot_token` sensitive, `telegram_chat_id`,
  `channel_webhook_url` sensitive). `servers/channel/index.js` reads
  either legacy env vars (`TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` /
  `CHANNEL_WEBHOOK_URL`) or userConfig-injected `CLAUDE_PLUGIN_OPTION_*`
  equivalents.

- **Output styles (2)**: `presentation`, `terse`.

- **Hooks & monitors** — two-layer lifecycle automation:
  - Global (`hooks/hooks.json`): session state, cost tracking, idle
    teammate detection (Agent Teams mode), stop-failure recovery,
    `ConfigChange` / `WorktreeCreate` / `WorktreeRemove` instrumentation.
  - Skill-scoped (frontmatter of `skills/tab/SKILL.md` and
    `skills/rechallenge/SKILL.md`): `PreCompact`, `PostCompact`, `Stop`
    fire only inside TAB sessions — non-TAB sessions pay zero overhead.
  - `tab-session-monitor` and `tab-stall-guard` both gated by
    `when: on-skill-invoke:tab`, arming only after the first `tab`
    dispatch of a host session.
  - `tab-stall-guard` (`scripts/stall-guard.sh`) detects subagents open
    >30 min without a `SubagentStop` (typically MCP setup hangs); emits
    `{"event":"stall-detected",...}` to the host notification stream and
    appends to `<session>/stalls.ndjson` (bounded: 1k lines / 500 KB /
    2 rotations). Thresholds overridable via `TAB_STALL_THRESHOLD_SECONDS`
    (default 1800) and `TAB_STALL_POLL_SECONDS` (default 60).

- **Schemas (JSON)** — contracts for `synthesis`, `research-cache`, `state`,
  and `vanguard-timeline` artifacts.

- **NDJSON auto-rotation** — `timeline-events.ndjson`, `denials.ndjson`,
  and related artifacts rotate at 10k lines / 5 MB / 3 rotations by
  default (caps per-artifact disk use at ~20 MB). Overridable via
  `TAB_TIMELINE_MAX_{LINES,BYTES,ROTATIONS}` and
  `TAB_DENIALS_MAX_{LINES,BYTES,ROTATIONS}` env vars.
  `scripts/render-timeline.sh`'s generated HTML detects rotation (file
  shrinkage) and resets its read offset, so the browser never hangs on
  overlarge NDJSON and never misses events after rotation.

- **Configurable knobs (userConfig)** — cost ceilings, language preference,
  default mode, per-agent model overrides, model-selection policy
  (`static` / `budget-aware` / `context-aware`), strict-path activation,
  and experimental Agent Teams execution mode.

- **Utility scripts** (`bin/`) — `plugin-version` (single source of truth
  propagation), `new-adr` (ADR scaffolding), `cache` (with
  `scripts/lib/json_atomic.atomic_update()` for race-free `invalidate`
  and `prune`), and more.

- **Instrumentation scripts** — `scripts/on-config-change.sh` appends
  user/project/local/policy/skills settings mutations into
  `state-full.json.config_changes[]`; `scripts/on-worktree-create.sh`
  and `scripts/on-worktree-remove.sh` append to
  `<session>/worktrees.ndjson` (pairs by `worktree_path`) so Rechallenge
  worktree lifecycle is auditable without parsing Bash exit status from
  `EnterWorktree`. `scripts/on-task-completed.sh` closes any still-open
  `state-full.json.subagents_invoked[]` entry for the task_id (fallback
  for cases where `SubagentStop` didn't fire) and increments
  `telemetry.json.totals.tasks_completed` / `.tasks_failed`.

- **Documentation**
  - `ARCHITECTURE.md` at the repo root (~360 lines) for maintainers and
    contributors. Covers mental model (Moderator + Scout + 5 subagent
    roles + Rechallenge), 13-phase pipeline with ASCII diagram,
    persistence layout (`.tab/` + `${CLAUDE_PLUGIN_DATA}`), the
    `scripts/lib/json_atomic` contract, hook taxonomy, 9 critical
    invariants (session-language lock, confidence monotonicity,
    two-source rule, COI disclosure, advisor independence, discard
    fairness, mandatory auditor, atomic ADR numbering, schema contract
    stability), model policy defaults, graceful-degradation matrix,
    6 extension points, testing pointer, and a diagnostic cheat sheet.
  - `docs/SYNTHESIS_CONTRACT.md` — single consumer contract for
    `synthesis.json` (schema, hard-fail rules, required fields,
    confidence tags, CI recipe, forward-compat policy). Producer-side
    docs (`synthesis-schema.md`, `synthesis-template.md`) remain as
    authoring aids for the Moderator.
  - `docs/PLUGIN_CONFORMANCE.md` — formalizes which TAB patterns are
    canonical per the official Claude Code spec (hooks/hooks.json path,
    subagent frontmatter `tools`/`disallowedTools`/`memory: project`,
    `.lsp.json` path, skill shell blocks), with evidence (file:line)
    and official doc pointers.

### Compatibility

- Recommended Claude Code **≥ v2.1.111** (uses `effort: xhigh` for
  Opus 4.7 on the Auditor). Older versions down to **v2.1.72** work
  with automatic degradation (no `xhigh`, `EnterWorktree` optional).
- Recommended MCPs: `perplexity`, `context7`, `brave-search` (for live research).
- Optional: set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to enable real
  multi-agent execution (otherwise simulated fan-out via subagents).

### License

MIT — see [LICENSE](./LICENSE).

[0.1.0]: https://github.com/lucascouts/tech-advisory-board/releases/tag/0.1.0
