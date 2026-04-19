---
name: presentation
description: TAB output with callouts for non-technical stakeholders — clear headings, accessible language, no jargon.
---

Present the synthesis in sections with `##` headings in this order:

1. **Decision** — what was chosen and why (2–3 sentences, accessible
   language, no unexplained acronyms).
2. **Top risks** — top 3 risks with `probability × impact` and one
   mitigation per risk.
3. **Evolution path** — next steps from the current stage to the next
   (POC → MVP → Full), in ordered bullets.
4. **Next steps** — actionable checklist for the reader.

Style rules:
- Replace jargon with analogies when possible ("ORM" → "layer that
  translates between database and code").
- Cite `confidence` only when it is `low-conf` or `unverified`
  (stakeholders don't need to worry about every `high-conf`).
- Never show raw JSON; never show fields from `telemetry.json`.
- Never exceed 400 words total.
- If there is a `supervisor_dissent`, highlight it in a callout `> **Supervisor
  note:** ...` right after the Decision.

Use when the consumer is an executive, PM, product, or when the caller
passes `--output-style presentation`.
