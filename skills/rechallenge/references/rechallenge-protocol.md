---
version: 1.0
last_updated: 2026-04-16
scope: Block 5c — Rechallenge mode
audience: Rechallenge Moderator
---

# Rechallenge Protocol

The canonical reference for the compressed rechallenge flow. Read this
before running any rechallenge session.

## 1. Purpose

A TAB decision (ADR) is correct for the moment it was made, not forever.
Ecosystems shift, CVEs emerge, licenses change, alternatives mature.
Rechallenge answers one question: **given what has changed, is the
original decision still correct?**

It is explicitly NOT a new TAB session. It does not re-open the debate,
re-shortlist, or re-rank the alternatives from scratch.

## 2. Three verdicts

| Verdict | Outcome for the original ADR | Triggering conditions |
|---|---|---|
| `still-valid` | Status unchanged; rechallenge log appended | No material changes AND no critical auditor findings AND advisors all score the original primary ≥7 |
| `needs-revision` | Status stays `accepted`; revision notes appended; migration/risks updated | Some material changes BUT original primary still wins on weighted score |
| `supersede` | Status becomes `superseded-by: NNNN`; new ADR generated | An alternative now outscores the primary OR auditor returns critical OR advisors agree the primary no longer fits |

Ties break conservatively: `still-valid` > `needs-revision` > `supersede`.

## 3. Delta research axes

Four parallel research subagents, one per axis. Each produces a fragment
of `delta-report.json` under the rechallenge session directory.

### 3.1 Primary stack axis

For `recommendation.primary.stack`, check:

- Major version releases since the ADR date
- CVEs published against the current installed version range
- License changes (vendor-side, not project-side)
- Deprecations in the ecosystem (e.g. "X is deprecated in favor of Y")
- Vendor stability events (acquisitions, shutdowns, maintainer churn)

Output per claim: `{"axis": "primary", "finding": "...",
"change_type": "no-change|change-observed|change-material",
"sources": [...], "confidence": "..."}`.

### 3.2 Alternatives axis

For each entry in `recommendation.alternatives`, check:

- Benchmark improvements vs the time of the original decision
- New features that address the `when_to_prefer` condition
- Adoption signals (stars, production case studies, vendor momentum)
- Whether the alternative now satisfies the primary's original strengths

**`change-material` requires BOTH** a measurable improvement in the
alternative AND evidence it now meets/exceeds the primary on at least
one dimension the original session weighted heavily.

### 3.3 Risks axis

For each entry in `risks`, check:

- Has probability changed? (e.g. a risk tied to a vendor's financial
  stability where the vendor was acquired)
- Has impact changed? (e.g. blast radius grew because the system is
  now in production)
- Has the mitigation aged? (e.g. the library providing the mitigation
  was abandoned)

### 3.4 Pivot triggers axis

For each `recommendation.pivot_triggers[].condition`:

- Has the condition materialized *in the wider world* (not
  necessarily in the user's project)?
- If materialized, what did OTHER teams do? Is the planned action
  (`pivot_triggers[].action`) still the right move?

## 4. Auditor invocation (compressed)

The auditor runs BEFORE advisors in rechallenge (opposite order from a
new session). Rationale: the auditor establishes whether facts
changed; advisors then evaluate the dimensional impact of those
changes with the audit already in hand.

Auditor inputs (required):

- The original `synthesis.json`
- The `delta-report.json` produced in Phase 1
- The original ADR's `auditor_findings[]` (if any) — so the new auditor
  doesn't re-flag already-addressed issues

Auditor mandate (spoken to the subagent in the invocation prompt):

> "The decision described in this ADR is N months old. Delta research
> has produced the attached report of changes. Your job is to determine
> whether the original decision still holds *in light of those
> changes*. Flag claims that became wrong, risks that became more
> severe, and alternatives that now dominate. Treat the original
> auditor findings as a closed list — do not re-litigate them unless
> delta shows they're no longer addressed."

## 5. Advisor panel (3 fixed dimensions)

Unlike a new session (which picks 4-6 advisors dynamically), rechallenge
always uses exactly three:

| Dimension | Evaluates |
|---|---|
| Maintenance | Dependency health, supply-chain risk, breaking changes, maintainer bus factor |
| Evolution | Does the decision still fit the user's current stage and the next stage? Has the stage gap widened? |
| Cost | Vendor pricing shifts, infra cost trajectory, team scaling cost |

Each advisor scores THREE options on a 1-10 scale:

- **Keep-primary** — stay on `recommendation.primary.stack`
- **Switch-to-top-alternative** — adopt the highest-scoring alternative
  from the original synthesis
- **No-action** — defer the decision (useful when all options are in
  flux)

Advisors do NOT see each other's outputs (independence contract
preserved). Budget: 400 words each, hard cap 550.

## 6. Verdict computation

Compute weighted score per option:

```
score = sum(advisor.score for advisor in advisors) / len(advisors)
```

Decision tree:

```
1. Compile material_changes = count of delta findings with
   change_type == "change-material"
2. Compile critical_findings = count of auditor findings with
   severity == "critical"
3. Compile advisor_verdicts:
     keep_primary_avg   = mean of keep-primary scores
     switch_avg         = mean of switch-to-top-alternative scores
4. Decide:
     if material_changes == 0 and critical_findings == 0 and
        keep_primary_avg >= 7:
         → still-valid
     elif switch_avg > keep_primary_avg + 1 or critical_findings > 0:
         → supersede
     else:
         → needs-revision
5. Break ties conservatively (→ still-valid over needs-revision over supersede)
```

Document the computation in `rechallenge-verdict.md`.

## 7. ADR supersede mechanics

When the verdict is `supersede`:

1. **Generate a new synthesis** — the rechallenge moderator composes a
   fresh `synthesis.json` under the rechallenge session dir. Key fields:
   - `session.mode = "Rechallenge"`
   - `recommendation.primary.stack = <the winning alternative or new
     stack>`
   - `recommendation.primary.rationale` must cite the original ADR and
     the specific delta findings that justified the switch
   - `context.assumptions_recorded` inherits confirmed assumptions from
     the original synthesis
   - `consumable_hints.supersedes_adr = <path-to-original-ADR>`
2. **Run the ADR generator**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/new-adr <rechallenge-session>/synthesis.json
   ```
   This produces a new ADR `NNNN-<slug>.md` in `.tab/decisions/`.
3. **Link supersession**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/supersede-adr \
       --old <original-ADR-path> --new <new-ADR-path>
   ```
   This:
   - Rewrites the original ADR's status line to
     `superseded-by: NNNN`
   - Appends a "Superseded By" section with a link to the new ADR
   - Regenerates `.tab/index.md` so both rows reflect current status

## 8. `needs-revision` mechanics

When the verdict is `needs-revision`:

1. Do NOT generate a new ADR.
2. Append a `## Revision Notes — YYYY-MM-DD` section to the original
   ADR. Include:
   - Material changes found (bulleted)
   - Updated mitigations (if risks shifted)
   - Updated pivot triggers (if the original conditions aged)
   - A link to the rechallenge session dir
3. Do NOT change the status line — it remains `proposed` or `accepted`.
4. Update `.tab/index.md` by running `supersede-adr` with
   `--mode revision --new <rechallenge-session>/synthesis.json`.

## 9. `still-valid` mechanics

When the verdict is `still-valid`:

1. Append a `## Rechallenge Log` section to the original ADR (create
   the section if it doesn't exist; append a new dated entry if it
   does).
2. Format: `- **YYYY-MM-DD — still-valid.** No material changes;
   auditor returned N informational findings; advisors (Maint, Evo,
   Cost) averaged X.Y on keep-primary. Session:
   <path-to-rechallenge-session>`.
3. Update `.tab/index.md` Status column with a `(reviewed YYYY-MM-DD)`
   suffix — but keep the base status (`accepted`) intact.
4. Write a minimal `synthesis.json` to the rechallenge session dir
   capturing the verdict + links. This synthesis uses
   `session.mode = "Rechallenge"` and `recommendation.primary` is a
   pointer back to the original synthesis.

## 10. Failure modes

| Condition | Behavior |
|---|---|
| ADR path doesn't exist | Stop pre-flight; ask user for the correct path |
| ADR is already superseded | Stop pre-flight; inform user, optionally rechallenge the successor |
| ADR is <30 days old | Warn; proceed only on user confirmation |
| Original `synthesis.json` cannot be located | Degraded mode — offer to synthesize from the ADR body alone (results marked `[low-conf: derived-from-ADR-body]`) |
| Delta research hits MCP degraded mode | Same fallbacks as a new session (WebSearch, with `[unverified]` tags); document the degradation in `state-full.json` |
| Budget ceiling reached before auditor runs | Abort with saved state; offer resume-with-raised-budget |

## 11. Scheduling

Rechallenge can be scheduled per ADR via `schedule-rechallenge`.
The scheduled job invokes this skill non-interactively with
`--allowedTools` pre-declared. In scheduled mode:

- User confirmation prompts (age warning, missing synthesis) are
  auto-declined (= do NOT proceed).
- The session completes only if all pre-flight checks pass cleanly.
- Failure emits a `Notification` hook AND leaves the session in the
  archived state for the user to review. The hook is dispatched by
  `scripts/on-notification.sh`, which routes the failure summary through
  the `channel` MCP server (Telegram / generic webhook). Under
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` the routing is a silent no-op —
  the archived session is still the source of truth (see
  `docs/TROUBLESHOOTING.md`).

### 11.1 Activation path — pick one

Schedule envelope **v3** emits three parallel specs. Choose based on
the intended lifetime of the schedule:

| Activation | When to use | Persistence | Reference |
|---|---|---|---|
| `routines` | Schedules > 7 days (weekly / monthly / quarterly / annual ADR review cadences). Recommended for most ADRs. | Cloud-persistent; survives host restarts and session expiry. | `routines_spec` in `.schedule.json`; `code.claude.com/docs/en/routines` |
| `native` | Short-lived schedules bounded to the current session or the next 7 days (e.g. "re-check this in 3 days"). | Session-bound; host auto-expires after 7 days; re-cron via SessionStart hook on schedules with `active=true`. | `native_cron_spec` in `.schedule.json`; CronCreate tool, Claude Code ≥ v2.1.72 |
| `loop-fallback` | Hosts without Routines AND without CronCreate (e.g. restricted Bedrock/Vertex deployments). | None — requires an active session holding the /loop. | `loop_fallback_prompt` in `.schedule.json` |

After the caller registers the schedule through the chosen path, they
**must** call:

```bash
schedule-rechallenge <adr.md> --record-task <task-or-routine-id> \
  --activation routines|native|loop-fallback
```

This freezes `activation_path` in the `.schedule.json`, so later runs
(and the SessionStart re-cron logic) know which backend to talk to.

### 11.2 Comparison at a glance

- **Routines** — preferred for ADR review cycles because ADRs live
  months or years. A cron that dies after 7 days is the wrong tool for
  "re-check this decision every quarter".
- **native (CronCreate)** — kept for backwards compatibility and for
  cases where cloud-side scheduling is unavailable. Acceptable for
  bounded review windows but requires a SessionStart safety net.
- **loop-fallback** — the lowest-common-denominator. Do not ship this
  to production deployments that need any schedule > session lifetime.

## 12. Related documents

- `skills/rechallenge/SKILL.md` — the skill body itself
- `skills/tab/SKILL.md` — parent TAB skill (shared persistence,
  config, agents)
- `skills/tab/references/persistence-protocol.md` — state/telemetry
  protocol
- `skills/tab/references/adversarial-triggers.md` — auditor mandate
  in rechallenge
- `skills/tab/references/research-budget.md` — T5 expansion trigger
  for rechallenge
