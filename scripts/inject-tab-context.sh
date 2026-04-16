#!/usr/bin/env bash
# inject-tab-context.sh — UserPromptSubmit hook.
# When the prompt looks like a TAB-triggering decision query AND no TAB
# session is already active, pre-inject extract-context.sh output so the
# first Moderator turn does not burn cycles on discovery.
#
# UserPromptSubmit hooks fire on every prompt (no matcher), so the
# script is responsible for gating itself.
#
# Budget: <400ms. Non-blocking on failure.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat || echo '{}')

SHOULD_INJECT=$(python3 - "$INPUT" <<'PYEOF' 2>/dev/null || echo "no"
import json, re, sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    print("no"); sys.exit(0)

prompt = (payload.get("user_prompt") or payload.get("prompt") or "").lower()

# Only fire when the user explicitly invokes the TAB skill OR uses a
# canonical TAB-triggering phrase. Conservative matching — false
# positives would inject context into every coding conversation.
triggers = [
    r"/tech-advisory-board:",
    r"\btab\b",
    r"which (database|framework|library|stack|orm|runtime)",
    r"(should i use|que devo usar|qual usar)",
    r"compare .+ (vs|versus|or) ",
    r"analise (esse|este) projeto",
]

for pat in triggers:
    if re.search(pat, prompt):
        print("yes"); sys.exit(0)
print("no")
PYEOF
)

if [[ "$SHOULD_INJECT" != "yes" ]]; then
    exit 0
fi

EXTRACT="${CLAUDE_PLUGIN_ROOT:-}/scripts/extract-context.sh"
[[ -x "$EXTRACT" ]] || exit 0

CTX_JSON=$("$EXTRACT" --json 2>/dev/null || echo '{}')

python3 - "$CTX_JSON" <<'PYEOF' 2>/dev/null || exit 0
import json, sys

try:
    ctx = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

if not ctx or ctx.get("error"):
    sys.exit(0)

summary_lines = ["TAB pre-injected project context:"]
if ctx.get("manifests"):
    summary_lines.append(f"  manifests: {', '.join(ctx['manifests'][:5])}")
stack = ctx.get("stack") or {}
if stack:
    if stack.get("name"):
        summary_lines.append(f"  project: {stack['name']}")
    if stack.get("dependencies"):
        summary_lines.append(f"  deps: {', '.join(stack['dependencies'][:8])}")
if ctx.get("git", {}).get("branch"):
    summary_lines.append(f"  branch: {ctx['git']['branch']}")

if len(summary_lines) <= 1:
    sys.exit(0)

print(json.dumps({"additionalContext": "\n".join(summary_lines)}))
PYEOF
