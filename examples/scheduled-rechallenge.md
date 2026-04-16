# Scheduled rechallenge — end-to-end tutorial

Goal: after TAB writes an ADR, schedule automatic rechallenge reviews on a cron cadence so decisions don't rot silently. The `/loop` skill (or `CronCreate`) runs the rechallenge headlessly; failures surface via the Stop-gate.

## Assumptions

- TAB plugin installed and a session has produced `TAB/decisions/0003-database-selection.md`.
- `python3` ≥ 3.9 in PATH.
- Host has either the `/loop` skill available or supports `CronCreate`.

## Step 1 — Prepare the schedule metadata

Run the helper to validate the cron expression, check the ADR is not superseded, and write a companion `schedule.json` alongside the ADR:

```bash
tab-schedule-rechallenge TAB/decisions/0003-database-selection.md \
    --every "0 9 * * 1" \
    --mode quick
```

Canonical cron examples (5 fields only):

| Cadence | Expression |
|---|---|
| Weekly (Mon 09:00) | `0 9 * * 1` |
| Monthly (day 1, 00:00) | `0 0 1 * *` |
| Quarterly | `0 0 1 */3 *` |
| Semi-annual | `0 0 1 1,7 *` |
| Annual | `0 0 1 1 *` |

The script emits an **activation prompt** to stdout — copy it for Step 2.

## Step 2 — Activate via `/loop`

Paste the activation prompt into an active Claude Code session. The `/loop` skill creates the recurring trigger:

```
/loop "0 9 * * 1" /tech-advisory-board:rechallenge TAB/decisions/0003-database-selection.md
```

Alternative: use `CronCreate` directly from an agent SDK script if your host doesn't expose `/loop`.

## Step 3 — Watch the verdicts

Each scheduled run produces a fresh `TAB/sessions/<sid>/` with:

- `delta-report.json` — what changed in the ecosystem since the ADR.
- `synthesis.json` — with `session.mode = "Rechallenge"` and a `verdict` field:
  - `still-valid` — no action.
  - `needs-revision` — primary still wins, but risks or mitigations shifted.
  - `supersede` — an alternative now dominates; `tab-new-adr` writes a new ADR and `tab-supersede-adr` marks the old one.

## Step 4 — Fail loud on supersede

In CI, parse the synthesis verdict and fail the pipeline if a supersede was triggered without human review:

```bash
VERDICT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict"])' \
    TAB/sessions/*/synthesis.json | sort | tail -1)

if [ "$VERDICT" = "supersede" ]; then
    echo "ADR 0003 was superseded automatically. Review required." >&2
    exit 1
fi
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CronCreate is disabled via CLAUDE_CODE_DISABLE_CRON=1` | Host blocks scheduled tasks | Unset the env var or use a different host |
| `bad cron: extended syntax not supported` | Used `L`, `W`, `?`, or `MON/JAN` aliases | Rewrite in 5-field classic syntax |
| Rechallenge runs but ADR is skipped | ADR already has `superseded-by:` status | Rechallenge refuses superseded ADRs by design |
| Stop-gate blocks every run | `synthesis.json` failed hard-fail assertions | Inspect `TAB/sessions/<sid>/synthesis.json` and re-emit |
