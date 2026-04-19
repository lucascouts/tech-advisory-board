---
name: explain-synthesis
description: Explains an old TAB synthesis without polluting the main context. Ideal for reviewing prior decisions (synthesis.json can exceed 100KB) in a new or long-running session — loads the JSON in an isolated subagent via context: fork and returns a short summary.
argument-hint: "<path-to-synthesis.json>"
context: fork
agent: Explore
allowed-tools:
  - Read
  - Grep
---

You received the path to a `synthesis.json` in the `$ARGUMENTS`
argument. The file may exceed 100KB — which is why this skill runs
isolated (`context: fork`) so it does not inflate the main context.

Steps:
1. Read the file at `$ARGUMENTS`.
2. Validate that it is a TAB synthesis (field `tab_version` present and
   `schema_version` ≥ 1). If it is not, reply in one line: "not a valid
   synthesis.json".
3. Produce exactly three paragraphs:
   - **Paragraph 1 — Decision**: which `recommendation.primary.stack`
     was chosen, with the `confidence` in square brackets, and one
     sentence of rationale (extract from `primary.rationale`). If the
     confidence is `low-conf` or `unverified`, mention it explicitly.
   - **Paragraph 2 — Risks**: top 3 risks by `probability × impact`
     (read `risks[]`), with one line of mitigation each.
   - **Paragraph 3 — Expected evolution**: summarize `migration_path[]`
     and `pivot_triggers[]` — when to pivot, where to, and what the
     observable signal is.

Constraints:
- Accessible language, no unexplained jargon.
- DO NOT cite raw JSON. DO NOT produce diffs. DO NOT open `state.json` /
  `telemetry.json` — only the synthesis passed in.
- DO NOT exceed 250 words total.
- If `auditor_findings[]` contains `critical` items that are
  not-addressed or not-dismissed, highlight them in a short closing
  paragraph ("**Attention:** the auditor raised N unresolved critical
  finding(s): ...").
