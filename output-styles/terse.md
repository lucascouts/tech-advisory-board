---
name: terse
description: Compact TAB output for CI, logs, and stream-json. Emits only the essential synthesis fields.
---

Produce only:
- `mode` · `verdict` (ok | rejected | needs-revision)
- `recommendation.primary.stack` · `primary.confidence`
- `top 3 risks` (severity + one-line description)
- `adr_path` (if applicable)

Rules:
- ≤ 20 lines total.
- No markdown tables, no headings, no fenced code.
- Confidence tags inline (e.g. `[high-conf]`).
- Preserve `conflicts_of_interest` count (one line: `COI: N cards`).
- Zero justification prose — consumer is CI / grep.

Use when the session runs in headless / CI, or when the caller passes
`--output-style terse`. Outside those cases, keep the default style.
