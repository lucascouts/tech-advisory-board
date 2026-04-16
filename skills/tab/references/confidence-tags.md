---
version: 1.0
last_updated: 2026-04-16
scope: Block 5a — data-driven claims (ARCHITECTURE.md §11)
audience: TAB Moderator + Champions + Advisors + Auditor
---

# Confidence Tags

Every quantitative or factual claim in a TAB session carries a confidence
tag. This is not decoration — downstream consumers of `synthesis.json`
(task generators, dashboards, CI gates) gate actions on these tags.
`validate-claims.sh` enforces tag presence on high-stakes claims.

## 1. The four tags

| Tag | Criteria |
|---|---|
| `[high-conf]` | 2+ independent sources, OR a context7 primary source (vendor docs, RFC, paper) |
| `[med-conf]` | 1 source, verified within the last 6 months |
| `[low-conf]` | Model knowledge; external verification attempted and failed, OR not attempted |
| `[unverified]` | Research explicitly skipped or failed; claim stands only on interpretation |

## 2. Rendering conventions

### 2.1 In prose (report.md, champion presentations, advisor evaluations)

The tag appears immediately after the claim, inline, in backticks:

> "Postgres 17 scales to ~10K req/s on a 4-vCPU instance `[high-conf]`,
> though tail latency climbs at 80% CPU utilization `[med-conf]`."

Multiple tags may appear in the same sentence when independent sub-claims
each carry their own confidence.

### 2.2 In `synthesis.json`

Every field that represents a claim carries a `confidence` sibling:

```json
{
  "name": "Postgres",
  "version": "17.0",
  "confidence": "high-conf"
}
```

In `claims_registry[]` (state-full.json), confidence is a required field
per entry; see ARCHITECTURE.md §7.1.

### 2.3 In ADR (`TAB/decisions/NNNN-*.md`)

The ADR inherits tags from `synthesis.json`. The `tab-new-adr` generator
preserves them in the rendered markdown — do not strip.

## 3. When to use which

### `[high-conf]`

Use when **two separate searches or sources independently confirm the
claim** — e.g. perplexity + context7, or two vendor sources. Use when a
context7 primary source (official docs, stable RFC, peer-reviewed paper)
provides the answer directly.

**Do not** use `[high-conf]` for general market perception or blog
consensus, even if 10 blogs say the same thing — blog consensus often
traces to a single upstream claim.

### `[med-conf]`

Use when **one source confirmed within 6 months** and the claim is not
controversial. Typical case: you found the information in a single
vendor doc or recent benchmark report.

### `[low-conf]`

Use when you are stating something from training-data memory AND either
(a) external search failed, (b) external search was not run because the
claim is cosmetic, or (c) the research budget was exhausted. Treat
`[low-conf]` as the ceiling for any claim you personally "just know."

### `[unverified]`

Use when you attempted verification and it failed, OR when the claim is
structurally un-verifiable (e.g. a speculative cost projection for a
hypothetical team at a hypothetical scale). The claim may still be
valuable — it just signals that the reader should weight it accordingly.

## 4. Who tags what

| Role | Tagging responsibility |
|---|---|
| Researcher | Every quantitative claim in the report. Attach `[single source]` if only one source was found, which becomes `[med-conf]` or `[low-conf]` depending on recency. |
| Champion | Every numeric claim (benchmarks, adoption, scale, cost). Also tag claims inherited from researcher output. |
| Advisor | Every score justification that references a metric. Tag uncertain claims during spot-check (`[not verified]` maps to `[unverified]`). |
| Auditor | Explicit tags on every `verified_claims[]` entry — audit output is itself a claim-quality signal. |
| Supervisor | Tags on `evidence[]` entries in dissent output. |
| Moderator | Consolidates tags into `synthesis.json`. When two subagents conflict on confidence for the same claim, use the LOWER confidence (conservative). |

## 5. Hard-fail vs warn in `validate-claims.sh`

| Rule | Severity |
|---|---|
| `landscape.shortlist[].confidence` present for every entry | hard fail |
| `recommendation.primary.confidence` present | hard fail |
| `claims_registry[].verified: true` requires ≥1 `verification_sources` | hard fail |
| `claims_registry[].confidence == "high-conf"` requires ≥2 sources | warn |
| Unverified-claim ratio <30% across registry | warn (triggers budget expansion, §10) |
| Every discarded entry has a `criterion` | warn |

## 6. Legacy "Data Requiring Independent Verification" section

Early TAB versions emitted a consolidated appendix listing unverified
items. This is now **redundant with inline tags** but retained for
human auditability. The Moderator produces both:

- **Inline tags** — machine-readable, consumed by validators and
  downstream tools
- **Appendix in report.md** — list of every `[unverified]` and
  `[low-conf]` claim, collated for quick visual scan

Do not drop the appendix. It is the only place a human reader can scan
for weak-evidence claims without ctrl-f'ing the whole report.

## 7. Example — mapping tags to action

External consumer decision matrix:

| Tag | Auto-apply? | Surface warning? | Gate merge? |
|---|---|---|---|
| `high-conf` | yes | no | no |
| `med-conf` | yes with notice | yes | no |
| `low-conf` | **no** | yes | yes |
| `unverified` | **no** | yes | yes |

Consumers may tighten this matrix but should not loosen it silently.
