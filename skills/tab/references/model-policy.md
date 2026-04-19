---
version: 1.0
last_updated: 2026-04-17
scope: Dynamic model selection — reading config, signals, and overrides
audience: Lead Moderator (consulted before spawning each subagent)
---

# Model Policy

The Moderator consults this reference right before spawning any subagent
when `userConfig.model_policy` is not `static`. It decides which model a
Champion / Advisor / Auditor runs under, based on runtime signals rather
than a fixed frontmatter pin.

Resolution script: `scripts/model-policy.sh` (stdin JSON in, stdout JSON out).

---

## 1. Policies

| Policy | Behavior |
|---|---|
| `static` | Honor only `champion_model`, `advisor_model`, `auditor_model` envs. No dynamic decision. |
| `budget-aware` *(default)* | Start from the env defaults; downgrade Champion / Auditor to Sonnet when **budget_remaining_pct < 30**. |
| `context-aware` | `budget-aware` + the signal table below. |

---

## 2. Signals (`context-aware` only)

| Signal | Threshold | Effect |
|---|---|---|
| `budget_remaining_pct` | `< 30` | Downgrade Champion / Auditor → Sonnet |
| `cache_hit_rate_pct` | `> 70` | Downgrade Advisor (task is more mechanical) |
| `mcp_perplexity_up` | `false` | Upgrade Auditor → Opus (reasoning without corroboration) |
| `novel_topic` | `true` | Upgrade Champion → Opus (no prior vanguard-timeline match) |
| `prompt_cache_warm_pct` | `> 80` | Permit upgrade (incremental cost low) |
| `stakes` | `"Full"` | Upgrade Champion / Auditor |

The script applies signals in the order above; the latest winning signal
determines `source = "signal"` and populates `reason`.

---

## 3. Per-mode overrides

`userConfig.model_policy_overrides` accepts a JSON object shaped like:

```json
{
  "Instant": "haiku",
  "Fast":    "sonnet",
  "Standard": "sonnet",
  "Complete": "claude-opus-4-7",
  "Complete+": "claude-opus-4-7",
  "Rechallenge": "claude-opus-4-7"
}
```

Applied after the signal engine — a matching key wins over any engine
recommendation for Champion, Advisor, Auditor. `researcher` / `supervisor`
ignore per-mode overrides.

---

## 4. Moderator invocation

Before every subagent spawn, the Moderator (or the `inject-tab-context.sh`
helper) pipes a decision envelope into `model-policy.sh`:

```bash
echo '{
  "role": "champion",
  "mode": "Complete",
  "signals": {
    "budget_remaining_pct": 42,
    "cache_hit_rate_pct":   55,
    "mcp_perplexity_up":    true,
    "novel_topic":          false,
    "prompt_cache_warm_pct": 30,
    "stakes":               "MVP"
  }
}' | ${CLAUDE_PLUGIN_ROOT}/scripts/model-policy.sh
```

Response:

```json
{
  "model": "claude-opus-4-7",
  "policy": "context-aware",
  "source": "env",
  "reason": "champion default (context-aware)",
  "role":   "champion",
  "mode":   "Complete"
}
```

The Moderator then injects `model` into the subagent's `initialPrompt`
(Claude Code ≥ v2.1.83) or sets the corresponding `CLAUDE_PLUGIN_OPTION_*_model`
env var for the spawn.

---

## 5. Telemetry

Every resolution is appended to `telemetry.json.model_policy_decisions[]`
(schema-free). Consumers compare `source = "env"` vs `"signal"` vs
`"mode-override"` counts to understand how often dynamic signals kicked in.

Tracking downgrades and upgrades is also useful for calibrating the
signal thresholds per project.
