#!/usr/bin/env bash
# normalize-mode.sh — canonicalize a TAB session mode string.
#
# Accepts the current canonical names (Instant, Fast, Standard, Complete,
# Complete+, Rechallenge) and the legacy aliases (Express → Instant,
# Quick → Fast) introduced before the 0.2 rename. Legacy aliases emit a
# deprecation notice to stderr and resolve to the canonical name on stdout.
# Unknown inputs pass through unchanged (the caller validates against the
# enum in schemas/synthesis.schema.json).
#
# Usage:
#   normalize-mode.sh <mode>
# Output:
#   canonical mode on stdout
#   deprecation warning on stderr (legacy aliases only)
# Exit codes:
#   0 — canonical or legacy alias
#   0 — unknown (passed through so caller can decide)
#
# Deprecation window: accepted through 0.2.x, removed in 0.3.0.
set -uo pipefail

MODE="${1:-}"
[[ -n "$MODE" ]] || { echo "Usage: normalize-mode.sh <mode>" >&2; exit 2; }

case "$MODE" in
    Express)
        echo "[TAB:normalize-mode] legacy alias 'Express' → 'Instant' (removal in 0.3)" >&2
        printf 'Instant'
        ;;
    Quick)
        echo "[TAB:normalize-mode] legacy alias 'Quick' → 'Fast' (removal in 0.3)" >&2
        printf 'Fast'
        ;;
    *)
        printf '%s' "$MODE"
        ;;
esac
