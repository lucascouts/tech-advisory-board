# `synthesis.json` consumer contract

Every TAB session emits two artifacts when it closes:

- **`synthesis.json`** — canonical, structured, machine-consumable. This file
  is the source of truth for every downstream tool (CI gates, dashboards, ADR
  generators, analytics).
- **`report.md`** — human-readable rendering. Never parse this in automation;
  regenerate it from `synthesis.json` if you need a fresh render.

This document is the **single reference for consumers**: anyone writing a
GitHub Action, a dashboard, a notification bridge, a policy check, or any
other tool that reads a synthesis file.

## Authoritative schema

The binding spec is `schemas/synthesis.schema.json` (JSON Schema Draft
2020-12). Validate every file you receive against it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-synthesis-json.sh path/to/synthesis.json
```

Exit 0 means the file satisfies both the schema and the hard-fail assertions
(see *Hard-fail rules* below). Non-zero means the file should not be
consumed.

Related files (producer-side, not for consumers):

- `skills/tab/references/synthesis-schema.md` — prose walkthrough of every
  field for the Moderator. Redundant with the JSON schema; kept as
  authoring aid.
- `skills/tab/references/synthesis-template.md` — template the Moderator
  fills in. Not a contract.

## Versioning

`schema_version` is `1` today and will increment as a **major** bump when
breaking changes land. Minor additions (new optional fields, new enum
members that consumers can ignore) do not bump `schema_version`. The plan
is to keep v1 stable; any v2 will ship alongside v1 for at least one minor
release of the plugin with `schema_version` upgraded on a per-session basis.

Consumers should:

1. Check `schema_version` first.
2. Fail **soft** on unknown versions (warn, skip, do not crash).
3. Treat unknown top-level or nested keys as forward-compatible extras.

## Required top-level fields

The schema marks these as `required`:

| Field | Type | Meaning |
|---|---|---|
| `tab_version` | string | Plugin version that produced the file. Informational. |
| `schema_version` | integer (=1) | Contract version. |
| `session` | object | Identifying metadata (id, question, language, mode, complexity, timestamps). |
| `context` | object | Project-level inputs that drove the deliberation (stage, constraints, detected stack). |
| `landscape` | object | The shortlist of considered alternatives and the discarded set. |
| `recommendation` | object | The primary stack + alternatives + reversibility + pivot triggers. |
| `risks` | array | Non-empty in Standard+ sessions; records identified risks with probability and impact. |

Optional top-level fields that consumers should handle when present:

- `champions` — champion presentations (Strengths / Weaknesses / Stage Vision).
- `cross_examination` — attack/defense/concession records between champions.
- `advisors` — per-dimension score matrices.
- `auditor_findings` — adversarial audit output. **Required in `Complete`,
  `Complete+`, `Rechallenge` modes.**
- `supervisor_dissent` — §12.1 gate output when consensus-theater triggered.
- `conflicts_of_interest` — COI disclosures from agents with `memory: project`.
  **Required in `Complete`, `Complete+`, `Rechallenge` modes.**
- `migration_path` — stage-to-stage migration steps.
- `adr_path` — path to the generated MADR ADR (populated in Standard+).

## Hard-fail rules (beyond schema)

`validate-synthesis-json.sh` enforces these in addition to JSON Schema:

1. `recommendation.primary` is present and carries a `confidence` tag.
2. `risks[]` is non-empty for every mode above `Instant`.
3. `auditor_findings[]` is non-empty in `Complete` / `Complete+` /
   `Rechallenge`.
4. `conflicts_of_interest[]` is present (may be empty) in
   `Complete` / `Complete+` / `Rechallenge`.
5. Every claim in `champions[*].weaknesses[]` carries a `mitigation`.
6. Vanguard champions (archetype == `vanguard`) carry a full
   `readiness_assessment` block.
7. `recommendation.reversibility` is one of `low` / `medium` / `high`.
8. Every `landscape.shortlist[]` item has a `confidence` tag.
9. If a claim asserts `high-conf`, it carries at least 2 sources (cross-
   referenced against the claims registry in `state-full.json` when that
   file is available to the validator).

## Confidence tags

Every quantitative or factual claim in the synthesis is tagged:

| Tag | Meaning |
|---|---|
| `high-conf` | Two or more independent sources. |
| `med-conf` | One source, cross-referenced against context7 or similar. |
| `low-conf` | Weak source or interpolation; use with care. |
| `unverified` | Claimed but not validated within session budget. Consumer should not drive automation off these without manual review. |

See `skills/tab/references/confidence-tags.md` for the full taxonomy and
the rule that "when two subagents disagree on confidence for the same
claim, record the LOWER".

## Minimal valid example

```json
{
  "tab_version": "0.1.0",
  "schema_version": 1,
  "session": {
    "id": "2026-04-19-sample",
    "question": "Which ORM should I use with Postgres for an MVP?",
    "language": "en",
    "started_at": "2026-04-19T10:00:00Z",
    "completed_at": "2026-04-19T10:12:00Z",
    "mode": "Fast",
    "complexity": "Simple"
  },
  "context": {
    "stage": "MVP",
    "constraints": ["TypeScript-first", "5-engineer team"]
  },
  "landscape": {
    "shortlist": [
      {"name": "Drizzle", "version": "0.30", "confidence": "high-conf", "stage_fit": "MVP"},
      {"name": "Prisma",  "version": "5.14", "confidence": "high-conf", "stage_fit": "MVP"}
    ]
  },
  "recommendation": {
    "primary": {
      "stack": "Drizzle",
      "rationale": "Leaner runtime, SQL-first API fits the team's Postgres expertise.",
      "confidence": "high-conf"
    },
    "alternatives": [
      {"stack": "Prisma", "when_to_prefer": "If the team pivots to GraphQL-first tooling."}
    ],
    "reversibility": "high"
  },
  "risks": [
    {"description": "Schema migration tooling is less mature than Prisma Migrate.",
     "probability": "medium", "impact": "low"}
  ]
}
```

## Full example with Auditor findings

```json
{
  "tab_version": "0.1.0",
  "schema_version": 1,
  "session": {
    "id": "2026-04-19-multitenant",
    "question": "Stack for a multi-tenant marketing-agency SaaS.",
    "language": "en",
    "started_at": "2026-04-19T09:00:00Z",
    "completed_at": "2026-04-19T10:30:00Z",
    "mode": "Complete",
    "complexity": "High"
  },
  "context": {
    "stage": "MVP",
    "team_size": 8,
    "team_expertise": ["TypeScript", "React", "AWS"],
    "constraints": ["EU data residency", "Sub-$1k/mo infra budget"],
    "assumptions_recorded": [
      {"text": "Multi-tenancy via row-level security (RLS)", "confirmed": true}
    ]
  },
  "landscape": {
    "shortlist": [
      {"name": "Next.js + Postgres (RLS)", "confidence": "high-conf", "stage_fit": "Full"},
      {"name": "Rails + Postgres (RLS)",   "confidence": "med-conf",  "stage_fit": "Full"}
    ],
    "discarded": [
      {"name": "Django",   "reason": "Team has no Python expertise"},
      {"name": "MongoDB",  "reason": "RLS is the multi-tenancy strategy; relational fit is primary"}
    ]
  },
  "champions": [
    {
      "stack": "Next.js + Postgres",
      "archetype": "full-stack",
      "strengths": [
        "Unified TS across frontend and API",
        "First-party Postgres RLS support via Drizzle and Kysely"
      ],
      "weaknesses": [
        {"weakness": "Server actions API is still maturing",
         "mitigation": "Pin to stable Next.js 15.x; re-evaluate on v16 release"}
      ]
    }
  ],
  "advisors": [
    {
      "dimension": "cost",
      "scores": {"Next.js + Postgres": 8, "Rails + Postgres": 7},
      "verdict": "Next.js edges ahead on managed Postgres (Neon/Supabase free tiers)."
    }
  ],
  "auditor_findings": [
    {
      "severity": "moderate",
      "dimension": "feasibility",
      "finding": "RLS policies require every query to pass tenant_id; missing middleware is a footgun.",
      "addressed_in_section": "risks"
    }
  ],
  "conflicts_of_interest": [
    {
      "agent": "researcher",
      "prior_stacks": ["Next.js researched in session 2026-03-10"],
      "mitigation_applied": "identity rotated to Researcher-Beta"
    }
  ],
  "recommendation": {
    "primary": {
      "stack": "Next.js + Postgres (Drizzle + RLS)",
      "rationale": "Best TypeScript fit, leanest infra cost, mature RLS ecosystem.",
      "confidence": "high-conf"
    },
    "alternatives": [
      {"stack": "Rails + Postgres",
       "when_to_prefer": "If team scales beyond 20 engineers; Rails conventions reduce coordination cost."}
    ],
    "reversibility": "medium",
    "pivot_triggers": [
      {"condition": "Tenant count exceeds 1,000",
       "action": "Re-evaluate tenant-per-schema vs RLS"}
    ]
  },
  "risks": [
    {"description": "Forgetting tenant_id filter in ad-hoc queries leaks data",
     "probability": "medium", "impact": "high"},
    {"description": "Next.js 16 may break server-actions usage",
     "probability": "low", "impact": "medium"}
  ],
  "migration_path": [
    {"from_stage": "MVP", "to_stage": "Full",
     "effort_days": 30,
     "changes": ["Add per-tenant observability dashboards",
                 "Swap Neon free tier for dedicated instance"]}
  ],
  "adr_path": ".tab/decisions/0001-stack-for-multi-tenant-saas.md"
}
```

## Using the contract in CI

```yaml
- name: Run TAB
  run: |
    claude --bare -p "$QUESTION" --output-format json \
      --json-schema "$(cat ${CLAUDE_PLUGIN_ROOT}/schemas/synthesis.schema.json)"

- name: Fail on supersede verdict
  run: |
    jq -e '.recommendation.primary.confidence == "high-conf"' synthesis.json
    jq -e '.auditor_findings // [] | map(select(.severity == "critical")) | length == 0' synthesis.json
```

The `--json-schema` flag (`/en/headless#get-structured-output`) validates
the model response against the schema at stream time, giving CI a fast
failure signal before the session even closes. See
`examples/ci-github-actions.yml` for a complete workflow.

## When the contract breaks

If `validate-synthesis-json.sh` fails at session close, the Stop gate
(`scripts/validate-on-stop.sh`) emits `{"decision":"block", "reason":...}`
and the session is not allowed to terminate. The Moderator must re-emit
the synthesis with the violation fixed. This makes contract violations
runtime errors rather than silent downstream failures in consumers.

## See also

- Schema file: `schemas/synthesis.schema.json`
- Producer-side walkthrough: `skills/tab/references/synthesis-schema.md`
- Moderator template: `skills/tab/references/synthesis-template.md`
- Validator: `scripts/validate-synthesis-json.sh`
- Claims-quality validator: `scripts/validate-claims.sh`
- Stop gate: `scripts/validate-on-stop.sh`
- ADR generator (downstream consumer): `bin/new-adr`
