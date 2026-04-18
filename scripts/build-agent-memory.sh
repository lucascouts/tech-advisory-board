#!/usr/bin/env bash
# build-agent-memory.sh — compose the effective MEMORY.md for an agent
# spawn, scoped to a decision domain (§3.7 / coi-disclosure.md §2.1).
#
# Usage:
#   build-agent-memory.sh <agent-name> <domain> [--print-path]
#
# Inputs:
#   <agent-name>   researcher | auditor | (any agent with memory: project)
#   <domain>       kebab-case slug, e.g. frontend-framework, database
#                  Use "auto" to infer from the stack list on stdin.
#
# Output:
#   Writes (or refreshes) .claude/agent-memory/<agent>/<domain>/MEMORY.md
#   by merging that domain's MEMORY.md with .claude/agent-memory/<agent>/_fallback/MEMORY.md.
#   Prints the resolved MEMORY.md path on stdout.
#
# The Moderator invokes this helper BEFORE `subagent_type:` spawn so the
# agent's frontmatter `memory: project` resolves to the scoped file.
# The host-side symlink / copy strategy is host-specific; when the host
# does not support per-spawn memory overrides, this helper simply
# prints the canonical path and the Moderator passes the contents via
# `initialPrompt`.
set -uo pipefail

AGENT="${1:-}"
DOMAIN="${2:-}"

if [[ -z "$AGENT" || -z "$DOMAIN" ]]; then
    echo "Usage: build-agent-memory.sh <agent-name> <domain|auto> [--print-path]" >&2
    exit 2
fi

# Domain keyword map — extend when adding new domains (§coi-disclosure.md §4).
# Keep kebab-case slugs.
declare -A DOMAIN_KEYWORDS=(
    [frontend-framework]="nextjs next.js remix sveltekit svelte astro qwik vue nuxt solid"
    [database]="postgres postgresql mongodb cassandra redis clickhouse dynamodb sqlite mariadb mysql"
    [orchestrator]="kubernetes k8s nomad ecs fargate systemd swarm"
    [runtime-language]="node nodejs deno bun python go golang rust elixir ruby"
    [ai-ml]="openai anthropic claude llama gpt pytorch tensorflow vllm"
    [queue-stream]="kafka rabbitmq nats sqs redis-streams pulsar"
)

if [[ "$DOMAIN" == "auto" ]]; then
    STACKS=$(cat | tr 'A-Z' 'a-z')
    DOMAIN="_fallback"
    for slug in "${!DOMAIN_KEYWORDS[@]}"; do
        for kw in ${DOMAIN_KEYWORDS[$slug]}; do
            if grep -qw "$kw" <<<"$STACKS"; then
                DOMAIN="$slug"
                break 2
            fi
        done
    done
fi

ROOT=".claude/agent-memory/$AGENT"
mkdir -p "$ROOT/$DOMAIN" "$ROOT/_fallback"

FALLBACK_FILE="$ROOT/_fallback/MEMORY.md"
DOMAIN_FILE="$ROOT/$DOMAIN/MEMORY.md"
OUT_FILE="$DOMAIN_FILE"

# Initialize missing files with a header (never overwrite if content exists).
for f in "$FALLBACK_FILE" "$DOMAIN_FILE"; do
    if [[ ! -f "$f" ]]; then
        cat > "$f" <<HEADER
# Memory — $(basename "$(dirname "$f")") ($AGENT)

> Scoped memory per §coi-disclosure.md §2.1. Entries here are read by
> the agent when invoked under this domain. Keep entries short and
> tagged (\`stack:\`, \`session:\`, \`outcome:\`).

HEADER
    fi
done

for arg in "$@"; do
    if [[ "$arg" == "--print-path" ]]; then
        printf '%s\n' "$OUT_FILE"
        exit 0
    fi
done

# Default output: merged body on stdout — callers can feed this directly
# into the agent's initialPrompt when the host does not support per-spawn
# memory file overrides.
{
    echo "# Effective memory for agent=$AGENT domain=$DOMAIN"
    echo
    echo "## Fallback (cross-domain)"
    echo
    cat "$FALLBACK_FILE"
    echo
    echo "## Domain: $DOMAIN"
    echo
    cat "$DOMAIN_FILE"
}
