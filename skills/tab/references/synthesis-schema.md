---
version: 1.0
last_updated: 2026-04-16
scope: Block 3 — canonical output
audience: TAB Moderator + external consumers
---

# `synthesis.json` — Consumer Guide

The Moderator emits `synthesis.json` at Phase 7 as the **canonical structured
output** of a TAB session. The human-readable `report.md` is rendered from the
same data. External tools (task generators, dashboards, CI gates, audit
workflows) consume this file directly.

The authoritative schema lives at `schemas/synthesis.schema.json`. This
document explains the *semantics* — what each field means, when it's
populated, and how consumers should interpret it.

---

## 1. Top-level contract

| Field | Required | Notes |
|---|---|---|
| `tab_version` | yes | Plugin version (informational) |
| `schema_version` | yes | Integer. Currently `1`. Consumers must fail-soft on mismatch |
| `session` | yes | Session metadata |
| `context` | yes | Detected + confirmed project context |
| `landscape` | yes | Shortlist + discard table |
| `champions` | Standard+ | Empty in Express mode |
| `cross_examination` | Standard+ | Present only when cross-exam phase ran |
| `scores` | Standard+ | Score matrix + divergence analysis |
| `recommendation` | yes | The decision itself |
| `migration_path` | conditional | Required when `context.stage != "Full"` |
| `risks` | yes | At least one entry |
| `unverified_claims` | yes | May be empty array |
| `auditor_findings` | Complete/Complete+/Rechallenge | Non-empty in those modes |
| `supervisor_dissent` | on-trigger | `null` when no supervisor was invoked |
| `adr_path` | yes | `null` when ADR was skipped (Express/Quick only) |
| `consumable_hints` | no | Optional hints for downstream tools |

### 1.1 Versioning policy

- `schema_version` follows a strict contract. **Minor** additions (new
  optional fields) do not bump it. **Breaking** changes (renamed or removed
  fields) bump the major integer. Migration notes live in ``
  Appendix B.
- Consumers should declare the minimum `schema_version` they accept and emit
  a soft warning (not a hard error) when a newer version is encountered.

---

## 2. Field semantics

### 2.1 `session`

Contains `id` (session directory name), original `question`, ISO-8601
timestamps, detected `language` (BCP 47 tag), and the two classification
axes: `mode` and `complexity`.

- `mode` describes *how the session was run* (`Express` through `Complete+`
  plus `Rechallenge`).
- `complexity` describes *the user's decision difficulty* (`Trivial` through
  `Very High`). The default mapping is documented in ;
  users may override.

### 2.2 `context`

Everything the Moderator learned about the user's project before the debate
started. Think of this as "the world we're deciding inside."

`assumptions_recorded[]` captures gaps — things the Moderator asked about
that the user didn't answer. `confirmed: false` means the assumption was
inferred and remains unverified; consumers should weight the recommendation
accordingly.

### 2.3 `landscape`

`shortlist[]` is the set of options that made it into Champion debate.
`discarded[]` is the set that did not, each with a `reason` and a
`criterion` label (the rule used to exclude it). Consumers building
alternatives pages should merge both into a "considered options" list.

### 2.4 `champions`

One entry per Champion. `archetype` is `Established`, `Vanguard`, or
`Pragmatic` (full catalog in `archetypes.md`).

The Vanguard Champion — if present — includes a `readiness_assessment`
block (`verdict`, `maturity_estimate_months`, `blockers`). Consumers can
use this to flag risky recommendations.

### 2.5 `cross_examination`

Summary of the debate between Champions. `concessions[]` captures where a
Champion yielded; `unresolved_points[]` captures where they did not. These
feed the risk and pivot-trigger reasoning.

### 2.6 `scores`

- `matrix[]` is the raw 2D score grid: `(advisor, champion) → score`. Use
  this for heatmaps.
- `divergences[]` highlights any pair of advisors whose scores for the same
  champion differ by >3 points. `resolved` indicates whether the Moderator
  reconciled the divergence in-session.

### 2.7 `recommendation`

The actual decision. Always:

- `primary.stack` — the string you ship
- `primary.confidence` — how sure TAB is (see §3)
- `primary.rationale` — short prose justifying the choice
- `reversibility` — `low` / `medium` / `high`. Cheapest proxy for "how hard
  is it to undo this later"
- `alternatives[]` — runner-up stacks with `when_to_prefer` conditions;
  useful for "here's what we'd pick instead if X"
- `pivot_triggers[]` — explicit (`condition`, `action`) pairs. Task
  generators should surface these as watchable signals.

### 2.8 `migration_path`

Sequential steps from the current stage to the next (or final) stage.
`effort_days` is a rough estimate — consumers should not treat it as a
bid. `changes[]` is the ordered list of tasks per step.

### 2.9 `risks`

Minimum one entry. `probability × impact` gives you a heatmap. Every
risk ties back to a `stage` (when it becomes relevant) and optionally
to `affected_options[]` (which alternatives share the risk).

### 2.10 `unverified_claims`

Claims the Moderator could not or did not verify. Each is tagged with
`expected_source` (where the data would come from) and `impact` (how
much the decision hinges on it). Treat `impact: "high"` as action items.

### 2.11 `auditor_findings`

Mandatory and non-empty in `Complete`, `Complete+`, `Rechallenge`. Each
finding has a `severity`. For `critical` or `moderate` severities, either
`addressed_in_section` (the synthesis section where the Moderator
incorporated the finding) or `dismissed_reason` (why it was set aside) is
required — never both null.

### 2.12 `supervisor_dissent`

`null` when no consensus-theater trigger fired. Otherwise, a structured
dissent with `identified_bias`, `overlooked_angle`, optional
`proposed_reranking`. Consumers should surface this prominently — it's
the strongest signal that the "obvious" answer may be wrong.

### 2.13 `adr_path` and `consumable_hints`

`adr_path` is a relative path from the project root to the generated MADR
ADR. Null in Express/Quick modes where ADR generation is optional.

`consumable_hints` is freeform — TAB uses `consumable_hints.task_generators`
to point external task-generation plugins at the richest fields. Schema is
intentionally loose so new consumers can read hints without requiring a
TAB update.

---

## 3. Confidence tags

Every major claim carries a confidence tag:

| Tag | Semantic |
|---|---|
| `high-conf` | 2+ independent sources OR context7 primary source |
| `med-conf` | 1 source, verified within 6 months |
| `low-conf` | Model knowledge; unable to verify externally |
| `unverified` | Research explicitly failed or skipped |

Consumers should treat `low-conf` and `unverified` as blockers for
automated action.

---

## 4. Validation

TAB ships a validator at `scripts/validate-synthesis-json.sh`. It runs
the hard-fail assertions from  using Python stdlib
alone. If `jsonschema` is installed, it additionally performs full-schema
validation against `schemas/synthesis.schema.json`.

```bash
scripts/validate-synthesis-json.sh path/to/synthesis.json
# exit 0 = valid, exit 1 = hard-fail, exit 2 = bad invocation
scripts/validate-synthesis-json.sh --schema schemas/synthesis.schema.json path/to/synthesis.json
```

Output is JSON: `{"valid": bool, "errors": [...], "warnings": [...], ...}`.

---

## 5. External consumer checklist

Before shipping any consumer that reads `synthesis.json`:

- [ ] Declare a minimum `schema_version` and fail-soft above it
- [ ] Validate with `validate-synthesis-json.sh` before processing
- [ ] Honour `recommendation.primary.confidence` — don't auto-apply
      `low-conf` or `unverified` recommendations
- [ ] Surface `unverified_claims[].impact == "high"` as user-visible
      warnings
- [ ] Respect `reversibility: "low"` — prompt for manual confirmation
      before acting
- [ ] Check `auditor_findings[]` for open `critical` items
- [ ] Pass `session.language` through so downstream output matches user
      expectations

---

## 6. Related documents

- `schemas/synthesis.schema.json` — authoritative JSON Schema
- `references/synthesis-template.md` — Moderator's output template
- `references/persistence-protocol.md` — when/where synthesis.json is written
