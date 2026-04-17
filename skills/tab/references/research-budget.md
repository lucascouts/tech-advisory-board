---
version: 1.0
last_updated: 2026-04-16
scope: Block 5b — dynamic research budget
audience: TAB Moderator
---

# Research Budget — Dynamic Algorithm

Every TAB session has a **query budget** that controls how much web
research happens. The budget is **static per mode** at session start
and **grows dynamically** when specific triggers fire. Expansions are
logged so consumers can audit cost.

## 1. Base budget per mode

| Mode | Max queries per tool | Max total queries | Retry budget |
|---|---|---|---|
| Express | 2 | 5 | +1 |
| Quick | 3 | 10 | +2 |
| Standard | 3 | 20 | +6 |
| Complete | 5 | 35 | +10 |
| Complete+ | 7 | 50 | +15 |

**Retry budget** is pooled across tools — if one source fails and the
Moderator needs to re-query via a second tool, retries draw from this
pool.

## 2. Expansion triggers

Five conditions can expand the budget. Each is evaluated at specific
phase boundaries (listed per trigger). Expansions stack.

| # | Trigger | When evaluated | Delta |
|---|---|---|---|
| T1 | Critical dimension mentioned in context but absent from baseline research | End of Phase 1 (baseline research) | +3 |
| T2 | Contradictory claims detected between two sources (tiebreaker needed) | During any research phase, on claim conflict | +2 |
| T3 | Unverified-claim ratio exceeds 30% at end of any phase | End of every phase | +2 |
| T4 | Auditor flags factual gap | End of Phase 6.5 (auditor) | +5 |
| T5 | User invokes Rechallenge and delta-research needs deep check | Phase 0 of Rechallenge session | +10 |

### 2.1 T1 — Critical dimension gap

A "critical dimension" is any requirement the user explicitly mentioned
that would have steered the shortlist if weighted properly — e.g.
"HIPAA compliance", "Windows-only", "GPU-required", "ARM64-native".

Detection: after baseline research, compare the user's stated
requirements against the research dimensions covered. If a requirement
has no matching research angle, T1 fires.

Action: Moderator expands budget by +3 and **re-enters Phase 1** with a
directed researcher subagent scoped to the missing dimension.

### 2.2 T2 — Contradictory claims

Detection: two sources (perplexity, context7, brave) return quantitative
claims that differ by more than one order of magnitude, OR two sources
agree on a fact one says is current and the other says is deprecated.

Action: budget +2 for a third-source tiebreaker. The Moderator records
the conflict in `state-full.json.claims_registry[].contested_by`.

### 2.3 T3 — High unverified ratio

Detection: `unverified / total_claims_this_phase > 0.30`.

Action: budget +2 for next phase. Does NOT retroactively re-query the
current phase's unverified claims — it funds deeper verification of
those same claims downstream (e.g. during cross-exam or advisor
evaluation).

### 2.4 T4 — Auditor factual gap

Detection: auditor returns a `factual-accuracy` finding with
severity ≥ moderate.

Action: budget +5 for a verification pass. The Moderator launches a
researcher subagent scoped to the flagged claim, updates
`claims_registry`, and re-runs Phase 6.5 (auditor) with the verification
result attached.

### 2.5 T5 — Rechallenge delta check

Only fires in Rechallenge mode. When the delta-research phase identifies
>5 material changes since the prior ADR, budget +10 to fund a deeper
re-evaluation.

## 3. Absolute ceiling

```
max_budget = base_budget * 1.5
```

Regardless of how many triggers fire, total queries cannot exceed 150%
of the mode's base budget. If triggers would push above the ceiling, the
Moderator:

1. Prioritizes `critical` auditor findings (T4) first
2. Then T1 (critical dimension)
3. Then T2 (contradictions)
4. Then T3 (unverified ratio)
5. Drops T5 (Rechallenge delta) last — the Moderator flags the drop in
   synthesis and suggests the user start a fresh session instead

## 4. Logging

Every expansion is appended to `telemetry.json.budget_adjustments[]`:

```json
{
  "phase": "champion-debate",
  "reason": "T2",
  "reason_label": "contradictory-claims",
  "delta": 2,
  "new_total": 32,
  "ceiling": 52,
  "at": "2026-04-16T14:34:02Z"
}
```

`validate-synthesis-json.sh` does not enforce budget adjustments —
this is telemetry, not a hard-fail. However, `scripts/validate-claims.sh`
warns when `unverified_ratio > 0.30` and no T3 expansion was logged, which
usually means the Moderator missed the trigger.

## 5. Moderator decision flow

At every phase boundary:

```
1. Compute unverified_ratio for this phase
2. If > 0.30 → fire T3, log expansion, update budget
3. Before starting next phase:
     if budget_consumed >= budget_total - retry_budget:
         pause, warn, require user ack before continuing
4. At end of phase 6.5 (auditor only):
     for each finding of severity ≥ moderate:
         if dimension == "factual-accuracy" → fire T4
5. At end of phase 1 (baseline research only):
     for each user-stated requirement:
         if no research dimension matched → fire T1
```

## 6. Configuration knobs

From `TAB/config.json`:

```json
{
  "budget": {
    "max_cost_per_session_usd": 5.00,
    "warn_at_usd": 3.00,
    "max_duration_s": 900
  }
}
```

The query budget itself is mode-derived and not configurable — changing
the mode is the knob. Cost and duration budgets are independent and
enforced alongside the query budget via `tab-compute-cost`.

## 7. Interaction with `research-cache.json`

Cache hits do NOT consume budget. Specifically:

- A fresh cache hit (<30 days, §7.3) returns silently and does not
  increment the query counter
- A stale cache hit (30-180 days) is surfaced with `[cached, X days]`
  but also does not consume budget — the Moderator may elect to re-query
  fresh, which DOES consume budget
- Cross-project shared cache (`${CLAUDE_PLUGIN_DATA}/shared-cache`) also
  counts as cache, not a new query

This means well-cached sessions may complete under budget while still
producing high-confidence claims.

## 8. Related documents

- `references/persistence-protocol.md` — telemetry lifecycle
- `references/confidence-tags.md` — unverified-ratio definitions
- `references/adversarial-triggers.md` — auditor finding semantics

## 9. MCP result persistence (`_meta`)

Every MCP research call issued by a subagent (`perplexity_search`,
`perplexity_research`, `perplexity_reason`, `context7 query-docs`,
`brave_web_search`) must carry:

```json
{
  "_meta": { "anthropic/maxResultSizeChars": 500000 }
}
```

This is a Claude Code ≥ v2.1.91 feature. When the server honours the hint,
the full response body (up to 500 000 chars) is persisted in the session
transcript and **survives context compaction**. Downstream agents — Champion,
Auditor, Supervisor — can cite the original result verbatim in
`evidence[].source` without re-issuing a paid query.

### Effect on budget accounting

- The first call still consumes 1 query from the budget.
- Subsequent **reads** of the same cached response (via transcript recall)
  do **not** consume budget — they behave like a cache hit under §7.
- If the agent explicitly re-queries to refresh the data, that is a new
  consumption.

### Fallback behaviour

- Servers that ignore `_meta` truncate normally — plugin does not fail.
- Add the `_meta` field unconditionally; it is a no-op when unsupported.

### Audit

`scripts/validate-claims.sh` does not enforce the `_meta` hint (the
transcript cannot be inspected from a shell hook). Absence of `_meta` is a
*performance* regression, not a correctness violation.
