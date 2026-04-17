# Troubleshooting

## Plugin silently no-ops / skill never triggers

### Shell execution is disabled

Claude Code ≥ v2.1.91 honours `disableSkillShellExecution: true` in
`~/.claude/settings.json`. With that flag set every `!`…`` bash block
inside a SKILL.md is skipped, which breaks TAB:

- `skills/tab/SKILL.md` runs `tab-init-dir`, `load-config.sh`,
  `extract-context.sh`, `tab-check-mcps` via shell blocks.
- `skills/rechallenge/SKILL.md` runs `tab-init-dir`,
  `tab-supersede-adr`, `tab-new-adr` via shell blocks.

Symptoms: the skill starts, prints its header, then stalls or proceeds
with empty `config.json` / `state.json` / context. Persistence hooks may
also appear to succeed but the Moderator has no session state.

Fix: remove the flag or allowlist TAB specifically:

```json
{
  "disableSkillShellExecution": false,
  "skills": {
    "tech-advisory-board:tab": { "shellExecution": true },
    "tech-advisory-board:rechallenge": { "shellExecution": true }
  }
}
```

In a managed environment use `managed-settings.d/` drop-ins (see
`docs/MANAGED_SETTINGS.md`).

## Monitor emits nothing

`scripts/monitor.sh` silently exits when:

- `CLAUDE_CODE_REMOTE=true` (host renders no monitors)
- `python3` is missing from `$PATH`
- `TAB/sessions/` does not yet exist in the working directory

If none of these apply, run the script manually to see its first
`attached` event:

```bash
TAB_MONITOR_POLL_S=1.0 ${CLAUDE_PLUGIN_ROOT}/scripts/monitor.sh
```

## PreCompact hook keeps blocking compaction

The `flush-state.sh` hook refuses compaction during cross-examination
and auditor phases to protect in-context evidence. If compaction stays
blocked after a phase should have ended:

```bash
cat TAB/sessions/<latest>/state.json | jq '.phase_completed, .next_phase'
```

If `phase_completed` is stuck on a cross-exam / auditor marker, the
Moderator did not advance state correctly. Manually bump the phase or
close the session (`tab-resume-session --abort`) so compaction can run.

## Opus 4.7 unavailable

TAB pins Champion and Auditor to `claude-opus-4-7`. On hosts or
plans without Opus 4.7 the model falls back to the latest available Opus
silently — no error surfaced. Check effective model via:

```bash
claude diag --show-models | jq '.resolved'
```

To force sonnet instead, set `CLAUDE_PLUGIN_OPTION_champion_model` and
`CLAUDE_PLUGIN_OPTION_auditor_model` or use `managed-settings.d/`.

## `claude plugin validate` passes but skills fail to load

Most common cause: the skill `description` field exceeds the 250-char
display cap in `/skills`. TAB keeps both skill descriptions
under the cap, but local edits can reintroduce the problem. Check:

```bash
jq -r '.description | length' skills/tab/SKILL.md  # errors — not JSON
awk '/^description:/,/^[^ ]/{if(/^[a-z-]+:/ && !/^description/) exit; print}' skills/tab/SKILL.md
```

or just eyeball the frontmatter.

## Research cache misses after compaction

TAB adds `_meta["anthropic/maxResultSizeChars"]: 500000` to
every MCP research call. If cache hits still drop after compaction:

1. Confirm Claude Code version ≥ v2.1.91 via `claude --version`.
2. Confirm the MCP server honours `_meta` — third-party servers may
   ignore the hint silently.
3. Inspect a call in the transcript and verify the `_meta` field is
   present on the tool input.

## Scheduled rechallenge not firing

Check:

```bash
echo "$CLAUDE_CODE_DISABLE_CRON"   # empty means cron is enabled
claude cron list
```

Cron inheritance is stripped on `EnterWorktree`; if you scheduled the
rechallenge from inside a worktree, re-run `tab-schedule-rechallenge`
from the main repo.
