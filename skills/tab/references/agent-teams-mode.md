---
version: 1.0
last_updated: 2026-04-19
scope: Block 5d — Cross-examination execution mode
audience: TAB Moderator, plugin maintainers
---

# Agent Teams mode

How the cross-examination phase (§7 of `debate-protocol.md`) maps to the
two execution backends supported by the plugin: simulated **subagent
fan-out** (the historical default) and real **Agent Teams** (Claude
Code experimental, ≥ v2.1.32).

The selector is the `agent_team_mode` userConfig knob declared in
`.claude-plugin/plugin.json`. It accepts an enum of three values —
`subagents`, `agent_teams`, `auto` — and only takes effect in modes
**Complete** and **Complete+** (cheaper modes always run subagents).

## 1. Activation gates (all three must hold)

A real Agent Teams cross-exam runs only when **all** of these are true:

| Gate | Source | Default | Notes |
|---|---|---|---|
| **Mode** ∈ `{Complete, Complete+}` | Moderator triage (Phase 0) | n/a | Cheaper modes (`Instant`, `Fast`, `Standard`) always use subagents |
| **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`** | Host env | unset | Required by Claude Code to expose the Agent Teams runtime |
| **`agent_team_mode`** ∈ `{agent_teams, auto}` | userConfig (`CLAUDE_PLUGIN_OPTION_agent_team_mode`) | `subagents` | `auto` = prefer Agent Teams, fall back to subagents silently |

If any gate fails:

- `agent_team_mode=agent_teams` AND env unset → **hard-fail** with
  message `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set"`. The
  Moderator must surface this to the user.
- `agent_team_mode=auto` AND env unset → **silent fallback** to
  subagents. `telemetry.json.execution_path` records
  `subagents_fallback`.
- `agent_team_mode=subagents` → always runs the historical fan-out.

## 2. Behavior matrix (mode × selector)

| Mode | `subagents` | `agent_teams` | `auto` (env on) | `auto` (env off) |
|---|---|---|---|---|
| **Complete** | N champions in parallel as Task subagents; cross-exam mediated in main thread | N champions as a real Agent Team; direct teammate-to-teammate dialogue | same as `agent_teams` | falls back to `subagents`, logs `execution_path=subagents_fallback` |
| **Complete+** | N champions + extended research, same fan-out shape | N champions + Wildcards as a real Agent Team; longer cross-exam window | same as `agent_teams` | same fallback |

Effective cost / fidelity tradeoff (per Anthropic's current Agent Teams
guidance, subject to change):

| Selector | Avg #agents per cross-exam | Token multiplier vs `subagents` | Debate fidelity |
|---|---|---|---|
| `subagents` | 3–4 | 1.0× (baseline) | Mediated by Moderator; turn-taking simulated |
| `agent_teams` | 3–5 | **2–3×** | Genuine direct dialogue; richer disagreement surfaces |
| `auto` (env on) | 3–5 | 2–3× | Same as `agent_teams` when available |
| `auto` (env off) | 3–4 | 1.0× | Same as `subagents` |

When the resolved path is `agent_teams`, the Moderator emits a **single
warning** at session start (before Phase 1):

```
⚠ Running with Agent Teams — estimated $X (2–3× base cost).
  Session ceiling: max_cost_per_session_usd = $Y.
  Adjust the ceiling if you expect to run out mid-session.
```

The warning is informational only. It does not block. Set
`agent_team_mode=subagents` to disable Agent Teams permanently.

## 3. Critical limitation — frontmatter scope

When a subagent runs as a **teammate** inside an Agent Team, the
`skills:` and `mcpServers:` fields declared in its frontmatter are
**ignored**. Teammates inherit skills and MCP servers from
**user/project settings** instead.

Practical consequence: any champion that depends on a specific skill
(e.g. `tab:verification-checklist`) or MCP server must have that
dependency declared in `.claude/settings.json` at user or project
scope. A frontmatter-only declaration silently no-ops in teammate
mode.

This applies to the auditor (which preloads `tab:verification-checklist`
in its frontmatter) and to any champion bound to a vendor-specific MCP
via `mcpServers:`. The Moderator should flag this in the COI section
of the synthesis when the resolved path is `agent_teams`.

## 4. Telemetry

`schemas/telemetry.schema.json.execution_path` records the resolved
backend with one of three values:

- `agent_teams` — gates aligned, real Agent Teams runtime used.
- `subagents_fallback` — `agent_team_mode=auto` requested but
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` was unset; degraded silently.
- `subagents` — default path, no Agent Teams attempted.

The `TeammateIdle` host hook (registered in `hooks/hooks.json` since
v0.1.0) appends entries to `telemetry.json.teammate_idles[]` whenever
a teammate stalls during cross-exam. Use this to debug round-stall
issues.

## 5. Debugging

| Symptom | Likely cause | Fix |
|---|---|---|
| `execution_path=subagents` even with `agent_team_mode=agent_teams` | Mode is not Complete/Complete+ | Bump mode or accept subagents |
| `execution_path=subagents_fallback` | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` unset | `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and restart |
| Hard-fail on session start | `agent_team_mode=agent_teams` AND env unset | Switch to `auto` for graceful fallback, or set the env var |
| Champion produces empty / incomplete output | Required skill or MCP only declared in frontmatter | Move declaration to `.claude/settings.json` (see §3) |
| Unexplained idle gaps in cross-exam | Teammate stalled | Inspect `telemetry.json.teammate_idles[]` |

To force the safe path during debugging, set
`CLAUDE_PLUGIN_OPTION_agent_team_mode=subagents` regardless of env.

## 6. Upstream-change signals to watch

The Agent Teams API is **experimental** in Claude Code. Monitor
[`docs/en/changelog`](https://code.claude.com/docs/en/changelog) for
each release and update the plugin if any of the following change:

| Upstream change | Files to update |
|---|---|
| `TeammateIdle` hook renamed or split | `hooks/hooks.json`, `hooks-catalog.md` §2.N, this doc |
| `TeammateIdle` payload shape changed | `scripts/on-teammate-idle.sh` field names |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var renamed or deprecated | `agent-teams-mode.md` §1, `SKILL.md` Phase 5 gate, `README.md` |
| Minimum Claude Code version raised | `README.md` Compatibility, `CHANGELOG.md` |
| Frontmatter limitation §3 lifted | Remove §3 caveat, simplify auditor/champion docs |
| New `execution_path` value introduced | `schemas/telemetry.schema.json` enum, this doc §4 |

## 7. Sources

- Agent Teams reference: <https://code.claude.com/docs/en/agent-teams>
- Env vars: <https://code.claude.com/docs/en/env-vars>
- Frontmatter limitation (`skills:`/`mcpServers:` not propagated to
  teammates): same Agent Teams page, §Limitations
- Hooks (incl. `TeammateIdle`): <https://code.claude.com/docs/en/hooks>
