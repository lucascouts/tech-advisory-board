# Changelog

All notable changes to this plugin are documented here. This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-04-16

Initial plugin release.

### Added

- Plugin manifest (`.claude-plugin/plugin.json`) with 7 `userConfig` knobs (cost ceiling, warning threshold, language preference, default mode, auditor toggle, supervisor gate toggle, ADR dir override).
- Single-plugin marketplace manifest (`.claude-plugin/marketplace.json`).
- Two skills: `tab` (full advisory-board deliberation, 13 phases, Express → Complete+ modes) and `rechallenge` (compressed delta review of a prior ADR, `disable-model-invocation: true`).
- Five subagents: `researcher` (Sonnet, `memory: project`), `champion` (Opus), `advisor` (Sonnet), `auditor` (Opus, `memory: project`, mandatory in Complete/Complete+/Rechallenge), `supervisor` (Sonnet, conditional on consensus-theater triggers).
- Eight lifecycle hooks: `SessionStart`, `UserPromptSubmit`, `PreCompact`, `PostCompact`, `PostToolUse` (matcher `Write(**/TAB/sessions/**)`), `SubagentStop`, `Stop` (gate via `decision:"block"`), `SessionEnd`.
- Eight bin commands auto-added to PATH: `tab-init-dir`, `tab-resume-session`, `tab-compute-cost`, `tab-new-adr`, `tab-supersede-adr`, `tab-vanguard-timeline`, `tab-schedule-rechallenge`, `tab-check-mcps`.
- Seven JSON schemas (Draft 2020-12) for `config`, `state`, `state-full`, `telemetry`, `synthesis`, `research-cache`, `vanguard-timeline`.
- Sixteen reference documents under `skills/tab/references/` covering archetypes, specialists, debate protocol, intent detection, stage definitions, synthesis template and schema, context extraction, output examples, confidence tags, adversarial triggers, research budget, persistence protocol, hooks catalog, automation, flow and modes.
- One reference under `skills/rechallenge/references/` describing the rechallenge protocol.
- Evals suite (`evals/evals.json`) with 48 test cases plus three project fixtures (`simple-node-api`, `python-cli`, `messy-project`).
- `ARCHITECTURE.md` consolidating the reference map.
- `docs/MCP_SETUP.md` with setup instructions for the recommended `perplexity`, `context7`, `brave-search` MCP servers.
- `examples/` directory with a GitHub Actions CI workflow, Python and TypeScript Agent SDK snippets, and a scheduled-rechallenge tutorial.
- Subagent status line (`[TAB:mode] session · phase → next · N active · $cost/max (pct%)`) via `settings.json`.
