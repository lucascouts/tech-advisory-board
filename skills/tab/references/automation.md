---
version: 1.0
last_updated: 2026-04-16
scope: Block 6 — headless + Agent SDK integration (ARCHITECTURE.md §18)
audience: CI/CD engineers, automation builders, external tool authors
---

# Automation & Integration

TAB is designed to be driven interactively, but its artifacts
(`synthesis.json`, ADRs, telemetry) are meant for downstream
consumption. This reference explains how to run TAB from CI, from
scripts, and from the Claude Agent SDK — and what invariants hold when
it runs non-interactively.

## 1. Headless invocation via `claude -p`

```bash
claude -p '/tech-advisory-board:tab "Postgres vs MongoDB for 1M IoT events/sec"' \
    --output-format json \
    --json-schema ${CLAUDE_PLUGIN_ROOT}/schemas/synthesis.schema.json \
    --allowedTools "Agent,AskUserQuestion,Read,Write,Edit,Grep,Glob,LSP,WebSearch,WebFetch,TodoWrite,mcp__perplexity__*,mcp__plugin_context7_context7__*,mcp__brave-search__*,Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*),Bash(${CLAUDE_PLUGIN_ROOT}/bin/*),Bash(git *)"
```

Flags explained:

| Flag | Purpose |
|---|---|
| `-p '...'` | Non-interactive single-prompt invocation |
| `--output-format json` | Emit `{session_id, usage, result}` JSON rather than transcript text |
| `--json-schema <path>` | Coerce `result` to match the canonical synthesis schema |
| `--allowedTools "..."` | Pre-authorize every tool TAB needs; without this the Moderator is paused on every permission prompt |

### 1.1 Minimum allow-list

TAB's required host capabilities:

- `Agent` — to spawn researcher/champion/advisor/auditor/supervisor subagents
- `AskUserQuestion` — clarifications (auto-skipped in headless, but still declared)
- `Read`, `Write`, `Edit` — artifact authoring
- `Grep`, `Glob`, `LSP` — code-context inspection for Analyze/Evolve intents
- `WebSearch`, `WebFetch` — research fallbacks when MCP is absent
- `TodoWrite` — phase tracking
- `mcp__perplexity__*`, `mcp__plugin_context7_context7__*`, `mcp__brave-search__*` — MCP research tools (when configured)
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)`, `Bash(${CLAUDE_PLUGIN_ROOT}/bin/*)` — plugin scripts
- `Bash(git *)` — git introspection in `extract-context.sh`

### 1.2 Headless invariants (ARCHITECTURE.md §18.4)

When running via `-p`:

- Clarification rounds (§1.5, §2 mid-session) are **auto-skipped**.
  Gaps become `context.assumptions_recorded[].confirmed = false`.
- User checkpoints in Phase 2 are **suppressed**. Session runs
  end-to-end.
- Cost abort at 100% still fires; session exits non-zero with state
  saved.
- `subagentStatusLine` renders nothing (host does not render it
  headless).
- Scheduled rechallenges run via `/loop` use the same headless semantics.

## 2. `--bare` mode for CI validation

`--bare` skips hooks, skills, plugins, MCP, CLAUDE.md. TAB itself cannot
run in `--bare` (it IS a plugin), but you can validate pre-existing
synthesis files:

```bash
claude -p --bare \
    "Validate ./TAB/sessions/*/synthesis.json against schemas/synthesis.schema.json, exit non-zero on failure."
```

Use this as a merge gate: CI asserts that every session directory has a
schema-compliant synthesis before allowing a release.

Alternatively, bypass Claude entirely and run the validators directly:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis-json.sh TAB/sessions/<id>/synthesis.json
${CLAUDE_PLUGIN_ROOT}/scripts/validate-claims.sh --session TAB/sessions/<id>
```

This is the fastest CI gate — no API calls, no tokens billed.

## 3. Python Agent SDK

```python
from anthropic_claude_code import ClaudeCode
import json

result = ClaudeCode.run(
    prompt='/tech-advisory-board:tab "GraphQL vs tRPC for internal APIs"',
    output_format="json",
    json_schema_path="schemas/synthesis.schema.json",
    allowed_tools=[
        "Agent", "Read", "Write", "WebSearch",
        "mcp__perplexity__*",
        "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)",
        "Bash(${CLAUDE_PLUGIN_ROOT}/bin/*)",
    ],
    cwd="/path/to/target-project",
)
synthesis = json.loads(result["result"])
print("Recommended stack:", synthesis["recommendation"]["primary"]["stack"])
```

The SDK preserves all TAB artifacts under `cwd/TAB/`. The only knob is
`cwd` — point it at the project you want TAB to analyze.

## 4. TypeScript Agent SDK

```typescript
import { ClaudeCode } from "@anthropic-ai/claude-code";
import fs from "node:fs";

const result = await ClaudeCode.run({
  prompt: '/tech-advisory-board:tab "React vs SolidJS for our editor UI"',
  outputFormat: "json",
  jsonSchemaPath: "schemas/synthesis.schema.json",
  allowedTools: [
    "Agent", "Read", "Write", "WebSearch",
    "mcp__perplexity__*",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/bin/*)",
  ],
  cwd: "/path/to/target-project",
});
const synthesis = JSON.parse(result.result);
console.log("Recommended:", synthesis.recommendation.primary.stack);
```

## 5. CI/CD integration recipes

### 5.1 Merge gate on fresh synthesis

```yaml
# .github/workflows/tab-gate.yml
name: TAB synthesis gate
on:
  pull_request:
    paths:
      - 'TAB/decisions/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate every synthesis under TAB/sessions/
        run: |
          for s in TAB/sessions/*/synthesis.json; do
            bash tech-advisory-board/scripts/validate-synthesis-json.sh "$s"
            bash tech-advisory-board/scripts/validate-claims.sh "$s"
          done
```

No API calls — pure stdlib checks. Costs nothing.

### 5.2 Nightly ADR rechallenge

```yaml
on:
  schedule:
    - cron: "0 6 * * 1"   # every Monday 06:00 UTC

jobs:
  rechallenge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup claude
        # ... install claude CLI + auth ...
      - name: Rechallenge oldest accepted ADR
        run: |
          OLDEST=$(ls -1t TAB/decisions/*.md | tail -1)
          claude -p "/tech-advisory-board:rechallenge $OLDEST" \
              --output-format json \
              --allowedTools "Agent,Read,Write,WebSearch,mcp__perplexity__*"
```

For a fleet of ADRs, iterate and batch. Watch budget — each rechallenge
consumes Standard + T5 budget (~$1-3 USD typical).

## 6. Consumer contract for external tools

Tools that read `synthesis.json` should:

- [ ] Declare a minimum `schema_version` and fail-soft above it
- [ ] Validate with `validate-synthesis-json.sh` before processing
- [ ] Honour `recommendation.primary.confidence` — do NOT auto-apply
      `low-conf` or `unverified` recommendations
- [ ] Surface `unverified_claims[].impact == "high"` as user-visible
      warnings
- [ ] Respect `reversibility: "low"` — prompt for manual confirmation
      before acting
- [ ] Check `auditor_findings[]` for open `critical` items

Full consumer checklist: `skills/tab/references/synthesis-schema.md` §5.

## 7. Environment variables that matter

| Variable | Effect |
|---|---|
| `CLAUDE_CODE_DISABLE_CRON=1` | Scheduled rechallenge refuses to register new tasks |
| `CLAUDE_CODE_REMOTE=true` | Statusline script exits silently (host renders nothing anyway) |
| `CLAUDE_PLUGIN_ROOT` | Points to this plugin's install root — used by all `!``…`` blocks in SKILL.md |
| `CLAUDE_PLUGIN_DATA` | Vanguard timeline and shared research cache live here |
| `CLAUDE_PLUGIN_OPTION_max_cost_per_session_usd` | Personal budget override (userConfig) |
| `CLAUDE_PLUGIN_OPTION_language_preference` | Personal language override (userConfig) |
| `TAB_VANGUARD_WINDOW_DAYS` | Days within which a cached Vanguard assessment is reused (default 90) |
| `TAB_RATE_OPUS_IN` / `TAB_RATE_OPUS_OUT` / etc. | Override `tab-compute-cost` per-Mtok rates |

## 8. When NOT to run headless

- **High-stakes architectural decisions.** Headless skips clarifications;
  gaps become unconfirmed assumptions. For billion-dollar pivots you
  want the interactive version where the Moderator can ask "wait — did
  you mean X or Y?".
- **First TAB session in a project.** `config.json` is absent on run 1;
  the Moderator relies on clarifications to bootstrap preferences.
  Headless run 1 produces a decent synthesis but with wider assumptions.
- **Rechallenge of a decision <30 days old.** The age-warning prompt is
  auto-declined in headless mode — the job will exit cleanly without
  completing.

Rule of thumb: headless is for *re-validation* and *batch audits*, not
for *first-time decisions*.

## 9. Related documents

- `ARCHITECTURE.md` §18 — full specification
- `skills/tab/references/synthesis-schema.md` — consumer contract
- `skills/tab/references/hooks-catalog.md` — hook reference
- `skills/rechallenge/references/rechallenge-protocol.md` — rechallenge in CI
- `scripts/validate-synthesis-json.sh` / `validate-claims.sh` — offline validators
