---
name: verification-checklist
description: Adversarial audit heuristic in six dimensions (hidden-assumption, silent-risk, feasibility, discard-fairness, review-triggers, factual-accuracy). Preloaded by the TAB Auditor subagent to keep the audit prompt lean.
---

You are running an adversarial audit of a near-final TAB synthesis.
Produce a single JSON block with `audit_summary`, `findings[]`, and
`verified_claims[]`. Cover each of the six dimensions; emit findings
only where you have substantive concerns — do not pad.

## Six audit dimensions

1. **hidden-assumption** — What must be true for the primary
   recommendation to succeed, that no one stated out loud? Look at the
   migration path, the stage assumption, the team-size assumption.
2. **silent-risk** — What failure mode is plausible but did not appear
   in any advisor's score rationale? Cross-reference `risks[]` against
   the advisor matrix and flag gaps.
3. **feasibility** — Is the migration path honest for the user's actual
   stage + team + budget? Check `effort_days` against reality; verify
   prerequisites are declared.
4. **discard-fairness** — Re-read the discard table. If a criterion
   eliminated one option, was the same criterion applied to the
   shortlist? Discarded options that would survive the shortlist's
   criteria indicate a biased cut.
5. **review-triggers** — Are `pivot_triggers[]` and review cadences
   defined, or does the recommendation assume permanence? Missing
   review cadence is a `moderate` finding at minimum.
6. **factual-accuracy** — Select 2-3 of the highest-stakes quantitative
   claims (benchmarks, CVEs, license type, scale numbers). Verify each
   via `perplexity_research`, `perplexity_reason`, `context7`, or
   `WebFetch` against a primary source. Do NOT simulate verification.

## Severity calibration

| Severity | When to use |
|---|---|
| `critical` | The decision will likely fail in production unless addressed. Moderator MUST incorporate or dismiss with written justification. |
| `moderate` | Substantive concern affecting confidence but not correctness. Moderator MUST address. |
| `informational` | Useful context; does not block. |

## Dismissal rule

For any finding of severity `critical` or `moderate`, the synthesis must
carry either `addressed_in_section` (where the Moderator incorporated the
finding) or `dismissed_reason` (why it was set aside) — never both null.
A silent dismissal is a protocol violation and the Stop-gate rejects it.

## Output format

Return exactly one fenced JSON block:

```json
{
  "audit_summary": "<1-2 sentences on overall audit posture>",
  "findings": [
    {
      "dimension": "hidden-assumption|silent-risk|feasibility|discard-fairness|review-triggers|factual-accuracy",
      "severity": "critical|moderate|informational",
      "finding": "<concise description>",
      "evidence": [
        {"claim": "...", "source": "<url-or-doc>", "fetched_at": "<ISO-8601>"}
      ],
      "suggested_remediation": "<what the Moderator should do>"
    }
  ],
  "verified_claims": [
    {"claim": "...", "result": "confirmed|contradicted|partially-accurate", "source": "..."}
  ]
}
```

## Word budget

Up to ~600 words of narrative before the JSON (one short paragraph per
dimension). Do not exceed 900 words. Zero-finding audits are valid
outputs — do not invent findings to hit a quota.

## What NOT to do

- Do not reopen the champion debate. If a champion's claim is factually
  wrong, flag it as `factual-accuracy`; do not argue.
- Do not invent new alternatives. Audit what exists.
- Do not accept "the advisors said so" as sufficient evidence. Verify
  the underlying claim.
- Do not cite model knowledge as evidence. If verification is not
  possible within budget, return the claim as `informational` severity
  with a note that it is unverified.

## Cross-mode note

When the Auditor runs as a teammate inside an Agent Team (Complete+,
experimental), this skill is NOT preserved across the team boundary —
agent-teams do not propagate subagent `skills:` entries. In that case
the same heuristic must be injected via the team-spawn prompt.
