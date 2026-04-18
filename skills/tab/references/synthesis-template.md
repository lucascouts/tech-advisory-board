---
version: 4.0
last_updated: 2026-04-08
review_by: 2026-07-07
---

# Final Synthesis Template

The Moderator produces this structured output after all debate phases are complete.
All section headers and content must be translated to the user's detected language
at runtime. The structure below defines the semantic sections — adapt labels to
the user's language.

---

## Instant Mode Template

Use this template for Trivial complexity decisions only.

**[Moderator Name] (Moderator):** I classify this decision as **Trivial** because
[reason]. **Instant** mode.

**[Scout Name] (Landscape Scout):** [Compact shortlist — 2-3 lines, one per alternative]

**Recommendation:** **[Tool]** ([version]) — [justification in 1-2 sentences].
Valid alternative: **[Tool B]** if [specific condition].
Reversibility: [Easy/Medium/Hard] — [1 sentence].

---

## Fast Mode Template

Use this template for Simple complexity decisions only.

### Simplified Matrix (max 5 criteria)

| Criterion | [Option A] | [Option B] | Weight |
|-----------|-----------|-----------|--------|
| [Top 1] | stars | stars | High |
| [Top 2] | ... | ... | ... |
| ... | ... | ... | ... |

### Recommendation
For stage [X]: **[Stack]** because [3 reasons in bullets].

### Evolution
- Next stage: [what changes]
- Full Product: [what changes]

### Reversibility
[Easy/Medium/Hard] — [justification]

---

## Standard / Complete Template

Use this template for Moderate, High, and Very High+ decisions.

---

## 1. Consolidated Advisor Score Matrix

This matrix is built from the **independent advisor subagent results**. Each
advisor scored each champion on their specific dimension. The Moderator
consolidates without modifying individual scores.

### 1a. Raw Independent Scores

| Advisor | Dimension | Champion A | Champion B | Vanguard | Data Verified |
|---------|----------|-----------|-----------|----------|---------------|
| [Name] | [dim] | X/10 | Y/10 | Z/10 | [count] claims checked |
| [Name] | [dim] | X/10 | Y/10 | Z/10 | [count] claims checked |
| ... | ... | ... | ... | ... | ... |
| **Sum** | | **SA** | **SB** | **SV** | |

### 1b. Divergence Analysis

Flag any scores where two advisors differ by >3 points for the same champion:

| Champion | Advisor A (score) | Advisor B (score) | Delta | Resolved? |
|----------|-------------------|-------------------|-------|-----------|
| ... | [Name] (X) | [Name] (Y) | D | Yes/No — [summary of cross-exam] |

If no divergences >3 points exist, state: "No significant divergences detected."

### 1c. Qualitative Comparison Matrix

Synthesized from advisor evaluations. Adapt criteria to the scenario.
**Reversibility** is mandatory.

| Criterion | Champion A | Champion B | Vanguard | Weight |
|-----------|-----------|-----------|----------|--------|
| Performance [POC/MVP/Full] | stars | stars | stars | High |
| DX & Productivity | ... | ... | ... | ... |
| Scalability | ... | ... | ... | ... |
| Security | ... | ... | ... | ... |
| Operational Cost | ... | ... | ... | ... |
| **Reversibility** | ... | ... | ... | ... |

---

## 2. Recommendation & Evolution

### Primary Recommendation (for the declared stage: [POC/MVP/Full])

1. **[Option]** — Score X/N — Justification in 2-3 sentences
2. **[Option]** — Score Y/N — Justification
3. **[Option]** — Score Z/N — Justification

### For stage [X] of your project, I recommend **[Stack]** because:
- [Reason 1]
- [Reason 2]
- [Reason 3]

### How the ranking changes in later stages

- **At [next stage]:** [What changes and why]
- **At Full Product:** [End-state recommendation]

### Evolution Path

| Stage | Recommended Stack | What Changes | Transition Effort | What to Abstract From Day One |
|-------|-------------------|-------------|-------------------|-------------------------------|
| POC | ... | — | — | ... |
| MVP | ... | ... | ... | ... |
| Full | ... | ... | ... | — |

### When to Pivot
- **Trigger 1:** If [specific condition], migrate [component] to [alternative]
- **Trigger 2:** If [condition], re-evaluate [decision]

### Migration Path Between Stages
- From POC to MVP: [What to change, estimated effort]
- From MVP to Full: [What to change, estimated effort]
- **Preventive abstractions:** [What to isolate from the start to ease migration]

### Vanguard Timeline
- **Today:** [Current maturity state]
- **In 6 months:** [Projection]
- **When to consider adoption:** [Specific trigger]

---

## 3. Risk Assessment

Focus on risks that are non-obvious and scenario-specific. Do NOT list generic risks.
Every risk must be concrete, actionable, and tied to this specific decision context.

| Risk | Probability | Impact | Mitigation | Stage | Affected Options |
|------|-------------|--------|------------|-------|-----------------|
| ... | High/Medium/Low | High/Medium/Low | ... | [POC/MVP/Full] | ... |

---

## 4. Data Requiring Independent Verification

If any data was marked with `[not verified]` during the session, list them here:

| Data Point | Expected Source | Impact on Recommendation |
|------------|----------------|------------------------|
| ... | ... | High/Medium/Low |

If no data was flagged, this section can be omitted.

---

## 5. Decision Record (ADR format)

### Context
What the decision was about. If phases were skipped by the user, record here.

### Project Stage
POC / MVP / Full Product

### Alternatives Considered
Complete list (shortlist + discarded with reasons).

### Decision
What was chosen (for the current stage) and why.

### Future Evolution
How the stack evolves as the project matures.

### Consequences
Trade-offs accepted consciously.

### Review Triggers
When to revisit this decision:
- [ ] Upon reaching [X] simultaneous users
- [ ] Upon starting stage [Y]
- [ ] If [tool Z] reaches production maturity
- [ ] At [date/period] for general reassessment

---

## 6. Direct Recommendation

If I were in your position, with this specific context, I would go with **[Stack]**.
[2-3 sentences in plain language, no jargon, explaining why].
The only thing that would concern me is [main risk], and I would mitigate it with
[action] from day 1.

### To Get Started Now

```bash
# Setup commands — copy-paste ready
[command 1]
[command 2]
[command 3]
```

### Reversibility
- **[Stack A]:** [Easy/Medium/Hard] — [justification]
- **[Stack B]:** [Easy/Medium/Hard] — [justification]

---

## 7. Adoption Scaffold

**Purpose:** turn the decision from "choose X" into an operational contract. Do
NOT emit code, do NOT step into implementation — stay at the level of steps,
risks, and checkpoints. Mandatory in `Complete` / `Complete+`; optional
(compressed) in `Standard`; skipped in `Instant` / `Fast`.

### Migration steps (abstract, not code)

1. [Step 1 — e.g. "Validate current routing against chosen framework"]
2. [Step 2 — e.g. "Identify SSR/ISR touchpoints in the current stack"]
3. [Step 3 — e.g. "Roll out canary path: 10% → 50% → 100%"]

### Lock-in risks

- [Vendor / platform assumption — e.g. "Vercel edge middleware"]
- [Architectural assumption — e.g. "React Server Components; reverse costs 3-4 sprints"]

### Operational checklist (post-adoption)

- **D+30:** [Metric to watch — e.g. "TTFB p95 vs baseline"]
- **D+90:** [Metric to watch — e.g. "bundle-size regression"]
- **D+180:** [Automatic rechallenge trigger — schedule via `tab-schedule-rechallenge` or `CronCreate`]

### Integration debt

- [Integration 1 — e.g. "Analytics: requires server-components adaptation"]
- [Integration 2 — e.g. "Auth: NextAuth v5 beta — plan B if it breaks"]

---

## 8. Decision Sensitivity

**Purpose:** answer "what would change the decision?". Mandatory in `Standard+`.

### Threshold analysis

State the context dimensions whose value, if changed, would reorder the ranking:

- If **[dimension X] < [threshold]** → [alternative] takes the lead because [reason].
- If **[dimension Y] > [threshold]** → [alternative] enters the shortlist because [reason].
- If **[dimension Z]** changes direction → [alternative] becomes preferable because [reason].

Concrete example template:

```
- If team_size < 2        → SvelteKit leads (lower conceptual overhead)
- If infra_budget < $500  → Astro becomes viable (static-first)
- If timeline > 18 months → Qwik joins shortlist (long-term bet)
- If traffic > 10M req/mo → Remix closes the gap (superior edge p95)
```

### Stability vs fragility

Classify each dimension as stable or fragile:

- **Stable dimensions:** [list — e.g. "learning curve, ecosystem maturity"]
- **Fragile dimensions:** [list — e.g. "deployment cost (small budget shift reorders ranking)"]

The recommendation is **stable when the fragile dimensions stay within a
narrow band**. If any fragile dimension is near its reordering threshold,
annotate the primary recommendation with `fragile: true` so consumers
can react.

---

## Post-Decision Handoff

After the recommendation, suggest relevant skills for next steps based on the
decision domain. Only suggest skills that are actually available in the session.

**Conditional suggestions (include only those that match):**
- Frontend framework decision -> "To implement the UI, you can use `/frontend-design`"
- Claude API / AI integration -> "For API integration details, see `/claude-api`"
- Complex feature requiring planning -> "To break this into tasks, try `/epic`"
- Gentoo packaging needed -> "For ebuild creation, use `/gentoo-dev`"

**Format (in the user's language):**

> **Next steps:** Based on this decision, you might find these useful:
> - `/skill-name` — one-line description of how it helps

Only suggest 1-3 skills maximum. Omit this section entirely if no skills are relevant.

---

## ADR Generation Offer

After presenting the synthesis, offer (in the user's language):

"Would you like to save this decision as an ADR in the project?
-> Path: docs/decisions/NNNN-[title-kebab-case].md
-> Format: MADR (Markdown Architectural Decision Records)"

This is opt-in. Only generate if the user accepts.

---

## Notes on Using This Template

- **Instant and Fast modes use their own compact templates above** — do NOT use the full Standard/Complete template for these modes.
- **Adapt, don't fill mechanically.** If a section isn't relevant, compress or skip it.
- **Quantify where possible.** "Scales better" is weak. "Supports 10K req/s vs 2K req/s on the same hardware" is strong.
- **Be honest about uncertainty.** If the board couldn't reach consensus, say so.
- **The user decides.** End with a clear recommendation but frame it as advice.
- **Translate all headers and content** to the user's detected language at runtime.
