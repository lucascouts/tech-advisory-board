---
version: 1.0
last_updated: 2026-04-17
scope: Conflict-of-Interest disclosure for subagents carrying project memory
audience: Lead Moderator + agents with `memory: project`
---

# Conflict of Interest (COI) Disclosure

The `researcher` and `auditor` subagents carry `memory: project` in their
frontmatter. Project memory **accumulates** notes across sessions in the
same project — powerful for continuity, but it can create **stack
advocacy loops**: if the researcher was part of a session where
SvelteKit won, residual memory may tilt the next SvelteKit-adjacent
session. LLMs have no economic interest in a technology, but they *do*
have representation drift via accumulation.

This document defines the disclosure surface and the structural
mitigations so drift becomes visible rather than silent.

---

## 1. The COI Card

Every `researcher` / `auditor` instantiation MUST emit a COI disclosure
block at the **top of its first turn**, before any research output. The
block is structured and includes the following fields:

```markdown
## COI Disclosure
- Memory entries loaded: <N>
- Stacks previously defended / audited in this project: [stack (outcome), ...]
- Prior bias signal: <short sentence, e.g. "no prior bias" or "tends to favor Vanguard picks (4/6 sessions)">
- Mitigations applied:
  - Identity card rotated (not same name as prior champion)
  - Memory scoped to `<memory-subdir>/` for this invocation
  - Adversarial role assignment: <yes/no + stack>
```

Missing fields are an Auditor finding (§12.3 trigger). The Moderator does
NOT block on a missing card in Instant / Fast modes (those don't use
project-memory agents anyway), but for Standard / Complete / Complete+ /
Rechallenge the Stop gate (`validate-on-stop.sh`) treats absence as a
moderate finding.

---

## 2. Structural mitigations

### 2.1 Memory partition by convention

The Claude Code spec accepts `memory: user | project | local` only. To
scope memory by **decision domain**, TAB uses subdirectory conventions:

```
.claude/agent-memory/<agent-name>/
├── frontend-framework/
│   └── MEMORY.md
├── database/
│   └── MEMORY.md
├── orchestrator/
│   └── MEMORY.md
└── _fallback/
    └── MEMORY.md
```

Before spawning the agent, the Moderator calls
`scripts/build-agent-memory.sh` to compose an effective `MEMORY.md` from
the relevant domain subdirectory (plus `_fallback/` as a baseline).
Entries scoped to a different domain do not leak.

Domain inference:
- **frontend-framework** — Next.js, Remix, SvelteKit, Astro, Qwik, Vue/Nuxt
- **database** — Postgres, MongoDB, Cassandra, Redis, ClickHouse, DynamoDB
- **orchestrator** — Kubernetes, Nomad, ECS, Fargate, systemd
- **runtime-language** — Node, Deno, Bun, Python, Go, Rust
- *(extend as projects need — see §4 of this file)*

### 2.2 Identity rotation

Champions use random identity names per session. The Moderator ensures
**the same champion name never evaluates the same stack twice in the
same project** (tracked via `state-full.json.identity_history[]` — a
plain list of `{name, stack, session_id, outcome}`).

### 2.3 Adversarial role assignment

If a champion (or the auditor reading their prior defense) previously
defended X in this project, the Moderator forces them into a **contra-
champion** position in the next session where X appears — effectively a
steel-man inverted. Reduces the bias of "always defending the thing I've
defended before".

### 2.4 Bias telemetry

`TAB/vanguard-timeline.json` already tracks Vanguard picks. Extend via
`coi_ledger[]` entries:

```json
{
  "identity_name": "Marina Chen",
  "stack": "SvelteKit",
  "role": "champion",
  "outcome": "won" | "lost" | "pending",
  "session_id": "2026-01-14-frontend-stack",
  "at": "2026-01-14T10:00:00Z"
}
```

Reviewable with `tab-vanguard-timeline coi --by <stack>|<identity>`.

---

## 3. Limits of the COI model

- **LLMs are not economically biased.** The "interest" here is representation
  drift, not corruption.
- **The Card makes drift visible**, it does not remove it. Mitigations
  §2.1–2.4 reduce the rate, but accumulation is structural.
- **Fresh memory ≠ clean slate.** Even the `_fallback/` file inherits
  from prior invocations. Long-lived projects should `tab-cache prune`
  and delete obsolete per-domain MEMORY.md files periodically.

---

## 4. Extending the domain list

The domain list is a shared convention, not a schema. To add a new
domain:

1. Decide the slug (kebab-case, singular, narrow).
2. Create `.claude/agent-memory/<agent>/<slug>/MEMORY.md` if agents
   should carry a scoped memory there.
3. Update `scripts/build-agent-memory.sh` keyword map (at the top of the
   file) so the Moderator routes relevant stacks into the new domain.
4. Document the new slug here.

Missing slug = fallback to `_fallback/`. No failure.
