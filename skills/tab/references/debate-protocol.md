---
version: 4.0
last_updated: 2026-04-07
review_by: 2026-07-07
---

# Debate Protocol

Phase-by-phase protocol for the Technical Advisory Board deliberation.

---

## Mode-Aware Execution

| Mode | Phases Executed |
|------|----------------|
| **Express** | Research (light) -> Landscape Scan -> Direct Recommendation |
| **Quick** | Research -> Landscape Scan -> 2 Champion Presentations -> 2 Advisor Verdicts -> Synthesis |
| **Standard** | All phases, cross-examination limited to 1 round on biggest divergence |
| **Complete** | All phases, full depth |
| **Complete+** | All phases + extended research + multiple Wildcards possible |

---

## Research Fallback Protocol

When MCP tools or WebSearch fail or return insufficient data:

1. **Retry once** with rephrased query (uses retry budget, not research budget)
2. If still fails, mark claim with: `[not verified — based on model knowledge, may be outdated]`
3. The Moderator maintains a **list of unverified data** throughout the session
4. In the Final Synthesis, include a **"Data Requiring Independent Verification"** section listing all flagged items
5. Never halt the session due to research failure — proceed with transparency

---

## MCP Tool Strategy

### Tool Usage Priority

| Data Needed | Primary Tool | Fallback | Query Pattern |
|---|---|---|---|
| API docs, config, migration | context7 (`resolve-library-id` -> `query-docs`) | `perplexity_ask` | Library name -> resolved ID -> specific query |
| Current versions, health | `perplexity_search` | `brave_web_search` | "[tool] latest version release date" |
| Benchmarks, comparisons | `perplexity_research` (slow, 30s+) | `brave_web_search` | "[A] vs [B] benchmark 2025 2026" |
| CVEs, security | `brave_web_search` | `perplexity_search` | "[tool] CVE security advisory" |
| License changes | `perplexity_ask` | `brave_web_search` | "[tool] license change SSPL BSL" |
| Emerging tools | `perplexity_research` | `brave_web_search` | "[domain] new framework 2026" |

If NO MCP tools are available, use built-in WebSearch.
If WebSearch also fails, apply the **Research Fallback Protocol** above.

### Research Validation Rules

1. **Two-source rule:** Quantitative claims need 2+ sources, or mark `[single source]`
2. **Recency check:** Ecosystem data >6 months old or versions >1 month old get unverified flag
3. **context7 as ground truth:** context7 docs are authoritative for API facts
4. **Orders of magnitude:** Use "50K+ stars" not "52,847 stars" — volatile data should use approximate figures

### Research Query Budget

Queries and retries are tracked separately:

| Mode | Max queries/tool | Max total queries | Retry budget (extra) |
|---|---|---|---|
| Express | 2 | 5 | +1 |
| Quick | 3 | 10 | +2 |
| Standard | 3 | 20 | +6 |
| Complete/Complete+ | 5 | 35 | +10 |

Retries count separately and are used ONLY for re-attempting failed queries.

---

## Interactive Checkpoint

ONE checkpoint — after Landscape Scan (Phase 1):

> "**Checkpoint:** The Scout has presented the landscape. You can:
> 1. **Continue** — proceed with Champions
> 2. **Adjust** — add/remove alternatives from the shortlist
> 3. **Skip to synthesis** — I have enough information
>
> What do you prefer?"

Before synthesis, briefly (in the user's language):
"Any questions before the final synthesis?"

If the user skips phases, the Moderator notes in the synthesis:
"Phases [X] and [Y] were skipped at the user's request. The analysis may be less complete on those dimensions."

---

## Phase 0: Research

After context extraction and stage classification, the Moderator activates research.

**Announce (in the user's language):**
"I will activate the research phase. Specialists will consult up-to-date data before any recommendation."

### Parallel Research Execution (Standard/Complete/Complete+ only)

Launch ONE `researcher` subagent per shortlisted alternative (via `subagent_type: "tech-advisory-board:researcher"`):

1. Each receives: tool name + project context
2. Run all subagents in parallel
3. Consolidate results before proceeding

Research depth by complexity:

| Complexity | Researcher | Queries/alternative | Execution |
|---|---|---|---|
| Trivial | No subagent | 0 | Moderator queries inline |
| Simple | No subagent | 1-2 inline | Main context |
| Moderate | Parallel subagents | 3 | Parallel |
| High | Parallel subagents | 5 | Parallel |
| Very High+ | Parallel subagents, multiple sources | 7+ | Parallel |

---

## Post-Research Clarification (High/Very High+ only)

After researchers return and before the Landscape Scan, the Moderator identifies
gaps revealed by research:

1. Review all research reports for contradictions, gaps, and assumption-dependent data
2. Invoke the native `AskUserQuestion` tool with 2-4 directed questions
   (Claude Code ≥ v2.1.76). The host renders a structured multi-question UI,
   attaches responses to `context.assumptions_recorded[]`, and fires the
   `Elicitation` / `ElicitationResult` hooks for any host-side telemetry.
3. In **batch / headless** mode (`claude -p`) clarifications can instead
   be resolved via `PreToolUse` `updatedInput` — the CI writer answers the
   Moderator's questions from a fixture file without user interaction.

**Tool payload template:**
```json
{
  "tool_name": "AskUserQuestion",
  "input": {
    "questions": [
      {
        "id": "license-change",
        "question": "Tool X changed its license to SSPL on <date>. Is this acceptable for your distribution model?",
        "allow_free_text": true
      },
      {
        "id": "throughput-target",
        "question": "Benchmarks show Y scaling to N req/s, but you mentioned M as target. Does this change performance expectations?",
        "choices": ["Same target", "Relaxed", "Tightened"]
      }
    ]
  }
}
```

**Rules:**
- Maximum 4 questions per round
- If a question goes unanswered (user skips, timeout, headless), store the
  gap as `context.assumptions_recorded[].confirmed = false` and proceed
- Only for High and Very High+ complexity
- Responses live in `state-full.json.clarifications[]` with the question
  id and the verbatim reply for audit

---

## Phase 1: Landscape Scan

**Landscape Scout** presents:

### Shortlist (3-6 alternatives)

| Alternative | Language | Current Version | Stage Fit | Rationale |
|---|---|---|---|---|

Each shortlisted alternative becomes a Champion.

### Discard Table

| Tool | Language | Status | Stage Fit | Reason for Exclusion |
|---|---|---|---|---|

Every tool a developer could reasonably suggest MUST appear in either table.

### Logical Consistency Check

Before finalizing: if criterion X eliminates option A, does it also eliminate
option B that scores equally or worse on X? If yes, either eliminate both or
reclassify as a risk flag.

### Licensing & Legal Flags

Flag any licensing concerns, recent license changes, or compliance implications.

### Checkpoint

After presenting, offer the interactive checkpoint before proceeding.

---

## Phase 2: Champion Presentations

Champions are launched as **parallel `champion` subagents** (Opus, max effort) via `subagent_type: "tech-advisory-board:champion"`.

### Champion Count by Mode

| Complexity | Champions | Own Research | Execution |
|---|---|---|---|
| Trivial | 0 (Moderator recommends) | -- | -- |
| Simple | 2, main context | None (uses baseline) | Sequential |
| Moderate | 3 (2 Established + 1 Vanguard) | 2-3 directed queries | Parallel subagents |
| High | 3-4 (2+ Established + 1+ Vanguard) | 3-5 directed queries | Parallel subagents |
| Very High+ | 4-5 (3+ Established + 1+ Vanguard) | 5-7 in-depth queries | Parallel subagents |

### Invocation Protocol

The Moderator:
1. Reads `references/archetypes.md` to select appropriate archetypes
2. Generates an identity card per champion (random name, credentials, bias)
3. Prepares directed research instructions based on each champion's expertise
4. Launches all champions in parallel via the Agent tool

Each champion receives via prompt:
- Identity card
- Stack to defend
- Baseline research data
- Project context
- Directed research instructions (expertise-specific queries)

### Presentation Structure (4 sections)

1. **Proposal & Toolchain** — complete stack with exact researched versions
2. **Top 3 Strengths** — with researched evidence, project-specific
3. **Top 3 Weaknesses & Mitigations** — honest, with concrete mitigations
4. **Vision by Stage** — POC/MVP/Full with quick-start commands

**Vanguard presents LAST** with additional Readiness Assessment section.

---

## Mid-Session Clarification (High/Very High+ only)

After all champion presentations and before cross-examination:

1. Identify divergent assumptions between champions
2. Present 2-3 confirmation questions to the user

**Format (translate to user's language at runtime):**
```
"Champions raised points that need confirmation:

1. [Champion A] assumes the team has experience with [gRPC]. Can you confirm?
2. [Champion B] proposes [Kubernetes] which requires dedicated infra. Is this
   viable within the $X/month budget?
3. [Champion C] assumes the project will need multi-region in 12 months.
   Is that the actual expectation?

Please respond briefly. Unconfirmed assumptions will be recorded as such
in the synthesis."
```

**Rules:**
- Maximum 3 questions
- Unconfirmed assumptions are recorded as such in synthesis
- Only for High and Very High+ complexity

---

## State Checkpoint (mandatory for High/Very High+)

Before entering cross-examination, save state via TodoWrite:

```
- Phase 0 complete: [N] alternatives researched
- Phase 1 complete: Shortlist = [A, B, C], Discarded = [D, E]
- Phase 2 complete: Champions presented [A, B, C]
  Key claims: [summary of strongest claims per champion]
- Clarification results: [confirmed/corrected assumptions]
```

If context compaction occurs during later phases, re-read the checkpoint
and continue from the last recorded state.

---

## Phase 2.5: Cross-Examination (Champion vs Champion)

Cross-examination is now **champion-to-champion**, not advisor-to-champion.
Advisors evaluate AFTER, with the debate context.

### Cross-Exam Structure

Each champion produces:
1. **Direct attack** — specific technical challenge with researched evidence
2. **Counter-defense** — anticipates and refutes attacks on their stack
3. **Honest concession** — acknowledges genuine superiority, contextualizes

### Depth by Complexity

| Complexity | Cross-Examination | Mechanism |
|---|---|---|
| Trivial | None | -- |
| Simple | None | -- |
| Moderate | 1 round via subagents (Option A) | Parallel, no reply |
| High | Multiple rounds in main context (Option B) | Moderator-mediated |
| Very High+ | Full Option B + extended replies | Extended rounds |

### Option A — Subagents (Moderate)

Launch N `champion` agents in parallel (cross-exam mode) via `subagent_type: "tech-advisory-board:champion"`:
- Each champion receives its own presentation + ALL other champions' presentations
- Instruction: produce Attacks + Defenses + Concessions
- No reply cycle — single pass

### Option B — Main Context (High/Very High+)

The Moderator facilitates debate rounds in main context:

1. Presents the strongest attack from each champion to the target
2. The attacked champion responds
3. If response is insufficient, the Moderator deepens
4. Records concessions and unresolved points
5. Closes when each pair has had at least 1 exchange

The Moderator does NOT resolve divergences — only records them.
Resolution is the responsibility of advisors and the final synthesis.

### Concession monitor (adversarial)

During cross-exam, the Moderator tracks per champion:

```
concession_ratio = concessions_made / attacks_received
```

If any champion's ratio exceeds
`config.adversarial.concession_ratio_threshold` (default `0.6`) in
round 1, the Moderator forces a **round 2** scoped to over-concessions:

> "This concession was too quick. Justify the structural reason this
> isn't decision-relevant, or escalate the concession to a full weakness
> claim with mitigation."

Round 2 outcomes:

| Champion response | Moderator action |
|---|---|
| Defends concession as decision-irrelevant | Log in `cross_examination.unresolved_points[]` |
| Escalates to weakness | Move into `champions[].weaknesses[]`; require mitigation |
| Cannot defend either way | Flag for auditor attention |

Full adversarial-trigger catalog: see `references/adversarial-triggers.md`.

---

## Phase 3: Independent Advisor Evaluation (Parallel Subagents)

Advisors are launched as **parallel `advisor` subagents** (Sonnet, max effort) via `subagent_type: "tech-advisory-board:advisor"`.
Each runs independently with its own tools and context.

### Advisor Input Package

Each advisor receives:
1. Identity Card (from Core roster or dynamically generated)
2. Project context summary (stage, team, constraints, requirements)
3. ALL Champion presentations (complete text)
4. Cross-examination results (attacks, defenses, concessions)
5. Clarification results (confirmed/corrected assumptions)

### Advisor Count by Mode

| Mode | Advisors | Execution |
|------|----------|-----------|
| Express | 0 | -- |
| Quick | 2 | Main context (sequential) |
| Standard | 3-4 | Parallel subagents |
| Complete/Complete+ | 4-6 | Parallel subagents |

### Score Consolidation

After all advisors return, the Moderator consolidates:

1. **Build the score matrix** (raw scores per advisor per champion)
2. **Identify divergences:** scores differing by >3 points for same proposal
3. **Surface verified data:** compile all claim verifications

### Divergence Resolution (Complete/Complete+ only)

If divergences >3 points exist:
1. Present each advisor's challenge to the targeted champion
2. Champion responds in-character
3. Moderator facilitates but does NOT resolve — records for synthesis

---

## Phase 4: Wildcard (Conditional)

Invoked when ANY is true:
- All Champions recommend tools in the same language/ecosystem
- Top-ranked and second-ranked differ by <5 points in advisor score sum
- No Vanguard was assigned
- A user-mentioned technology has no Champion

The Wildcard is a dynamically created persona in main context who challenges
assumptions and proposes unconventional approaches.

---

## Phase 5: User Questions

"Before proceeding to the final synthesis, do you have any questions for the specialists?"

If no questions, proceed to synthesis.

---

## Phase 6: Final Synthesis

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis.sh` mentally
   to ensure all required sections will be present
2. Follow the template in `references/synthesis-template.md`
3. Offer ADR generation (in the user's language): "Would you like to save this decision as an ADR in the project?"
