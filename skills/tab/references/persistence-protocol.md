---
version: 1.0
last_updated: 2026-04-16
scope: Block 2 — persistence layer
---

# Persistence Protocol

This reference is consumed by the TAB Moderator. It defines **when**, **where**,
and **what** to write so that a session can be resumed, audited, and archived
without losing context.

Three state surfaces:

1. **`state.json`** — hot state (§7.1). Written after every phase.
2. **`state-full.json`** — full snapshot (§7.1). Written after every phase
   AND on explicit checkpoint triggers.
3. **`telemetry.json`** — cost and time ledger (§7.2). Updated incrementally
   as phases start/end and subagents return.

Everything lives under `<.tab>/sessions/<session-id>/`. The session
directory is created by `bin/init-dir` on the Moderator's first action.

---

## 1. Session bootstrap (Phase -1)

At invocation, the Moderator runs:

```bash
!`${CLAUDE_PLUGIN_ROOT}/bin/init-dir`
```

Expected output:
```json
{"tab_dir": "/path/to/project/.tab", "created": true|false,
 "archive_threshold_h": 24.0, "archived": ["..."]}
```

Then resume detection:

```bash
!`${CLAUDE_PLUGIN_ROOT}/bin/resume-session --tab-dir /path/to/project/.tab`
```

Decision tree:

- `status: "no-sessions"` → proceed to Phase 0 (context extraction).
- `status: "ok"` with one candidate → ask the user:
  > "An interrupted session from [last_updated] was found — phase
  > `[phase_completed]`, mode `[mode]`. Resume (`r`), start fresh (`f`),
  > or inspect (`i`)?"
- `status: "ok"` with multiple candidates → list them; user picks one or
  chooses fresh.

On resume: read the chosen session's `state.json` + `state-full.json`,
reconstruct the in-memory moderator context, and jump to `next_phase`.

---

## 2. Session id & directory naming

Session id: `YYYY-MM-DD-<slug>` where `slug` is a kebab-case compression
of the first 40 characters of the question. The Moderator computes this
in main context (no script needed).

Directory: `<.tab>/sessions/<session-id>/`

Collision rule: if the directory already exists, append `-2`, `-3`, etc.

---

## 3. Write protocol — per phase

After every phase completes successfully, the Moderator:

1. Writes `state.json` (hot). Idempotent — full overwrite.
2. Writes `state-full.json` (snapshot). Idempotent — full overwrite.
3. Appends a phase entry to `telemetry.json.phases[]` and updates
   `telemetry.json.totals`.

Writes are line-atomic (Write tool, not Edit) so a crashed mid-write
leaves the prior valid state intact.

### 3.1 `state.json` shape — see `schemas/state.schema.json`

Fields to keep fresh on every write:

| Field | Source |
|---|---|
| `last_updated` | ISO-8601 UTC at write time |
| `phase_completed` | name of the phase just finished |
| `next_phase` | name of the upcoming phase |
| `budget_consumed` | cumulative cost snapshot from `compute-cost` |

Do NOT put large arrays in `state.json` — it must stay <10 KB so the
resume-check is fast.

### 3.2 `state-full.json` shape — see `schemas/state-full.schema.json`

Claim registry entries accumulate here. Every quantitative or factual
claim made in a session is appended — champions, advisors, researcher,
auditor, even user-supplied facts. See  for the
per-entry schema.

### 3.3 Language lock (`session_language`, §3.5.3)

During Phase 1 (context extraction), the Moderator detects the user's
language and **LOCKS** it by writing `state-full.json.session_language`
as an IETF BCP 47 tag (`en`, `pt-BR`, etc.). Downstream:

- The `PostCompact` hook (`scripts/rehydrate-state.sh`) reads it and
  re-surfaces it in the digest so compaction can't dilute it.
- The `InstructionsLoaded` hook (`scripts/on-instructions-loaded.sh`,
  matchers `session_start` + `compact`) re-injects it whenever
  instructions reload — covering `/resume`, CLAUDE.md edits, and
  nested-traversal contexts.
- Champions / Advisors / Auditor inherit the value through their
  `initialPrompt` envelope (Claude Code ≥ v2.1.83) or the context digest.

**Never re-detect mid-session.** If the user switches language
(common in pt/en tech chats), the Moderator emits an `AskUserQuestion`
to confirm before changing the locked value; silent drift is prohibited.

---

## 4. Telemetry — write points

`telemetry.json` is created at session start with empty `phases[]`. Then:

- **Phase start**: append a phase object with `started_at` set.
- **Subagent return**: add the subagent to `subagents_invoked` count for
  the current phase; accumulate `tokens_in`/`tokens_out`.
- **Phase end**: set `ended_at`/`duration_s`; run `compute-cost
  --from-telemetry <path>` to refresh `totals`.

### 4.1 Budget warnings

After each phase end, compare `totals.cost_usd` against
`config.budget.warn_at_usd` and `config.budget.max_cost_per_session_usd`:

| Fraction of warn_at | Action |
|---|---|
| <60% | silent |
| 60–89% | soft notice to user, log to `warnings_issued[]` |
| 90–99% | prompt user to continue/pause, log to `warnings_issued[]` |
| ≥100% of max | abort session, save state, offer resume with raised budget |

---

## 5. Research cache

`research-cache.json` is per-session. Key: `sha256(<tool>:<normalized_query>:<date_window>)`.
The `<date_window>` is either `YYYY-MM` (month-granular) or `YYYY-W<NN>`
(week-granular) depending on volatility.

TTL policy:

| Age (days) | Behavior |
|---|---|
| 0–30 | fresh — reuse silently |
| 31–180 | reuse with `[cached, X days]` flag in prose |
| >180 | discard; re-query |

Cross-project shared cache lives at `${CLAUDE_PLUGIN_DATA}/shared-cache/`
and is consulted only when `config.cache.share_across_projects: true`.

---

## 6. Archival

`bin/init-dir` runs archival on every invocation (idempotent):

- Any session with `phase_completed ∈ {cost-report, archival}` is moved
  to `sessions/archived/` regardless of age.
- Any session with `last_updated` older than
  `config.output.session_archive_idle_hours` (default 24) is moved.

Archived sessions remain readable — they just don't appear in resume
candidates.

---

## 7. Failure modes and recovery

| Scenario | Recovery |
|---|---|
| `state.json` exists but `state-full.json` absent | rebuild full from `state.json` + artifacts; log a warning |
| `state.json` unreadable (partial write) | skip this session in resume candidates; Moderator prompts fresh start |
| User ran `/rewind` to a pre-TAB prompt | `state.json` goes stale — Moderator detects mismatch on next turn, offers `resume-session --reconcile` |
| Cost exceeded mid-phase | save state immediately, emit `budget_exceeded: true`, exit cleanly |

The moderator must NEVER leave the session directory in a half-written
state. When in doubt, write `state.json` first (atomic), then
`state-full.json`.

---

## 8. What the Moderator does NOT persist

- Raw subagent prompts (too verbose — log only their names and result summaries)
- Raw MCP responses (summarize to `research-cache.json`; raw bodies are transient)
- Host-level context window bytes (the host manages its own checkpoints via `/rewind`; see §19)

See  for the boundary between TAB's `state.json`
resumption and the host's native `/rewind` rollback.
