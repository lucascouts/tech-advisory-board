# Changelog

All notable changes to this plugin are documented here. This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-04-17

> Feature-heavy release closing the §3.1 – §3.8 roadmap in `APRIMORAMENTOS.md`. Additive except for the mode-name canonicalization (backwards-compatible via legacy aliases for one version; removal targeted for 0.3.0). Release-versioning policy going forward: **per-theme minor bumps** (one section of `APRIMORAMENTOS.md` per release when feasible) to keep rollback granular without spamming the marketplace with micro-releases.

### Changed

- **Mode rename**: `Express` → `Instant`, `Quick` → `Fast`. Canonical enum in `schemas/synthesis.schema.json` now lists `Instant, Fast, Standard, Complete, Complete+, Rechallenge`. Legacy aliases `Express` / `Quick` are normalized on input by `scripts/normalize-mode.sh` and `scripts/load-config.sh` (`CLAUDE_PLUGIN_OPTION_default_mode`) with a deprecation notice — removal targeted for 0.3.0.
- **README honesty**: `### Hooks (8 events)` was out of sync with the hooks declared in `hooks/hooks.json` — updated to 17 events (13 existing + `SubagentStart`, `Elicitation`, `ElicitationResult`, `PermissionDenied`).
- **Monitor declaration extracted**: the `tab-session-monitor` block moved out of `.claude-plugin/plugin.json` and into `monitors/monitors.json` (auto-discovered, mirrors the `hooks/hooks.json` convention).

### Added

- `scripts/normalize-mode.sh` — canonicalizes a TAB mode string, surfacing legacy aliases with a one-time stderr notice so callers can spot deprecated input.
- `bin/tab-cache` — manage the cross-session shared cache under `${CLAUDE_PLUGIN_DATA}/shared-cache/cache.json`. Subcommands: `list`, `stats`, `invalidate`, `prune`, `path`. TTLs: `volatile` 7 days (JS / AI / LLM ecosystems), `mature` 30 days (DBs, languages, compilers); overridable via `TAB_CACHE_TTL_VOLATILE_DAYS` / `TAB_CACHE_TTL_MATURE_DAYS`.
- `schemas/research-cache.schema.json` — new optional `scope` (`session` / `shared`) and per-entry `category` (`volatile` / `mature`), `expires_at`, `invalidated_at`. `research-budget.md §7` describes the category TTL and the `tab-cache` management surface.
- `scripts/model-policy.sh` + `skills/tab/references/model-policy.md` — dynamic model selection driven by runtime signals (budget remaining, cache-hit rate, MCP availability, topic novelty, prompt-cache warmth, stakes). New userConfig knobs: `model_policy` (`static` / `budget-aware` (default) / `context-aware`) and `model_policy_overrides` (JSON per-mode map). Envelopes are consulted via stdin JSON; output includes provenance (`source=env|signal|mode-override` + `reason`) for telemetry.
- `skills/tab/references/triage-protocol.md` + Phase 5.5 in `skills/tab/SKILL.md` — three-step landscape reinforcement before Champions spawn: discard triage questions (reversible discards via `AskUserQuestion`), adversarial premise check (auditor-subagent or moderator-inline), and steel-man of the best discarded option. Records to `telemetry.json.triage[]` and `state-full.json.landscape.discard_reversals[]` / `premise_check` / `steel_man`.
- `bin/tab-score-zscore` + `debate-protocol.md §Score Consolidation` — per-advisor z-score normalization before ranking to remove individual drift (lenient vs harsh advisors). `synthesis.schema.json` gains optional `scores.matrix[].score_z` and `scores.ranking_z[]`.
- **Outcome tracking on ADRs** (§3.3). `bin/tab-new-adr` now emits a YAML frontmatter with an `outcome:` block (status=pending). `bin/tab-record-outcome` fills it in with `status` (success / pivot / abandon / pending), `measured_at`, `actual_vs_predicted`, `variance_reason`, `lessons`. The `rechallenge` skill gained a Phase 0.5 that prompts the user to fill outcome when pending and uses the recorded outcome as counter-evidence for champions and auditor.
- **Adoption scaffold + sensitivity analysis** (§3.4). `synthesis-template.md` gains §7 (Adoption Scaffold — migration steps, lock-in risks, operational checklist at D+30/90/180, integration debt) and §8 (Decision Sensitivity — threshold analysis, stable vs fragile dimensions). `synthesis.schema.json` gains matching `adoption_scaffold` and `sensitivity` blocks. Mandatory in Complete / Complete+ (scaffold) and Standard+ (sensitivity).
- **Language lock in long sessions** (§3.5.3). `state-full.json` gains a `session_language` field (BCP 47), populated at Phase 1 and never re-detected mid-session. `scripts/rehydrate-state.sh` surfaces it in the PostCompact digest. New `InstructionsLoaded` hook (matchers `session_start`, `compact`) runs `scripts/on-instructions-loaded.sh` to re-inject the locked language on re-hydration (Claude Code ≥ v2.1.83).
- **Native hooks completion** (§3.5.1). Four additional host-native events were wired: `Elicitation` / `ElicitationResult` → `scripts/on-elicitation.sh` appends each `AskUserQuestion` round into `telemetry.json.elicitations[]` (discard-triage instrumentation for §3.2.1, Claude Code ≥ v2.1.76); `PermissionDenied` → `scripts/on-permission-denied.sh` appends blocked tools to `<session>/denials.ndjson` (Claude Code ≥ v2.1.89, feeds `automation.md §7.3`); `SubagentStart` → `scripts/on-subagent-start.sh` writes `started_at_subagent` on the matching `state-full.subagents_invoked[]` entry for exact Gantt timing (paired with existing `SubagentStop`). Total hooks: 17.
- **Failure-mode evals** (§3.5.2). Six new test cases (IDs 49–54) in `evals/evals.json` cover previously untested degradation paths: MCP down mid-session, budget burst past the ceiling mid-debate, Opus unavailable → sonnet fallback, `python3` absent from PATH, forced compaction during cross-examination, concurrent ADR writes from parallel sessions. Each asserts on concrete artifacts (telemetry records, NDJSON events, synthesis flags, hook exit contracts). Total cases: 54 (was 48).
- **Session timeline HTML** (§3.6). `scripts/monitor.sh` now mirrors every NDJSON event into `<session>/timeline-events.ndjson`. `scripts/render-timeline.sh` writes a self-contained `timeline.html` (Gantt by lane, claims panel, budget footer) that polls the NDJSON every 1.5s via `file://` fetch. `bin/tab-open-timeline` finds the newest session, renders if missing, and opens the HTML in the default browser (`xdg-open` / `open` / `$BROWSER`).
- **COI disclosure** (§3.7). `agents/researcher.md` and `agents/auditor.md` now require a structured COI block as the first output (memory-entry count, previously researched / audited stacks, bias signal, mitigations applied). New reference `skills/tab/references/coi-disclosure.md` documents the card + structural mitigations. New helper `scripts/build-agent-memory.sh` composes an effective `MEMORY.md` scoped to the inferred decision domain (frontend-framework, database, orchestrator, runtime-language, ai-ml, queue-stream, `_fallback`) so entries from unrelated domains do not contaminate the agent's spawn.
- **Scheduled rechallenge via `CronCreate`** (§3.8.1). `bin/tab-schedule-rechallenge` now emits schedule version 2 with both a `native_cron_spec` (envelope for the `CronCreate` tool, Claude Code ≥ v2.1.72) and a `loop_fallback_prompt` (/loop string). New `--activation native|loop-fallback` flag on `--record-task` freezes the path chosen so consumers can tell which backend activated the schedule.
- **CI gate hardening** (§3.8.2). `examples/ci-github-actions.yml` now calls `claude -p --bare --output-format stream-json --include-partial-messages --json-schema <schemas/synthesis.schema.json>`; the init-event check reads the ndjson stream instead of a single JSON payload. The `CLAUDE_PLUGIN_ROOT` shell fallback is replaced by a resolved `claude plugin path tech-advisory-board` step output for clarity.
- **1M context + prompt caching 1h** (§3.8.3). Default model (`claude-opus-4-7`) already carries the 1M context window on Max / Team / Enterprise tiers (Claude Code ≥ v2.1.75). `ENABLE_PROMPT_CACHING_1H=1` is enabled by default in the CI example and recommended for local Complete / Complete+ sessions (Claude Code ≥ v2.1.108).

## [0.1.1] — 2026-04-17

### Fixed

- Removed the redundant `"hooks": "./hooks/hooks.json"` key from `.claude-plugin/plugin.json`. The standard `hooks/hooks.json` path is auto-loaded by Claude Code, so declaring it in `manifest.hooks` caused a `Duplicate hooks file detected` error at plugin load time. `manifest.hooks` is now reserved for additional hook files outside the default path.

## [0.1.0] — 2026-04-16

Initial plugin release. Tracks Claude Code v2.1.72 through v2.1.111.

### Added

#### Core plugin skeleton

- Plugin manifest (`.claude-plugin/plugin.json`) with 10 `userConfig` knobs: cost ceiling, warning threshold, language preference, default mode, auditor toggle, supervisor gate toggle, ADR dir override, and three model-override knobs (`champion_model`, `auditor_model`, `advisor_model`) so organizations can pin alternative models via `modelOverrides`.
- Single-plugin marketplace manifest (`.claude-plugin/marketplace.json`).
- Explicit declaration of `agents`, `skills`, `hooks`, and `monitors` in `plugin.json` (rather than relying on discovery by convention).
- Two skills: `tab` (full advisory-board deliberation, 13 phases, Express → Complete+ modes) and `rechallenge` (compressed delta review of a prior ADR, `disable-model-invocation: true`).
- Five subagents: `researcher` (Sonnet, `memory: project`, `disallowedTools: [Edit, Write, Bash]`), `champion` (pinned to `claude-opus-4-7`, `effort: max`), `advisor` (Sonnet, `disallowedTools: [Edit, Write, Bash, NotebookEdit]`), `auditor` (pinned to `claude-opus-4-7` with `effort: xhigh`, `memory: project`, mandatory in Complete / Complete+ / Rechallenge), `supervisor` (Sonnet, conditional on consensus-theater triggers, `disallowedTools: [Edit, Write, Bash, NotebookEdit, WebFetch]`).
- Eight bin commands auto-added to PATH: `tab-init-dir`, `tab-resume-session`, `tab-compute-cost`, `tab-new-adr`, `tab-supersede-adr`, `tab-vanguard-timeline`, `tab-schedule-rechallenge`, `tab-check-mcps`.
- Seven JSON schemas (Draft 2020-12) for `config`, `state`, `state-full`, `telemetry`, `synthesis`, `research-cache`, `vanguard-timeline`.
- Sixteen reference documents under `skills/tab/references/` covering archetypes, specialists, debate protocol, intent detection, stage definitions, synthesis template and schema, context extraction, output examples, confidence tags, adversarial triggers, research budget, persistence protocol, hooks catalog, automation, flow and modes.
- One reference under `skills/rechallenge/references/` describing the rechallenge protocol.
- Evals suite (`evals/evals.json`) with 48 test cases plus three project fixtures (`simple-node-api`, `python-cli`, `messy-project`).
- `examples/` directory with a GitHub Actions CI workflow, Python and TypeScript Agent SDK snippets, and a scheduled-rechallenge tutorial.

#### Lifecycle hooks

Twelve hooks declared in `hooks/hooks.json`:

- `SessionStart` → detect interrupted sessions, emit resume hint
- `UserPromptSubmit` → inject auto-detected TAB context when intent matches
- **`PreCompact`** → blocking when the newest session's `phase_completed` or `next_phase` matches cross-exam / Phase 4 / Phase 6.5 / auditor markers (Claude Code ≥ v2.1.105). Returns `{"decision":"block","reason":"..."}`; non-matching phases fall through to a checkpoint hint so compaction proceeds. Watchdog self-timeout at 2 s.
- `PostCompact` → re-hydrate a digest of state-full.json into the Moderator's context
- `PostToolUse` (matcher `Write(**/TAB/sessions/**)`) → bump telemetry counters
- **`TaskCreated`** (Claude Code ≥ v2.1.84) → open a pending entry in `state-full.json.subagents_invoked[]` with the real start timestamp (instead of estimating it later by subtracting `duration_ms`).
- `SubagentStop` → close the pending entry opened by `TaskCreated`, matching by `task_id` first and `subagent_type` second. Duration is derived from real `started_at` when the host does not provide it.
- `Stop` → gate with `decision:"block"` when synthesis.json fails hard-fail assertions
- **`StopFailure`** (Claude Code ≥ v2.1.78) → writes `crash.json` with a phase-at-failure snapshot and emits a resume hint when the host terminates a turn because of an upstream API failure mid-cross-exam.
- **`CwdChanged`** (Claude Code ≥ v2.1.83) → re-locate TAB/ and re-inject a session digest when the host pivots into or out of a worktree (complements Rechallenge worktree isolation).
- **`FileChanged`** scoped to `TAB/**` → surface ADR / synthesis / state mutations that originate outside the Moderator, prompting a mandatory re-read before the next dependent tool call.
- `SessionEnd` → archive idle sessions.

#### Observability

- Subagent status line (`[TAB:mode] session · phase → next · N active · $cost/max (pct%)`) via `settings.json` — pull-model snapshot, re-rendered every host tick.
- **`monitors` manifest key** (Claude Code ≥ v2.1.105) declares `tab-session-monitor`, backed by `scripts/monitor.sh` — streams JSON-line events for phase transitions, subagent start/return, and budget thresholds (push-model complement to the statusline).
- `settings.json` declares `additionalDirectories: [".epic", "TAB/sessions", "TAB/decisions"]` — host protects these paths from accidental mutation (Claude Code ≥ v2.1.90).

#### Model & cache strategy

- **Champion** and **Auditor** pinned to `claude-opus-4-7` (Claude Code ≥ v2.1.111); Auditor runs at `effort: xhigh` for adversarial verification.
- All five agents carry an `MCP result persistence` section instructing them to attach `_meta["anthropic/maxResultSizeChars"]: 500000` to every `perplexity_search` / `perplexity_research` / `perplexity_reason` / `context7 query-docs` / `brave_web_search` call (Claude Code ≥ v2.1.91). Research cache now survives context compaction and can be cited verbatim by downstream phases without re-fetching.
- `skills/tab/references/research-budget.md` §9 documents the `_meta` protocol; `skills/tab/references/automation.md` §7.1 documents `ENABLE_PROMPT_CACHING_1H=1` as the recommended default for every headless TAB invocation in Complete / Complete+ modes (Claude Code ≥ v2.1.108).
- `examples/ci-github-actions.yml` enables `ENABLE_PROMPT_CACHING_1H=1` in the TAB step and fails fast when `plugin_errors[]` in the stream-json init event contains `tech-advisory-board` (Claude Code ≥ v2.1.111).

#### User interaction

- Clarification rounds (`skills/tab/SKILL.md` §5 and `skills/tab/references/debate-protocol.md` Post-Research Clarification) invoke the native `AskUserQuestion` tool (Claude Code ≥ v2.1.76); `Elicitation` / `ElicitationResult` hooks integrate for telemetry; `PreToolUse` `updatedInput` is the documented headless path.
- Moderator rule #9: push notification when the auditor returns on a long Complete / Complete+ session (>20 min) — Claude Code ≥ v2.1.110.
- `skills/rechallenge/SKILL.md` documents `EnterWorktree` / `ExitWorktree` isolation with a `path` argument (Claude Code ≥ v2.1.72) — all Rechallenge mutations live in a discardable branch; fallback in place for hosts without worktree support.

#### Cost tracking

- `bin/tab-compute-cost` supports three modes: positional `<model> <in> <out>`, `--from-telemetry <path>`, and `--from-cost-stdin` (Claude Code ≥ v2.1.92). The stdin mode consumes the native `/cost` breakdown and re-emits the totals block with per-model + cache-hit accounting, preferred over the heuristic rate table when available.

#### Documentation

- `docs/MCP_SETUP.md` — setup instructions for the recommended `perplexity`, `context7`, `brave-search` MCP servers.
- `docs/MANAGED_SETTINGS.md` — `managed-settings.d/` drop-ins for org-level policy (Claude Code ≥ v2.1.83): disable auditor/supervisor, pin cheaper models, cap spend, `allowManagedHooksOnly` (Claude Code ≥ v2.1.101).
- `docs/PERMISSIONS.md` — catalogue of TAB's read-only vs mutating commands with ready-to-paste `allow` / `deny` blocks for `.claude/settings.local.json`.
- `docs/TROUBLESHOOTING.md` — plugin-level failure modes: `disableSkillShellExecution`, PreCompact stuck in block, Opus 4.7 unavailable, cache misses, monitor silence, scheduled rechallenge not firing.
- `skills/tab/references/automation.md` §7.2 documents the `PreToolUse: "defer"` pattern (Claude Code ≥ v2.1.89) as a scoped alternative to `--dangerously-skip-permissions` for auto-approving MADR mutations in CI (`tab-new-adr`, `tab-supersede-adr`); §7.3 shows a `PermissionDenied` hook that appends to `TAB/sessions/latest/denials.ndjson` for auto-mode policy tuning.

### Design decisions not taken

- **Moving identity-cards into agent `initialPrompt`** was considered and rejected. Identity cards are intrinsically dynamic (name, bias, blind-spot, credentials vary per Champion / Advisor instantiation), and the agent's Markdown body is already injected as the system prompt. Moving boilerplate into a static `initialPrompt` would either flatten variability or require a per-invocation override, cancelling the payload saving.
