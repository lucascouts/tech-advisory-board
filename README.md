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

### Subagents (5)

| Agent | Model | Role |
|---|---|---|
| `researcher` | Sonnet, `memory: project` | Web research with MCP fallbacks; accumulates notes across sessions |
| `champion` | Opus | Stack advocate; 4-section presentation (+ Vanguard readiness) |
| `advisor` | Sonnet | Independent dimensional evaluator, scores 1-10 per dimension |
| `auditor` | Opus, `memory: project` | Adversarial review of near-final synthesis (Complete/Complete+/Rechallenge) |
| `supervisor` | Sonnet | Conditional consensus-theater gate (fires on §12.1 triggers) |

All agents are invoked as parallel subagents via `subagent_type: "tech-advisory-board:<name>"` in the Agent tool.

### Hooks (17 events)

| Event | Script | Purpose |
|---|---|---|
| `SessionStart` | `scripts/detect-interrupted.sh` | Detect resumable TAB sessions, emit resume hint |
| `UserPromptSubmit` | `scripts/inject-tab-context.sh` | Inject auto-detected project context on TAB-intent prompts |
| `PreCompact` | `scripts/flush-state.sh` | Force state persistence before context reclaim |
| `PostCompact` | `scripts/rehydrate-state.sh` | Re-inject phase / mode / claims digest + `session_language` after compaction |
| `PostToolUse` (Write TAB/sessions/**) | `scripts/update-telemetry.sh` | Track artifact writes into telemetry.json |
| `TaskCreated` | `scripts/on-task-created.sh` | Record subagent spawn timing into `state-full.json` |
| `SubagentStart` | `scripts/on-subagent-start.sh` | Native start pair of `SubagentStop` — exact wall-clock timing for the timeline Gantt |
| `SubagentStop` | `scripts/update-telemetry-subagent.sh` | Native subagent lifecycle → telemetry + state-full |
| `Stop` | `scripts/validate-on-stop.sh` | Gate session close on `validate-synthesis-json.sh` + `validate-claims.sh` |
| `StopFailure` | `scripts/on-stop-failure.sh` | Capture Stop-gate failures for retry / debugging |
| `CwdChanged` | `scripts/on-reactive-change.sh` | Detect workspace switch mid-session |
| `FileChanged` (`TAB/**`) | `scripts/on-reactive-change.sh` | React to external ADR / synthesis edits |
| `InstructionsLoaded` (`session_start`, `compact`) | `scripts/on-instructions-loaded.sh` | Re-inject locked `session_language` on re-hydration and CLAUDE.md changes |
| `Elicitation` | `scripts/on-elicitation.sh` | Record every `AskUserQuestion` round into `telemetry.json.elicitations[]` (discard-triage instrumentation) |
| `ElicitationResult` | `scripts/on-elicitation.sh` | Same script; captures the user's answer metadata |
| `PermissionDenied` | `scripts/on-permission-denied.sh` | Append blocked tools to `<session>/denials.ndjson` for auto-mode policy tuning |
| `SessionEnd` | `scripts/archive-idle-sessions.sh` | Redundant archival safety net |

### Bin commands (auto-added to PATH when plugin is active)

| Command | Purpose |
|---|---|
| `tab-init-dir` | Lazy init of project's `TAB/` directory (idempotent) |
| `tab-check-mcps` | Diagnose MCP availability (perplexity, context7, brave-search) |
| `tab-resume-session` | Scan for resumable sessions, emit JSON payload |
| `tab-compute-cost` | USD cost computation from telemetry or ad-hoc |
| `tab-new-adr` | MADR generator from `synthesis.json` |
| `tab-supersede-adr` | Link ADR pairs (supersede / revision modes) |
| `tab-vanguard-timeline` | Cross-project Vanguard maturity ledger |
| `tab-schedule-rechallenge` | Prepare scheduled rechallenge per ADR |
| `tab-cache` | Manage the cross-session research cache (list / invalidate / prune) |
| `tab-score-zscore` | Normalize the advisor score matrix via per-advisor z-score before ranking |
| `tab-record-outcome` | Update an ADR's `outcome:` frontmatter block (status / measured_at / predicted vs actual / lessons) |
| `tab-open-timeline` | Render + open the session timeline HTML in the browser (self-contained, reads `timeline-events.ndjson`) |

### Scripts (lifecycle helpers)

`extract-context.sh`, `load-config.sh`, `statusline.sh`, `validate-synthesis.sh`, `validate-synthesis-json.sh`, `validate-claims.sh`, plus the hook scripts above.

### Schemas (`schemas/`)

Draft 2020-12 JSON Schemas for `TAB/config.json`, `state.json`, `state-full.json`, `telemetry.json`, `synthesis.json`, `research-cache.json`, `vanguard-timeline.json`.

### Other

- `settings.json`: wires `subagentStatusLine` to `scripts/statusline.sh`.
- `evals/evals.json`: 54 test cases (48 happy-path + 6 failure-mode: MCP down, budget burst, Opus unavailable, python3 absent, forced compaction, concurrent ADR writes) + 3 project fixtures (simple-node-api, python-cli, messy-project).
- 15 reference documents under `skills/tab/references/` (archetypes, specialists, debate protocol, intent detection, stage definitions, synthesis template, synthesis schema, context extraction, output examples, confidence tags, adversarial triggers, research budget, persistence protocol, hooks catalog, automation, flow-and-modes).
- 1 reference under `skills/rechallenge/references/` (rechallenge protocol).

## Requirements

### Runtime

- Claude Code with Agent tool support.
- **`python3` ≥ 3.9** in PATH. All lifecycle scripts and validators use Python stdlib only (no external packages). On minimal container images (alpine, distroless, CI runners), install `python3` explicitly or the plugin degrades silently — `SessionStart` will emit a visible warning if it's missing.

### Recommended MCPs

Provided by the host session (not bundled): `perplexity`, `context7`, `brave-search`. The plugin-shipped agents declare MCP tool names in their `tools:` allowlist but cannot declare `mcpServers` themselves (plugin validator restriction). See [`docs/MCP_SETUP.md`](./docs/MCP_SETUP.md) for setup instructions and `bin/tab-check-mcps` for a diagnostic.

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
/tech-advisory-board:rechallenge TAB/decisions/0003-database-selection.md
```

Or let Claude auto-trigger `tab` when you ask a decision question:

```
Which database should I use for 1M IoT events per second?
```

(`rechallenge` is `disable-model-invocation: true` — it only runs when invoked explicitly with a path.)

The board will:

1. **Bootstrap** — init `TAB/` workspace, load config, detect resumable sessions.
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
| `default_mode` | *(unset)* | Preferred mode when classifier is ambiguous (Instant / Fast / Standard / Complete / Complete+; legacy `Express`/`Quick` accepted for one version) |
| `auditor_enabled` | true | Run Auditor in Complete / Complete+ / Rechallenge |
| `supervisor_gate_enabled` | true | Fire Supervisor on §12.1 triggers |
| `adr_dir_override` | *(unset)* | Override the default `TAB/decisions/` directory |

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

Inspect the schemas under `schemas/` when modifying `state*.json`, `synthesis.json`, `telemetry.json`, `research-cache.json`, `vanguard-timeline.json`, or `TAB/config.json`.

## License

MIT — see [LICENSE](./LICENSE).

## Author

[lucascouts](https://github.com/lucascouts) · lucascs@protonmail.com

## Version

0.1.1 — see [CHANGELOG](./CHANGELOG.md).
