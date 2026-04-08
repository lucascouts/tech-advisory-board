---
version: 1.0
last_updated: 2026-04-03
review_by: 2026-07-03
---

# Project Stage Definitions

Classification determines the PRIMARY recommendation, but the analysis ALWAYS covers the full spectrum.

## POC (Proof of Concept)
- **Goal:** Validate the core idea works technically
- **Timeline:** 2-6 weeks
- **Acceptable trade-offs:** Tech debt, hardcoded values, limited scale, single-user
- **Stack guidance:** Fastest to prototype, fewest moving parts

## MVP (Minimum Viable Product)
- **Goal:** First usable product for real users, validates market
- **Timeline:** 1-6 months
- **Acceptable trade-offs:** Limited features, known scaling ceiling, manual operations
- **Stack guidance:** Balance speed with foundation that doesn't require full rewrite

## Full Product
- **Goal:** Production-grade system designed for scale and longevity
- **Timeline:** 6-18 months
- **Acceptable trade-offs:** Longer development time for better architecture
- **Stack guidance:** Optimize for maintainability, scalability, operational maturity

## Critical Rule: Full-Spectrum Analysis

Regardless of declared stage, every champion, advisor, and synthesis MUST address:

1. **What works for the declared stage** — the primary recommendation
2. **What changes at the next stage** — what breaks, what needs replacing
3. **What the Full Product looks like** — end-state architecture
4. **Migration path between stages** — effort, risk, what to abstract from day one

A tool recommended for MVP must include (in the user's language):
"This scales up to X. Beyond that, Y will be needed. To prepare, abstract Z from the start."

A tool NOT recommended for the current stage but right for Full Product still appears with:
"Not recommended now (excessive complexity), but plan the migration when [specific trigger]."
