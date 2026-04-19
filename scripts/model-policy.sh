#!/usr/bin/env bash
# model-policy.sh — decide which model a subagent should run under.
#
# Inputs (stdin, JSON):
#   {
#     "role": "champion" | "advisor" | "auditor" | "researcher" | "supervisor",
#     "mode": "Instant" | "Fast" | "Standard" | "Complete" | "Complete+" | "Rechallenge",
#     "signals": {
#       "budget_remaining_pct": 0-100,
#       "cache_hit_rate_pct":   0-100,
#       "mcp_perplexity_up":    true|false,
#       "novel_topic":          true|false,
#       "prompt_cache_warm_pct":0-100,
#       "stakes":               "POC" | "MVP" | "Full"
#     }
#   }
#
# Policy selection (CLAUDE_PLUGIN_OPTION_model_policy):
#   static        → honor the *_model env vars only (no dynamic decision)
#   budget-aware  → start from *_model; downgrade Champion/Auditor to sonnet
#                   when budget_remaining_pct < 30
#   context-aware → apply the full signal table from skills/tab/references/model-policy.md
#
# Per-mode overrides (CLAUDE_PLUGIN_OPTION_model_policy_overrides, JSON):
#   { "Instant": "haiku", "Fast": "sonnet", "Complete": "opus" }
#   Applied last; wins over the engine's recommendation when the key matches
#   the incoming mode.
#
# Output (stdout, JSON):
#   { "model": "<model-id>",
#     "policy": "static|budget-aware|context-aware",
#     "source": "env|signal|mode-override",
#     "reason":  "short human-readable" }
#
# Exit 0 on success. Exit 2 on bad input.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 required" >&2
    exit 1
fi

INPUT_FILE="$(mktemp)"
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

exec python3 - "$INPUT_FILE" <<'PYEOF'
import json, os, sys

try:
    with open(sys.argv[1]) as f:
        payload = json.load(f)
except Exception as e:
    print(f'{{"error":"invalid JSON on stdin: {e}"}}', file=sys.stderr)
    sys.exit(2)

role   = payload.get("role")
mode   = payload.get("mode")
signals = payload.get("signals") or {}

if role not in {"champion", "advisor", "auditor", "researcher", "supervisor"}:
    print(f'{{"error":"unknown role: {role}"}}', file=sys.stderr)
    sys.exit(2)

policy = os.environ.get("CLAUDE_PLUGIN_OPTION_model_policy") or "budget-aware"
overrides_raw = os.environ.get("CLAUDE_PLUGIN_OPTION_model_policy_overrides") or ""
try:
    mode_overrides = json.loads(overrides_raw) if overrides_raw.strip() else {}
except json.JSONDecodeError:
    mode_overrides = {}

env_map = {
    "champion":  os.environ.get("CLAUDE_PLUGIN_OPTION_champion_model")  or "claude-opus-4-7",
    "advisor":   os.environ.get("CLAUDE_PLUGIN_OPTION_advisor_model")   or "sonnet",
    "auditor":   os.environ.get("CLAUDE_PLUGIN_OPTION_auditor_model")   or "claude-opus-4-7",
    "researcher": "sonnet",
    "supervisor": "sonnet",
}

model = env_map[role]
source = "env"
reason = f"{role} default ({policy})"

def downgrade_to_sonnet(current):
    if current.startswith("claude-opus") or current == "opus":
        return "sonnet"
    return current

def upgrade_to_opus(current):
    if current == "sonnet" or current.startswith("claude-sonnet"):
        return "claude-opus-4-7"
    return current

if policy == "static":
    pass  # env only

elif policy in ("budget-aware", "context-aware"):
    budget_pct = signals.get("budget_remaining_pct")
    if isinstance(budget_pct, (int, float)) and budget_pct < 30 and role in {"champion", "auditor"}:
        new = downgrade_to_sonnet(model)
        if new != model:
            model, source, reason = new, "signal", f"budget {budget_pct:.0f}% < 30 → downgrade {role}"

if policy == "context-aware":
    cache_rate = signals.get("cache_hit_rate_pct")
    if isinstance(cache_rate, (int, float)) and cache_rate > 70 and role == "advisor":
        new = downgrade_to_sonnet(model)  # advisor default is already sonnet; leave idempotent
        if new != model:
            model, source, reason = new, "signal", f"cache hit {cache_rate:.0f}% > 70 → advisor downgrade"

    if signals.get("mcp_perplexity_up") is False and role == "auditor":
        new = upgrade_to_opus(model)
        if new != model:
            model, source, reason = new, "signal", "perplexity down → upgrade auditor"

    if signals.get("novel_topic") is True and role == "champion":
        new = upgrade_to_opus(model)
        if new != model:
            model, source, reason = new, "signal", "novel topic → upgrade champion"

    warm = signals.get("prompt_cache_warm_pct")
    if isinstance(warm, (int, float)) and warm > 80 and role in {"champion", "auditor"}:
        new = upgrade_to_opus(model)
        if new != model:
            model, source, reason = new, "signal", f"prompt cache warm {warm:.0f}% > 80 → upgrade"

    if signals.get("stakes") == "Full" and role in {"champion", "auditor"}:
        new = upgrade_to_opus(model)
        if new != model:
            model, source, reason = new, "signal", "stakes=Full → upgrade"

# Per-mode overrides applied last, win over engine choice
if mode in mode_overrides and role in {"champion", "advisor", "auditor"}:
    new = mode_overrides[mode]
    if new and new != model:
        model, source, reason = new, "mode-override", f"mode={mode} override → {new}"

print(json.dumps({
    "model":  model,
    "policy": policy,
    "source": source,
    "reason": reason,
    "role":   role,
    "mode":   mode,
}, ensure_ascii=False))
PYEOF
