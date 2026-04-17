---
version: 1.0
last_updated: 2026-04-16
scope: Block 4 — adversarial layers
audience: TAB Moderator
---

# Adversarial Triggers

Convergence is suspect. TAB runs three layers of challenge so that a
recommendation cannot slip through just because everyone agreed. This
document is the Moderator's decision catalog — when do adversarial
agents fire, and what do they return?

Layers, in order of invocation:

1. **Cross-exam concession monitor** — runs during Phase 4 (cross-exam)
2. **Supervisor** — conditional, runs after Phase 5 (advisor evaluation)
3. **Wildcard** — conditional, main-context persona
4. **Auditor** — mandatory in Complete/Complete+/Rechallenge after Phase 6

---

## 1. Concession monitor (Phase 4)

### When it fires

During cross-examination, the Moderator tallies per-champion:

```
concession_ratio = concessions_made / attacks_received
```

If `concession_ratio > 0.6` in round 1 for any champion, the monitor
fires and forces a second round.

Threshold configurable via `config.adversarial.concession_ratio_threshold`
(default `0.6`).

### What it does

The Moderator issues a round-2 prompt to the over-conceding champion:

> "This concession was too quick. Justify the structural reason this
> isn't decision-relevant, or escalate the concession to a full weakness
> claim."

One of three outcomes:

| Outcome | Action |
|---|---|
| Champion defends the concession was decision-irrelevant | Note in cross_examination.unresolved_points[] |
| Champion escalates to weakness | Move from concessions[] to weaknesses[] in champions[].weaknesses; add mitigation |
| Champion cannot defend either way | Flag for auditor attention (cross_examination.unresolved_points[]) |

### Why this matters

A champion conceding too fast signals either (a) the advocate role was
performed half-heartedly or (b) the stack genuinely has a weakness being
glossed over. Both cases change the recommendation's confidence profile.
Round 2 surfaces which.

---

## 2. Supervisor trigger (Phase 5.5)

### When it fires

After all advisors return, the Moderator checks four conditions. **Any
one** triggers the supervisor:

| Condition | Threshold |
|---|---|
| Fraction of advisors scoring the same proposal ≥8/10 | ≥80% |
| Standard deviation of scores across all proposals | <1.5 |
| No dimension produced a <4 score for any proposal | true |
| No advisor issued a direct challenge | true |

Threshold for condition 1 configurable via
`config.adversarial.supervisor_trigger_threshold` (default `0.8`).

### What it does

Invokes the `supervisor` subagent (`agents/supervisor.md`) with all
advisor outputs + full context. The supervisor is NOT a re-scorer — it
surfaces *structural bias* in the evaluation frame itself.

### How the Moderator incorporates the result

The supervisor returns a structured dissent with fields:
`identified_bias`, `overlooked_angle`, `proposed_reranking`, `evidence`,
`severity`.

- `severity: critical` → Moderator must reopen Phase 6 (consolidation)
  with the dissent as a first-class input. Primary recommendation may
  change.
- `severity: moderate` → Moderator adjusts the recommendation's
  rationale or risks; may shift alternatives ordering.
- `severity: informational` → Moderator appends to synthesis as
  `supervisor_dissent` without changing the recommendation.

The dissent object is always written to `synthesis.json.supervisor_dissent`
even when the supervisor found no structural bias (`identified_bias:
"none — convergence is sound"`).

### Why this matters

Advisors share a frame — the roster the Moderator selected, the
questions they answered, the information they saw. When they converge,
it may be because the answer is right, OR because the frame steered them
there. The supervisor tests which.

---

## 3. Wildcard (existing, refined)

### When it fires

Any of:

- All champions in the same ecosystem (e.g. all Node/TS)
- Top-scored and 2nd-scored differ by <5 points
- No Vanguard champion was assigned
- User mentioned a specific technology that has no champion

### What it does

Main-context persona — NOT a subagent. The Moderator generates a
Wildcard identity card on the fly, drawn from a radically different
paradigm (e.g. a Rust Wildcard into a Node debate; a Dart Wildcard into
a React debate).

The Wildcard:

- Presents a compact (~300 word) alternative proposal
- Explicitly addresses why it was NOT in the shortlist
- Is NOT scored by advisors — it is a frame-breaker, not a contender
- Is captured in synthesis as `champions[].archetype: "Wildcard"` with
  `total_score: null`

---

## 4. Auditor (Phase 6.5, mandatory)

### When it runs

- `Complete` mode: mandatory
- `Complete+` mode: mandatory, with explicit rebuttal round
- `Rechallenge` mode: mandatory

Auditor runs AFTER Phase 6 consolidation and BEFORE Phase 7 synthesis.

### What it does

Invokes the `auditor` subagent (`agents/auditor.md`) with: shortlist +
discards + all champion presentations + cross-exam + all advisor
evaluations + the draft primary recommendation.

Auditor returns `findings[]` across six dimensions (hidden assumptions,
silent risks, feasibility, discard fairness, review triggers, factual
accuracy) plus `verified_claims[]`.

### How the Moderator incorporates findings

Every `critical` and `moderate` finding MUST be addressed in one of:

- Primary recommendation rationale (if it affects the choice)
- `risks[]` (if it becomes a new or amplified risk)
- `migration_path[]` (if it changes the evolution plan)
- `pivot_triggers[]` (if it's a watchable signal)

Dismissal is allowed BUT must include written justification in
`auditor_findings[].dismissed_reason`. A silent dismissal violates the
protocol and fails `validate-synthesis-json.sh`.

### Complete+ rebuttal round

In `Complete+`, each champion whose proposal received a `critical`
auditor finding may submit a 200-word rebuttal. The rebuttal is captured
as `auditor_findings[].champion_rebuttal` and the Moderator's response
as `auditor_findings[].moderator_response`. The finding's `severity` may
be downgraded but never upgraded by this round.

---

## 5. Decision matrix — which layer fires?

| Mode | Concession monitor | Supervisor | Wildcard | Auditor |
|---|---|---|---|---|
| Express | — | — | — | — |
| Quick | — | — | on-trigger | — |
| Standard | on-trigger | on-trigger | on-trigger | on-trigger |
| Complete | on-trigger | on-trigger | on-trigger | **mandatory** |
| Complete+ | on-trigger | on-trigger | on-trigger | **mandatory + rebuttal** |
| Rechallenge | — | on-trigger | — | **mandatory** |

---

## 6. Configuration knobs

From `TAB/config.json`:

```json
{
  "adversarial": {
    "auditor_mandatory_modes": ["Complete", "Complete+", "Rechallenge"],
    "supervisor_trigger_threshold": 0.8,
    "concession_ratio_threshold": 0.6
  }
}
```

Users may tighten or loosen thresholds, but `auditor_mandatory_modes`
should not be narrowed below `["Complete", "Complete+", "Rechallenge"]`
without explicit justification in `config.adversarial.auditor_override_reason`.

---

## 7. Related documents

- `agents/supervisor.md` — supervisor agent definition + output schema
- `agents/auditor.md` — auditor agent definition + output schema
- `references/debate-protocol.md` — §2.2 cross-exam + concession monitor
