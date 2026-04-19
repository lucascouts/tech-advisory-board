#!/usr/bin/env bash
# validate-synthesis-json.sh — structural validation of a synthesis.json file
# against the hard-fail assertions in .
# Uses Python stdlib only (no jsonschema dependency). If `jsonschema` is
# installed it runs an additional full-schema pass; otherwise only the
# hard-fail assertions are checked.
# Usage:
#   validate-synthesis-json.sh <path-to-synthesis.json>
#   validate-synthesis-json.sh --schema <schema-path> <path>
# Exit codes:
#   0   valid
#   1   hard-fail assertion violated
#   2   invalid invocation
set -uo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,14p' "$0" | sed 's/^# \?//'
    exit 0
fi

SCHEMA_PATH=""
SYNTH_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --schema) SCHEMA_PATH="$2"; shift ;;
        *) SYNTH_PATH="$1" ;;
    esac
    shift
done

if [[ -z "$SYNTH_PATH" ]]; then
    echo "Usage: validate-synthesis-json.sh [--schema <schema>] <synthesis.json>" >&2
    exit 2
fi

if [[ ! -f "$SYNTH_PATH" ]]; then
    echo "File not found: $SYNTH_PATH" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 required" >&2
    exit 1
fi

python3 - "$SYNTH_PATH" "$SCHEMA_PATH" <<'PYEOF'
import json, sys

synth_path, schema_path = sys.argv[1], sys.argv[2]

try:
    with open(synth_path) as f:
        s = json.load(f)
except Exception as e:
    print(json.dumps({"valid": False, "errors": [f"not valid JSON: {e}"]}))
    sys.exit(1)

errors = []
warnings = []

def require(cond, msg):
    if not cond:
        errors.append(msg)

def warn(cond, msg):
    if not cond:
        warnings.append(msg)

# --- Hard-fail assertions ---

# All required top-level fields present
for field in ("tab_version", "schema_version", "session", "context",
              "landscape", "recommendation", "risks"):
    require(field in s, f"missing required top-level field: {field}")

# recommendation.primary exists and has confidence
rec = s.get("recommendation") or {}
primary = rec.get("primary") or {}
require(bool(primary), "recommendation.primary is missing or empty")
require("confidence" in primary,
        "recommendation.primary.confidence is required")

# risks[] non-empty
require(isinstance(s.get("risks"), list) and len(s["risks"]) > 0,
        "risks[] must be non-empty")

# auditor_findings[] present in Complete/Complete+/Rechallenge
mode = (s.get("session") or {}).get("mode", "")
if mode in ("Complete", "Complete+", "Rechallenge"):
    af = s.get("auditor_findings")
    require(isinstance(af, list) and len(af) > 0,
            f"auditor_findings[] required and non-empty for mode={mode}")
    # Every critical/moderate finding must be addressed or explicitly dismissed
    for i, finding in enumerate(af or []):
        sev = finding.get("severity")
        if sev in ("critical", "moderate"):
            addressed = finding.get("addressed_in_section")
            dismissed = finding.get("dismissed_reason")
            require(bool(addressed) or bool(dismissed),
                    f"auditor_findings[{i}] (severity={sev}) must set "
                    "addressed_in_section or dismissed_reason")

# reversibility declared
require("reversibility" in rec, "recommendation.reversibility is required")

# Every champion has >=1 weakness with mitigation
for i, c in enumerate(s.get("champions") or []):
    ws = c.get("weaknesses") or []
    require(len(ws) > 0,
            f"champions[{i}] ({c.get('name','?')}) has no weaknesses")
    for j, w in enumerate(ws):
        require(isinstance(w, dict) and w.get("weakness") and w.get("mitigation"),
                f"champions[{i}].weaknesses[{j}] needs both 'weakness' and 'mitigation'")

# Vanguard readiness assessment
for i, c in enumerate(s.get("champions") or []):
    if (c.get("archetype") or "").lower() == "vanguard":
        ra = c.get("readiness_assessment")
        require(bool(ra),
                f"champions[{i}] ({c.get('name','?')}) is Vanguard but "
                "readiness_assessment is missing")

# conflicts_of_interest[]: hard-required in adversarial modes
if mode in ("Complete", "Complete+", "Rechallenge"):
    coi = s.get("conflicts_of_interest")
    require(isinstance(coi, list) and len(coi) > 0,
            f"conflicts_of_interest[] required and non-empty for mode={mode} "
            "(see skills/tab/references/coi-disclosure.md)")
    for i, card in enumerate(coi or []):
        if not isinstance(card, dict):
            errors.append(f"conflicts_of_interest[{i}] must be an object")
            continue
        for key in ("agent", "agent_type", "memory_loaded", "bias_signal", "mitigations"):
            require(key in card,
                    f"conflicts_of_interest[{i}].{key} is required")
        at = card.get("agent_type")
        if at is not None and at not in ("researcher", "auditor"):
            errors.append(
                f"conflicts_of_interest[{i}].agent_type must be "
                f"'researcher' or 'auditor' (got {at!r})"
            )
        bs = card.get("bias_signal")
        if bs is not None and bs not in ("none", "low", "medium", "high"):
            errors.append(
                f"conflicts_of_interest[{i}].bias_signal must be one of "
                f"none|low|medium|high (got {bs!r})"
            )

# In Instant/Fast/Standard, conflicts_of_interest is optional but must be
# well-formed if present.
elif "conflicts_of_interest" in s:
    coi = s.get("conflicts_of_interest")
    if not isinstance(coi, list):
        warnings.append("conflicts_of_interest must be an array if present")

# --- Warn-level assertions ---

# At least one alternatives[] entry
warn(len(rec.get("alternatives") or []) > 0,
     "recommendation.alternatives[] is empty")

# migration_path[] covers current stage → next stage
mp = s.get("migration_path") or []
stage = (s.get("context") or {}).get("stage")
if stage and stage != "Full":
    stages_in_path = {(step.get("from_stage"), step.get("to_stage")) for step in mp}
    expected = {
        "POC": ("POC", "MVP"),
        "MVP": ("MVP", "Full"),
    }.get(stage)
    warn(expected in stages_in_path,
         f"migration_path[] does not include a {expected[0]}→{expected[1]} step")

# Discard table size for Moderate+ complexity
complexity = (s.get("session") or {}).get("complexity", "")
if complexity in ("Moderate", "High", "Very High"):
    warn(len((s.get("landscape") or {}).get("discarded") or []) >= 3,
         f"landscape.discarded[] should have >=3 entries for complexity={complexity}")

# --- Optional full-schema validation via jsonschema ---
schema_errors = []
if schema_path:
    try:
        import jsonschema  # type: ignore
        with open(schema_path) as f:
            schema = json.load(f)
        validator = jsonschema.Draft202012Validator(schema)
        for err in validator.iter_errors(s):
            schema_errors.append(f"{'.'.join(str(p) for p in err.absolute_path)}: {err.message}")
    except ImportError:
        schema_errors.append("(jsonschema library not installed — skipping full-schema pass)")

result = {
    "valid": len(errors) == 0,
    "errors": errors,
    "warnings": warnings,
    "schema_errors": schema_errors,
    "mode": mode,
    "complexity": complexity,
}
print(json.dumps(result, indent=2))
sys.exit(0 if result["valid"] else 1)
PYEOF
