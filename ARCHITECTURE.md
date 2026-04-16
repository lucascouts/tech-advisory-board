# TAB Architecture

This document consolidates the 16 references under `skills/tab/references/` into a single navigable map. For authoritative detail, follow the links — this page is a table of contents with one-paragraph summaries.

## Pipeline at a glance

```
Phase -1  Bootstrap               → init TAB/, resume-detection, config snapshot
Phase  0  Argument Processing     → intent detection (Analyze/Improve/Create/Continue)
Phase  1  Context Extraction      → 20 questions, auto-skip answered
Phase  2  Complexity Classification → Express / Quick / Standard / Complete / Complete+
Phase  3  Research                → parallel researcher subagents, query budget T1-T5
Phase  4  Landscape Scan          → shortlist (3-6) + discard table
Phase  5  Champion Debate         → parallel champion subagents (2-5)
Phase  5.5 Supervisor Gate        → conditional — 4 §12.1 triggers
Phase  6  Cross-Examination       → Option A (subagent) / Option B (main context)
Phase  6.5 Auditor                → mandatory in Complete/Complete+/Rechallenge
Phase  7  Advisor Evaluation      → parallel advisor subagents
Phase  8  Score Consolidation     → matrix + divergence resolution
Phase  9  Wildcard                → conditional same-ecosystem tiebreak
Phase 10  Synthesis               → synthesis.json + report.md + ADR
```

## Reference map

### Identity and protocol

| Document | What it defines |
|---|---|
| [`archetypes.md`](skills/tab/references/archetypes.md) | 12 champion archetypes and the identity-card generator |
| [`specialists.md`](skills/tab/references/specialists.md) | Core roster of 6 advisor dimensions + dynamic-generation template |
| [`debate-protocol.md`](skills/tab/references/debate-protocol.md) | Mode-aware phases, research fallback, 2-source rule |
| [`stage-definitions.md`](skills/tab/references/stage-definitions.md) | POC / MVP / Full — full-spectrum coverage rule |
| [`intent-detection.md`](skills/tab/references/intent-detection.md) | Semantic classifier (Analyze/Improve/Create/Continue) |

### Adversarial layers

| Document | What it defines |
|---|---|
| [`adversarial-triggers.md`](skills/tab/references/adversarial-triggers.md) | 4 layers: concession monitor, supervisor gate, wildcard, auditor |
| [`confidence-tags.md`](skills/tab/references/confidence-tags.md) | `[high-conf]`, `[med-conf]`, `[low-conf]`, `[unverified]` |
| [`research-budget.md`](skills/tab/references/research-budget.md) | Per-mode base query budget + T1-T5 expansion triggers |

### Output contracts

| Document | What it defines |
|---|---|
| [`synthesis-schema.md`](skills/tab/references/synthesis-schema.md) | The canonical `synthesis.json` contract consumed by CI |
| [`synthesis-template.md`](skills/tab/references/synthesis-template.md) | Mode-specific rendering of the synthesis |
| [`output-examples.md`](skills/tab/references/output-examples.md) | Worked examples per mode |
| [`context-extraction.md`](skills/tab/references/context-extraction.md) | 20 context questions, auto-skip rules |

### Lifecycle and automation

| Document | What it defines |
|---|---|
| [`persistence-protocol.md`](skills/tab/references/persistence-protocol.md) | `state.json` + `state-full.json` per-phase persistence |
| [`hooks-catalog.md`](skills/tab/references/hooks-catalog.md) | 8 hook events and their scripts |
| [`automation.md`](skills/tab/references/automation.md) | `claude -p` / `--bare` / Agent SDK recipes |
| [`flow-and-modes.md`](skills/tab/references/flow-and-modes.md) | Mode matrix and phase-to-mode mapping |

### Rechallenge

| Document | What it defines |
|---|---|
| [`rechallenge-protocol.md`](skills/rechallenge/references/rechallenge-protocol.md) | Delta research, auditor re-run, verdict (still-valid / needs-revision / supersede) |

## Output artifacts per session

```
TAB/
├── config.json           ← project-level config (budget, preferences, stage)
├── index.md              ← index of all ADRs
├── decisions/
│   ├── 0001-<slug>.md    ← ADRs in MADR format
│   └── …
└── sessions/
    ├── <session-id>/
    │   ├── state.json          ← per-phase snapshot
    │   ├── state-full.json     ← claims registry, subagents, checkpoints
    │   ├── telemetry.json      ← tokens, cost, phase durations
    │   ├── synthesis.json      ← canonical contract (validated at Stop)
    │   └── report.md           ← rendered markdown for humans
    └── archived/
        └── <idle-sessions>/    ← moved by archive-idle-sessions.sh
```

## Schema reference

All JSON artifacts are validated against Draft 2020-12 schemas under [`schemas/`](schemas/):

- `config.schema.json` — budget, preferences, adversarial knobs
- `state.schema.json` — minimal per-phase snapshot
- `state-full.schema.json` — claims registry with source/confidence/contested_by
- `telemetry.schema.json` — tokens, cost, phase durations, rates used
- `synthesis.schema.json` — session, context, landscape, champions, scores, recommendation, risks, auditor_findings, supervisor_dissent
- `research-cache.schema.json` — sha256-keyed query cache
- `vanguard-timeline.schema.json` — cross-project maturity ledger

## Further reading

- [`README.md`](README.md) — user-facing installation and usage.
- [`CHANGELOG.md`](CHANGELOG.md) — version history.
- [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md) — recommended MCP servers.
- [`examples/`](examples/) — headless SDK usage, CI workflow, scheduled rechallenge.
