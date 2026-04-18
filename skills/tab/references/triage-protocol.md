---
version: 1.0
last_updated: 2026-04-17
scope: Phase 2 (landscape) reinforcement — discard triage, premise check, steel-manning
audience: Lead Moderator, Scout
---

# Triage Protocol

Context extraction and the Landscape Scan jointly produce a shortlist + a
discard table. This protocol tightens both sides: it gives the Moderator
a **reversible discard mechanism**, a **premise-check layer** that
catches bad assumptions before Champions spend Opus tokens on them, and a
**steel-man obligation** that forces the best discarded option to be
re-argued.

Invoked at the end of Phase 2 (Landscape Scan) and before Phase 3 (Champions).
Applies in `Standard`, `Complete`, and `Complete+` modes. `Instant` and `Fast`
run a compressed version (premise check only, via main context).

---

## 1. Discard triage questions (§3.2.1)

The Scout's initial discard table is **provisional**. Before freezing it,
the Moderator surfaces 2-4 **discard triage questions** targeted at the
specific reason each candidate was dropped.

Each question states the candidate, the discard criterion, and asks the
user whether that criterion is genuinely blocking for *their* context:

```
Scout's initial discard:
- SvelteKit — reason: "hiring volume"
- Qwik      — reason: "maturity"
- Astro     — reason: "SPA-limited interactivity"

Moderator (triage):
  Q1: SvelteKit would be cut for hiring volume — is that blocking,
      or would you accept a smaller talent pool?
  Q2: Qwik is pre-1.0 in several areas — can you tolerate a stack
      whose runway is <18 months?
  Q3: Astro is static-first — does your UI need SPA-like interactivity?
```

If the user answers "not blocking" (or "acceptable"), the candidate is
**reinstated** into the shortlist and the Scout records the reversal in
`state-full.json.landscape.discard_reversals[]`.

### Invocation mechanics

- Use the native `AskUserQuestion` elicitation (Claude Code ≥ v2.1.76);
  in headless mode the question resolves via `PreToolUse.updatedInput`.
- Wire the `Elicitation` / `ElicitationResult` hooks (present in the plugin's
  hook catalog) to log every triage round to
  `telemetry.json.discard_triage[]` with before/after counts.
- Budget: **2 questions minimum, 4 maximum**. Quality over volume.
- If the user ignores the question or gives an ambiguous answer, keep the
  discard but annotate with `user_ack: "unclear"` so the Auditor sees it.

### Telemetry fields

```json
{
  "candidate": "SvelteKit",
  "original_reason": "hiring-volume",
  "question_asked": "Is a smaller talent pool blocking?",
  "user_response": "not-blocking",
  "outcome": "reinstated",
  "at": "2026-04-17T14:32:04Z"
}
```

---

## 2. Adversarial premise check (§3.2.2)

Before Champions spawn, a dedicated step questions the **context itself**.
Every agent downstream inherits the Moderator's context envelope — if the
envelope is wrong, the debate amplifies the error instead of correcting it.

Implementation options, in order of preference:

1. **Dedicated premise-checker invocation**: reuse the `auditor` subagent
   with a narrow prompt: *"Read the context envelope below and list 3
   premises most likely to be wrong; rate each high / medium / low risk"*.
   Runs before Phase 3 in `Complete` / `Complete+`.
2. **Main-context premise pass**: in `Standard`, the Moderator performs
   the check inline with a short "what would make this framing wrong?"
   paragraph, recorded in `state-full.json.premise_check`.

Output structure:

```yaml
premise_check:
  risks:
    - premise: "Team is open to Rust"
      risk_level: high
      evidence_for:   ["rustup installed", "past issue #42 mentions Rust"]
      evidence_against: ["current stack is entirely Python", "team size 2"]
      resolution_needed: true
    - premise: "Latency requirement is 100ms p99"
      risk_level: low
      evidence_for: ["spec document, line 14"]
      evidence_against: []
      resolution_needed: false
```

If any `risk_level: high` has `resolution_needed: true`, the Moderator
**halts Phase 3** and asks a clarifying question before spawning Champions.

---

## 3. Steel-man of the best discarded option (§3.2.3)

The discard table tends to carry residual bias (Scout defaulting to
popular choices, over-weighting maturity, etc.). To catch this, exactly
**one** champion is assigned a **steel-man role**: briefly defend the
strongest discarded option (2-3 paragraphs, not a full 4-section brief).

Selection:
- The Scout ranks the discarded list by `steel_man_score` —
  a combination of (a) fit with stated dimensions, (b) discard margin
  (smaller margin = higher score), (c) novelty (not already a shortlist
  incumbent).
- The top-ranked discard becomes the steel-man target.

Execution:
- A champion instance is spawned with `role: steel-man`, identity card
  matching the steel-manned option, and a prompt instructing them to
  deliver the strongest credible case in ≤300 words.
- The Moderator reads the steel-man and decides:
  - **Reinstate** the option to the shortlist (rare — reserved for cases
    where the steel-man exposes a genuinely stronger argument than the
    Scout's discard)
  - **Keep discarded** with annotation `steel_man_reviewed: true` so the
    Auditor and Supervisor can cite it as evidence that the discard was
    tested.

### Ordering

```
Landscape Scan
   |
   v
Discard triage questions  (§1)   → maybe reverses discards
   |
   v
Adversarial premise check (§2)   → may halt for clarification
   |
   v
Steel-man of best discard (§3)   → final chance to reinstate
   |
   v
Champion phase begins
```

---

## 4. Telemetry surface

Every step writes a short record under `telemetry.json.triage[]`:

```json
{
  "step": "discard-triage" | "premise-check" | "steel-man",
  "at": "ISO-8601",
  "outcome_summary": "1 reinstated, 2 confirmed discard",
  "cost_usd_delta": 0.03
}
```

The Auditor (Phase 6.5) reads these records and cites them in the final
review. If triage steps are missing in a mode that requires them, the
`validate-on-stop.sh` gate raises an informational finding (not a
hard-fail — absence is a process smell, not incorrect output).
