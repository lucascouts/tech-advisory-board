---
version: 1.0
last_updated: 2026-04-16
scope: Session flow diagram + complexity classification + per-mode capabilities
audience: Lead Moderator
---

# Session Flow and Modes

Extracted from `SKILL.md` for readability and to keep the skill body under
the ≤500-line recommendation (docs/en/skills §structure). The Moderator
consults this reference right after context extraction.

---

## Complexity Classification

After context extraction, classify the **complexity** of the decision:

| Flag | Example | Mode |
|------|---------|------|
| **Trivial** | "Which formatter should I use with Python?" | Express |
| **Simple** | "Which ORM should I use with Postgres in Node?" | Quick |
| **Moderate** | "Backend framework for a REST API with real-time" | Standard |
| **High** | "Full stack for a multi-tenant SaaS" | Complete |
| **Very High+** | "Monolith to microservices migration with zero downtime" | Complete+ |

The classification is announced in the user's language:
"I classify this decision as **[flag]** because [reason]. I will conduct
the session in **[mode]** mode." The user can override at any point.

If the plugin's `userConfig.default_mode` is set AND the classifier is
ambiguous between two modes, prefer the configured default.

---

## Session Modes

### Express `[Trivial]`
- Scout shortlist (2-3 items) + discard table
- Moderator direct recommendation
- No Champions, no debate, no Advisors, no Auditor, no Supervisor
- Validation: manual review recommended (Express output is too compact
  for reliable `validate-synthesis.sh` pattern matching)

### Quick `[Simple]`
- Scout shortlist + discard table
- 2 Champions (no mandatory Vanguard), condensed presentations
- 2 Advisors, direct comparative verdict
- No cross-examination
- No Auditor, no Supervisor

### Standard `[Moderate]`
- Full flow with 3 Champions (2 Established + 1 Vanguard) + 3-4 Advisors
- Cross-examination: 1 round via subagents (Option A)
- Supervisor gate: fires if §12.1 triggers match
- Auditor: NOT mandatory (configurable via
  `config.adversarial.auditor_mandatory_modes`)
- Full synthesis + auto-ADR

### Complete `[High]`
- Full 8-phase flow without simplifications
- 3-4 Champions (including Vanguard) + 4-5 Advisors
- Clarification rounds (post-research + mid-session)
- Cross-examination: main context, multiple rounds (Option B)
- State checkpointing mandatory after every phase
- Supervisor gate: fires if §12.1 triggers match
- **Auditor mandatory** (Phase 6.5)

### Complete+ `[Very High+]`
- Everything from Complete
- Extended research with multiple sources per alternative
- 4-5 Champions + 5-6 Advisors
- Multiple Wildcards possible
- Supervisor gate active
- **Auditor mandatory** (Phase 6.5)

### Rechallenge `[triggered by /tech-advisory-board:rechallenge]`
- Compressed flow: delta research → auditor → 3 fixed advisors → verdict
- Three verdicts: `still-valid` / `needs-revision` / `supersede`
- **Auditor mandatory**, runs BEFORE advisors (opposite of new session)
- No champions, no shortlist, no discard table
- Budget: Standard + T5 expansion trigger (+10 queries)

---

## Session Flow

```
User presents question
       |
       v
BOOTSTRAP [Phase -1]  (tab-init-dir + load-config + tab-resume-session)
  |-- fresh session dir created or existing resumed
  +-- idle sessions auto-archived
       |
       v
CONTEXT EXTRACTION (flexible — skip what auto-detected context covers)
       |
       v
BASELINE RESEARCH (researcher subagents, parallel)
       |
       v
POST-RESEARCH CLARIFICATION [High/Very High+ only]
       |
       v
LANDSCAPE SCAN + COMPLEXITY CLASSIFICATION + CHECKPOINT
       |
       v
CHAMPION PRESENTATIONS (champion subagents, Opus max, parallel)
  |-- Identity card with real academic credentials + random name
  |-- Directed research by expertise
  |-- 4-section presentation + Vanguard extras
  +-- 1 champion is Vanguard (bleeding-edge, honesty clause)
       |
       v
MID-SESSION CLARIFICATION [High/Very High+ only]
       |
       v
STATE CHECKPOINT (mandatory for High/Very High+)
       |
       v
CROSS-EXAMINATION (champion vs champion)
  |-- Moderate: 1 round via subagents (Option A)
  |-- High/Very High+: main context, multiple rounds (Option B)
  +-- Concession monitor (§12.2) may force round 2
       |
       v
ADVISOR EVALUATION (advisor subagents, Sonnet max, parallel)
  +-- Receives: presentations + cross-exam + clarifications
       |
       v
SUPERVISOR GATE [Phase 5.5]  (conditional)
  +-- If §12.1 consensus-theater triggers fire: supervisor subagent
       |
       v
SCORE CONSOLIDATION + WILDCARD (Moderator, main context)
       |
       v
AUDITOR [Phase 6.5]  (mandatory in Complete/Complete+/Rechallenge)
  +-- auditor subagent reviews near-final synthesis
       |
       v
SYNTHESIS + ADR offer  (auto-generated in Standard+)
  +-- Stop hook auto-runs validate-synthesis-json.sh + validate-claims.sh
```

---

## Phase-to-Mode matrix

| Phase | Express | Quick | Standard | Complete | Complete+ | Rechallenge |
|---|---|---|---|---|---|---|
| Bootstrap (-1) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Context extraction | ✓ | ✓ | ✓ | ✓ | ✓ | skip |
| Baseline research | light | ✓ | ✓ | ✓ | ✓ | delta-scoped |
| Post-research clarification | — | — | — | ✓ | ✓ | — |
| Landscape scan | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| Champion presentations | — | ✓ | ✓ | ✓ | ✓ | — |
| Mid-session clarification | — | — | — | ✓ | ✓ | — |
| Cross-examination | — | — | 1 round | multi | multi | — |
| Advisor evaluation | — | 2 advs | 3-4 advs | 4-5 advs | 5-6 advs | 3 fixed |
| Supervisor gate (5.5) | — | — | cond. | cond. | cond. | — |
| Auditor (6.5) | — | — | cond. | **req** | **req** | **req** |
| Synthesis | direct | full | full | full | full | compressed |
| Auto-ADR | optional | optional | ✓ | ✓ | ✓ | on supersede |

cond. = conditional based on `config.adversarial`.
