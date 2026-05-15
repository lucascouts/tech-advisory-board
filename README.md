# Technical Advisory Board (TAB)

A Claude Code plugin that convenes an **expert advisory board** to deliberate on technical decisions. Instead of a single answer, you get a structured multi-agent debate: Champions advocate competing technologies, Advisors evaluate from independent dimensions, a Landscape Scout maps the full alternative space, an Auditor adversarially reviews the near-final synthesis, a Supervisor challenges consensus-theater, and a Lead Moderator orchestrates the session.

Backed by current web research via MCPs (perplexity, context7, brave-search), every recommendation cites verifiable data rather than model knowledge.

## What it's for

- **Stack selection**: "What should I use to build X?"
- **Architecture choices**: monolith vs. microservices, REST vs. GraphQL, multi-tenancy strategies
- **Framework/database comparisons**: Next.js vs. Remix, Postgres vs. MongoDB, Prisma vs. Drizzle
- **Project planning**: POC → MVP → Full product roadmaps
- **Project analysis and evolution**: "Analyze this project", "Evolve this MVP to production"
- **Decision review**: re-test a prior ADR via `/tech-advisory-board:rechallenge`

**Not for**: debugging, code review, implementation, refactoring, or deployment tasks.

## What's inside

### Skills

| Skill | Invocation | Purpose |
|---|---|---|
| `tab` | `/tech-advisory-board:tab "<question>"` | Full advisory-board deliberation |
| `rechallenge` | `/tech-advisory-board:rechallenge <ADR-path>` | Re-test a prior ADR for continued validity (explicit invocation only) |
| `explain-synthesis` | `/tech-advisory-board:explain-synthesis <path-to-synthesis.json>` | Explain an old synthesis in three paragraphs without loading 100KB+ of JSON into the main context (`context: fork`, uses the `Explore` subagent) |

### Subagents (5)

| Agent | Model | Role |
|---|---|---|
| `researcher` | Sonnet, `memory: project` | Web research with MCP fallbacks; accumulates notes across sessions |
| `champion` | Opus | Stack advocate; 4-section presentation (+ Vanguard readiness) |
| `advisor` | Sonnet | Independent dimensional evaluator, scores 1-10 per dimension |
| `auditor` | Opus, `memory: project` | Adversarial review of near-final synthesis (Complete/Complete+/Rechallenge) |
| `supervisor` | Sonnet | Conditional consensus-theater gate (fires on §12.1 triggers) |

All agents are invoked as parallel subagents via `subagent_type: "tech-advisory-board:<name>"` in the Agent tool.

### Hooks

Events are declared in two layers:

- **Global** (`hooks/hooks.json`) — always active while the plugin is enabled.
- **Skill-scoped** (`hooks:` frontmatter in `skills/tab/SKILL.md` and `skills/rechallenge/SKILL.md`) — only active during the lifecycle of a TAB or Rechallenge skill invocation. Used for `PreCompact`, `PostCompact`, `Stop` to avoid hook-noise in non-TAB sessions.

| Event | Scope | Script | Purpose |
|---|---|---|---|
| `SessionStart` | global | `scripts/detect-interrupted.sh` + inline `node` check | Resume hint + runtime-deps warning |
| `UserPromptSubmit` | global | `scripts/inject-tab-context.sh` | Inject auto-detected project context on TAB-intent prompts (respects `strict_paths`) |
| `PreCompact` | skill (`tab`, `rechallenge`) | `scripts/flush-state.sh` | Force state persistence before context reclaim (blocks compaction in critical phases) |
| `PostCompact` | skill (`tab`, `rechallenge`) | `scripts/rehydrate-state.sh` | Re-inject phase / mode / claims digest + `session_language` after compaction |
| `PostToolUse` (Write .tab/sessions/**) | global | `scripts/update-telemetry.sh` | Track artifact writes into telemetry.json |
| `PostToolUseFailure` (`mcp__.*\|WebFetch\|WebSearch`) | global | `scripts/on-tool-failure.sh` | Capture tool errors into `telemetry.json.mcp_failures[]`; suggest WebSearch fallback after 3× |
| `TaskCreated` | global | `scripts/on-task-created.sh` | Record subagent spawn timing into `state-full.json` |
| `TaskCompleted` | global | `scripts/on-task-completed.sh` | Close open entries in `subagents_invoked[]`; bump `tasks_completed` / `tasks_failed` |
| `SubagentStart` | global | `scripts/on-subagent-start.sh` | Native start pair of `SubagentStop` — exact wall-clock timing for the timeline Gantt |
| `SubagentStop` | global | `scripts/update-telemetry-subagent.sh` | Native subagent lifecycle → telemetry + state-full |
| `Stop` | skill (`tab`, `rechallenge`) | `scripts/validate-on-stop.sh` | Gate session close on `validate-synthesis-json.sh` + `validate-claims.sh` |
| `StopFailure` | global | `scripts/on-stop-failure.sh` | Capture Stop-gate failures for retry / debugging |
| `CwdChanged` | global | `scripts/on-reactive-change.sh` | Detect workspace switch mid-session |
| `FileChanged` (TAB artifacts) | global | `scripts/on-reactive-change.sh` | React to external ADR / synthesis / state edits |
| `InstructionsLoaded` (`session_start`, `compact`) | global | `scripts/on-instructions-loaded.sh` | Re-inject locked `session_language` on re-hydration and CLAUDE.md changes |
| `Elicitation` | global | `scripts/on-elicitation.sh` | Record every `AskUserQuestion` round into `telemetry.json.elicitations[]` (discard-triage instrumentation) |
| `ElicitationResult` | global | `scripts/on-elicitation.sh` | Same script; captures the user's answer metadata |
| `PermissionDenied` | global | `scripts/on-permission-denied.sh` | Append blocked tools to `<session>/denials.ndjson` for auto-mode policy tuning |
| `PermissionRequest` (Read/Glob/Grep on .tab/**) | global | `scripts/on-permission-request.sh` | Auto-approve read-only access to TAB artifacts (Moderator re-reads its own state) |
| `SessionEnd` | global | `scripts/archive-idle-sessions.sh` | Redundant archival safety net |
| `Notification` | global | `scripts/on-notification.sh` | Route failed Rechallenge sessions through `channel` MCP push (Telegram / webhook) |
| `TeammateIdle` | global | `scripts/on-teammate-idle.sh` | Capture teammate stalls in real Agent Teams cross-exam → `telemetry.json.teammate_idles[]` |
| `ConfigChange` | global | `scripts/on-config-change.sh` | Record user/project/local/policy settings mutations into `state-full.json.config_changes[]` |
| `PostToolUse(EnterWorktree\|ExitWorktree)` | global | `scripts/on-worktree-tool.sh` | Primary observer of Rechallenge worktree usage — pairs `enter` / `exit` events by `tool_use_id` in `<session>/worktrees.ndjson` (source=`tool`) |
| `WorktreeRemove` | global | `scripts/on-worktree-remove.sh` | Observational counterpart for harness-driven worktree removals (source=`remove`) |
| `SubagentStart` / `SubagentStop` (snapshot) | global | `scripts/snapshot-worktrees.sh` | Safety-net diff against `git worktree list --porcelain`; logs creations / removals that bypassed the tool hooks (source=`snapshot`) |

### Bin commands (auto-added to PATH when plugin is active)

| Command | Purpose |
|---|---|
| `init-dir` | Lazy init of project's `.tab/` directory (idempotent) |
| `check-mcps` | Diagnose MCP availability (perplexity, context7, brave-search) |
| `resume-session` | Scan for resumable sessions, emit JSON payload |
| `compute-cost` | USD cost computation from telemetry or ad-hoc |
| `new-adr` | MADR generator from `synthesis.json` |
| `supersede-adr` | Link ADR pairs (supersede / revision modes) |
| `vanguard-timeline` | Cross-project Vanguard maturity ledger |
| `schedule-rechallenge` | Prepare scheduled rechallenge per ADR |
| `cache` | Manage the cross-session research cache (list / invalidate / prune) |
| `score-zscore` | Normalize the advisor score matrix via per-advisor z-score before ranking |
| `record-outcome` | Update an ADR's `outcome:` frontmatter block (status / measured_at / predicted vs actual / lessons) |
| `open-timeline` | Render + open the session timeline HTML in the browser (self-contained, reads `timeline-events.ndjson`) |

### Scripts (lifecycle helpers)

`extract-context.sh`, `load-config.sh`, `statusline.sh`, `validate-synthesis-json.sh`, `validate-claims.sh`, plus the hook scripts above. The legacy markdown validator (`validate-synthesis.sh`) was removed in 0.1.1 — the JSON validator is the single source of truth, language-agnostic and schema-driven.

### Schemas (`schemas/`)

Draft 2020-12 JSON Schemas for `.tab/config.json`, `state.json`, `state-full.json`, `telemetry.json`, `synthesis.json`, `research-cache.json`, `vanguard-timeline.json`.

The consumer contract for `synthesis.json` — the only artifact external tools should parse — is documented in [`docs/SYNTHESIS_CONTRACT.md`](./docs/SYNTHESIS_CONTRACT.md).

Maintainers refactoring frontmatter, hooks, `.lsp.json`, or skill shell blocks should first read [`docs/PLUGIN_CONFORMANCE.md`](./docs/PLUGIN_CONFORMANCE.md) — it lists which TAB patterns are canonical per the official Claude Code spec (so they don't get removed by mistake) and the only two points that genuinely depend on experimental features.

### Other

- `settings.json`: wires `subagentStatusLine` to `scripts/statusline.sh`.
- `evals/evals.json`: 55 test cases (36 should-trigger + 19 should-not-trigger, covering MCP down, budget burst, Opus unavailable, python3 absent, forced compaction, concurrent ADR writes, agent-teams resolver, rechallenge collision) + 3 project fixtures (simple-node-api, python-cli, messy-project).
- 20 reference documents under `skills/tab/references/` (archetypes, specialists, debate protocol, intent detection, stage definitions, synthesis template, synthesis schema, context extraction, output examples, confidence tags, adversarial triggers, research budget, persistence protocol, hooks catalog, automation, flow-and-modes, agent-teams-mode, coi-disclosure, model-policy, triage-protocol) plus `verification-checklist/SKILL.md` loaded by the auditor via `skills:` frontmatter.
- 1 reference under `skills/rechallenge/references/` (rechallenge protocol).

## Requirements

### Runtime

- Claude Code with Agent tool support.

### Runtime Dependencies

| Dependency | Minimum version | Used for | Missing → |
|---|---|---|---|
| `python3` | 3.9 | All lifecycle scripts, validators, config merge, telemetry, COI checks | `SessionStart` emits a visible warning; validators no-op (session continues but Stop-gate skipped) |
| `node` | 18 | Optional: LSP servers (`.lsp.json`) for Python/TS analysis, some MCP stdio bridges | `SessionStart` emits a visible warning; LSP falls back to Read/Grep |
| `git` | any | `scripts/extract-context.sh`, Rechallenge worktree isolation | Context extraction emits partial data; rechallenge falls back to in-place |
| `jq` | any | Optional, used by `examples/ci-github-actions.yml` for hook JSON assembly | CI example step fails; not used at runtime |

On minimal container images (alpine, distroless, CI runners), install
`python3` and `node` explicitly. The plugin runs in **degraded mode**
without them (validators no-op, LSP absent), but does not abort — the
synthesis will simply carry lower-confidence tags.

### Recommended MCPs

The plugin requires three **capabilities** (web search, library docs, cross-validation search), not specific vendors. The author's preferences are `perplexity`, `context7`, and `brave-search` — those names appear in every agent's `tools:` allowlist as sensible defaults. These are the **author's preferences**; other MCPs with equivalent capabilities (Tavily, Exa, Kagi, etc.) are accepted — see [`docs/MCP_SETUP.md`](./docs/MCP_SETUP.md) for the capability contract and how to substitute. The plugin-shipped agents cannot declare `mcpServers` themselves (plugin validator restriction); install them at the host level. Use `bin/check-mcps` for a diagnostic against the default trio.

Works in **degraded mode** without MCPs via built-in `WebSearch` — claims will be flagged `[unverified]` in the synthesis.

## Installation

### Option 1: Install from marketplace

```bash
/plugin marketplace add lucascouts/tech-advisory-board
/plugin install tech-advisory-board@tech-advisory-board
```

### Option 2: Install locally (development)

```bash
git clone https://github.com/lucascouts/tech-advisory-board.git
claude --plugin-dir ./tech-advisory-board
```

Use `/reload-plugins` after local edits to pick up changes without restarting.

## Usage

Invoke the tab skill directly:

```
/tech-advisory-board:tab "I want to build a multi-tenant SaaS for marketing agencies"
```

Invoke with a project path to analyze existing code:

```
/tech-advisory-board:tab ./src/api
```

Rechallenge a prior ADR:

```
/tech-advisory-board:rechallenge .tab/decisions/0003-database-selection.md
```

Or let Claude auto-trigger `tab` when you ask a decision question:

```
Which database should I use for 1M IoT events per second?
```

(`rechallenge` is `disable-model-invocation: true` — it only runs when invoked explicitly with a path.)

The board will:

1. **Bootstrap** — init `.tab/` workspace, load config, detect resumable sessions.
2. **Extract context** — team, budget, timeline, constraints (skips what auto-detected context already covers).
3. **Classify complexity** — Trivial / Simple / Moderate / High / Very High+. Respects `userConfig.default_mode` when the classifier is ambiguous.
4. **Run research** — parallel `researcher` subagents, one per alternative.
5. **Map landscape** — shortlist + discard table (every plausible tool accounted for).
6. **Champion debate** — 2-5 `champion` subagents advocate their stacks with directed research.
7. **Cross-examination** — champions challenge each other's claims (Option A or B by mode).
8. **Advisor evaluation** — parallel `advisor` subagents score independently per dimension.
9. **Supervisor gate** (conditional) — fires if §12.1 consensus-theater triggers match.
10. **Score consolidation + Wildcard** (conditional).
11. **Auditor** (mandatory in Complete / Complete+ / Rechallenge) — adversarial review across 6 dimensions.
12. **Synthesis** — emits both `synthesis.json` (canonical) and `report.md` (rendered); auto-generates ADR in Standard+ modes.
13. **Stop gate** — `validate-on-stop.sh` blocks session close if synthesis fails hard-fail assertions.

## Session modes

| Flag | Example | Mode |
|---|---|---|
| Trivial | "Ruff or Black?" | Instant (direct answer) |
| Simple | "Which ORM for Postgres?" | Fast (2 Champions) |
| Moderate | "Backend for real-time REST API" | Standard (3 Champions + 3-4 Advisors) |
| High | "Full stack for multi-tenant SaaS" | Complete (full flow + mandatory Auditor) |
| Very High+ | "Monolith → microservices, zero downtime" | Complete+ (extended flow) |

Full mode capabilities, phase diagram, and phase-to-mode matrix live in `skills/tab/references/flow-and-modes.md`.

## User configuration

Prompted at plugin-enable time (stored in your user / project settings; the `sensitive:` knobs would persist to the keychain but all current knobs are non-sensitive):

| Knob | Default | Purpose |
|---|---|---|
| `max_cost_per_session_usd` | 5.00 | Hard budget ceiling (aborts session on breach) |
| `warn_at_usd` | 3.00 | Soft warning threshold |
| `language_preference` | *(unset)* | BCP 47 tag used when first message is ambiguous |
| `default_mode` | *(unset)* | Preferred mode when classifier is ambiguous (Instant / Fast / Standard / Complete / Complete+) |
| `strict_paths` | `false` | Auto-activate `tab` only in directories with a project manifest. `false` preserves greenfield ("stack for X?" in empty cwd). Set `true` to reduce auto-trigger conflicts when multiple plugins compete |
| `auditor_enabled` | true | Run Auditor in Complete / Complete+ / Rechallenge |
| `supervisor_gate_enabled` | true | Fire Supervisor on §12.1 triggers |
| `adr_dir_override` | *(unset)* | Override the default `.tab/decisions/` directory |
| `agent_team_mode` | `subagents` | Cross-exam backend in Complete / Complete+. `subagents` = simulated fan-out (default, **stable**). `agent_teams` = real Agent Teams — **experimental per Anthropic docs; API may change between minor CC versions** (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; ~2–3× cost). `auto` = prefer Agent Teams when the env var is set, silently fall back to subagents otherwise. SessionStart emits a visible warning if you pin `agent_teams` without the env var. See `skills/tab/references/agent-teams-mode.md` |

## Language

The board auto-detects your language from the first message and mirrors it throughout. Technical terms, library names, and acronyms always stay in English. `language_preference` disambiguates on the first turn if the detection is ambiguous.

## Automation surface

Automation details (hooks catalog, `claude -p` / `--bare` recipes, Python and TypeScript Agent SDK snippets, CI workflow templates, consumer-contract checklist) live in:

- `skills/tab/references/hooks-catalog.md`
- `skills/tab/references/automation.md`

The subagent status line (`[TAB:mode] session · phase → next · N active · $cost/max (pct%)`) is enabled by default; silence it by unsetting `settings.json.subagentStatusLine` or by running in a cloud/remote session (`CLAUDE_CODE_REMOTE=true`).

## Development

Run the evals during plugin development:

```bash
# 47 cases + 3 project fixtures under evals/
# See the skill-creator skill for harness details
```

Validate the plugin manifest:

```bash
/plugin validate .
# or
claude plugin validate .
```

Inspect the schemas under `schemas/` when modifying `state*.json`, `synthesis.json`, `telemetry.json`, `research-cache.json`, `vanguard-timeline.json`, or `.tab/config.json`.

---

## Contributing

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the maintainer-facing
overview: pipeline, persistence layer, hook web, invariants, and
extension points.

## License

MIT — see [LICENSE](./LICENSE).

## Author

[lucascouts](https://github.com/lucascouts) · lucascs@protonmail.com

## Version

0.1.3 — see [CHANGELOG](./CHANGELOG.md).
