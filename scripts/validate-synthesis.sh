#!/usr/bin/env bash
# Validates that a TAB synthesis contains all required sections
# Uses structural patterns (markdown headers, section numbers, tables)
# that work regardless of output language.
# Usage: echo "$synthesis_text" | bash scripts/validate-synthesis.sh [mode]
# Modes: express, quick, standard, complete
# Exit 0 = valid, Exit 1 = missing sections, Exit 2 = unknown mode
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: echo "$synthesis" | validate-synthesis.sh [mode]

Validates that a TAB synthesis contains all required sections.
Uses language-agnostic structural patterns (markdown headers,
section numbers, tables) for validation.

Arguments:
  mode    One of: express, quick, standard, complete (default: standard)

Input:   Synthesis text via stdin
Output:  Progress (stderr), JSON result (stdout)

Exit codes:
  0    All required sections present
  1    Missing sections
  2    Unknown mode
HELP
    exit 0
fi

MODE="${1:-standard}"
INPUT=$(cat)

MISSING=0

check_section() {
    local pattern="$1"
    local name="$2"
    if echo "$INPUT" | grep -qiE "$pattern"; then
        echo "  ok: $name" >&2
        return 0
    else
        echo "  MISSING: $name" >&2
        return 1
    fi
}

echo "Validating synthesis (mode: $MODE)..." >&2

case "$MODE" in
    express)
        # Recommendation: look for bold tool name + version pattern
        check_section "\*\*[A-Za-z].*\*\*.*[0-9]+\.[0-9]+" "Recommendation (tool + version)" || ((MISSING++))
        # Alternative
        check_section "alternativ|valid.*(option|choice|if )" "Alternative" || ((MISSING++))
        # Reversibility
        check_section "reversib|easy.*medium.*hard|lock.in" "Reversibility" || ((MISSING++))
        ;;
    quick)
        # Simplified matrix (table with criteria/weight columns)
        check_section "\|.*\|.*\|.*\|" "Simplified Matrix (table)" || ((MISSING++))
        # Recommendation
        check_section "recommend|recomend" "Recommendation" || ((MISSING++))
        # Evolution / stages
        check_section "evolut|next stage|full product|POC.*MVP|estagio|proximo" "Evolution" || ((MISSING++))
        # Reversibility
        check_section "reversib|easy.*medium.*hard|lock.in" "Reversibility" || ((MISSING++))
        ;;
    standard|complete|complete+)
        # Section 1: Score matrix (table with X/10 scores)
        check_section "[0-9]+/10" "Score Matrix (X/10 scores)" || ((MISSING++))
        # Section 2: Recommendation with stage
        check_section "recommend.*stage|recommend.*POC|recommend.*MVP|recomend" "Recommendation" || ((MISSING++))
        # Evolution path (table or section with POC/MVP/Full)
        check_section "POC.*MVP.*Full|evolut|migration|migra" "Evolution Path" || ((MISSING++))
        # Section 3: Risk assessment (table with probability/impact)
        check_section "risk|risco|probabilit|impact" "Risk Assessment" || ((MISSING++))
        # Section 5: ADR / Decision Record
        check_section "ADR|decision record|registro.*decis|context.*alternatives|contexto.*alternativas" "ADR / Decision Record" || ((MISSING++))
        # Section 6: Direct recommendation (personal voice)
        check_section "if I were|se eu (estivesse|fosse)|in your (place|position)|I would go with|iria de" "Direct Recommendation" || ((MISSING++))
        # Reversibility (anywhere)
        check_section "reversib|easy.*medium.*hard|lock.in" "Reversibility" || ((MISSING++))
        ;;
    *)
        echo "Unknown mode: $MODE. Use: express, quick, standard, complete" >&2
        echo '{"valid": false, "mode": "'"$MODE"'", "error": "unknown mode"}'
        exit 2
        ;;
esac

if [ "$MISSING" -gt 0 ]; then
    echo "" >&2
    echo "RESULT: $MISSING required section(s) missing for mode '$MODE'" >&2
    echo '{"valid": false, "mode": "'"$MODE"'", "missing": '"$MISSING"'}'
    exit 1
else
    echo "" >&2
    echo "RESULT: All required sections present for mode '$MODE'" >&2
    echo '{"valid": true, "mode": "'"$MODE"'", "missing": 0}'
    exit 0
fi
