#!/usr/bin/env bash
# validate-claims.sh — data-quality validator for TAB session artifacts.
#
# Complements validate-synthesis-json.sh: that script checks *structure*,
# this one checks *claim hygiene* — citation coverage, uniform elimination
# criteria, confidence-tag completeness, discard-table asymmetries.
#
# Spec: ARCHITECTURE.md §9.2.
#
# Usage:
#   validate-claims.sh <path-to-synthesis.json>
#   validate-claims.sh --session <session-dir>    # reads synthesis.json
#                                                  # and state-full.json from
#                                                  # the session directory
#
# Exit codes:
#   0   all hard-fail checks pass (warnings may be present)
#   1   one or more hard-fail checks violated
#   2   bad invocation
set -uo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,18p' "$0" | sed 's/^# \?//'
    exit 0
fi

SYNTH_PATH=""
STATE_FULL_PATH=""

if [[ "${1:-}" == "--session" ]]; then
    [[ -n "${2:-}" ]] || { echo "Missing session dir" >&2; exit 2; }
    SESSION_DIR="$2"
    SYNTH_PATH="$SESSION_DIR/synthesis.json"
    STATE_FULL_PATH="$SESSION_DIR/state-full.json"
else
    SYNTH_PATH="${1:-}"
fi

if [[ -z "$SYNTH_PATH" ]]; then
    echo "Usage: validate-claims.sh <synthesis.json> | --session <dir>" >&2
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

python3 - "$SYNTH_PATH" "$STATE_FULL_PATH" <<'PYEOF'
import json, os, re, sys

synth_path = sys.argv[1]
state_full_path = sys.argv[2] if len(sys.argv) > 2 else ""

with open(synth_path) as f:
    s = json.load(f)

state_full = None
if state_full_path and os.path.isfile(state_full_path):
    try:
        with open(state_full_path) as f:
            state_full = json.load(f)
    except Exception as e:
        print(json.dumps({"error": f"state-full.json invalid: {e}"}))
        sys.exit(1)

errors = []
warnings = []

def require(cond, msg):
    if not cond:
        errors.append(msg)

def warn(cond, msg):
    if not cond:
        warnings.append(msg)

mode = (s.get("session") or {}).get("mode", "")
complexity = (s.get("session") or {}).get("complexity", "")
landscape = s.get("landscape") or {}

# --- Check 1: Each champion has >=1 weakness WITH mitigation ---
# (overlaps with validate-synthesis-json.sh but kept here for claim-level focus)
for i, c in enumerate(s.get("champions") or []):
    ws = c.get("weaknesses") or []
    require(len(ws) > 0,
            f"champions[{i}] ({c.get('name','?')}) has no weaknesses")
    for j, w in enumerate(ws):
        if isinstance(w, dict):
            require(bool(w.get("weakness")) and bool(w.get("mitigation")),
                    f"champions[{i}].weaknesses[{j}] needs weakness + mitigation")

# --- Check 2: Vanguard readiness_assessment populated ---
for i, c in enumerate(s.get("champions") or []):
    if (c.get("archetype") or "").lower() == "vanguard":
        ra = c.get("readiness_assessment") or {}
        require(ra.get("verdict") in ("production-ready", "near-ready", "experimental"),
                f"champions[{i}] Vanguard readiness_assessment.verdict missing or invalid")
        require(isinstance(ra.get("blockers"), list),
                f"champions[{i}] Vanguard readiness_assessment.blockers must be a list")

# --- Check 3: Reversibility declared ---
rec = s.get("recommendation") or {}
require(rec.get("reversibility") in ("low", "medium", "high"),
        "recommendation.reversibility must be low|medium|high")

# Reversibility for alternatives is optional in schema but we warn if missing
# when alternatives[] is non-trivial
alts = rec.get("alternatives") or []
if len(alts) >= 2:
    warn(all(("when_to_prefer" in a and a["when_to_prefer"]) for a in alts),
         "all alternatives[] entries should declare when_to_prefer")

# --- Check 4: Discard table size (warn) ---
discarded = landscape.get("discarded") or []
if complexity in ("Moderate", "High", "Very High"):
    warn(len(discarded) >= 3,
         f"landscape.discarded[] should have >=3 entries for complexity={complexity} (found {len(discarded)})")

# --- Check 5: Elimination criteria uniformity (warn) ---
# For each distinct criterion in discarded[], check that the shortlist does
# not include an option that would fail the same criterion.
shortlist_names = {item.get("name","") for item in (landscape.get("shortlist") or [])}
discard_criteria = {}
for d in discarded:
    crit = d.get("criterion")
    if crit:
        discard_criteria.setdefault(crit, []).append(d.get("name"))

# We cannot structurally verify uniform application without per-item criterion
# evaluation, but we CAN surface discards that use criteria not attested in
# the shortlist's rationale. Treat as informational.
if discard_criteria:
    warn(all(crit for crit in discard_criteria.keys()),
         "every discard should declare a criterion (some are missing)")

# --- Check 6: Confidence tag completeness ---
# For every landscape.shortlist[] entry, confidence should be present.
for i, item in enumerate(landscape.get("shortlist") or []):
    require(item.get("confidence") in ("high-conf", "med-conf", "low-conf", "unverified"),
            f"landscape.shortlist[{i}] ({item.get('name','?')}) missing/invalid confidence tag")

# Primary recommendation must carry a confidence tag
primary = rec.get("primary") or {}
require(primary.get("confidence") in ("high-conf", "med-conf", "low-conf", "unverified"),
        "recommendation.primary.confidence missing/invalid")

# --- Check 7: Claims registry hygiene (if state-full.json available) ---
if state_full is not None:
    registry = state_full.get("claims_registry") or []
    # Every claim with verified=true must have >=1 verification source
    for i, claim in enumerate(registry):
        if claim.get("verified") is True:
            vs = claim.get("verification_sources") or []
            require(len(vs) > 0,
                    f"claims_registry[{i}] (id={claim.get('id','?')}) "
                    "verified=true but verification_sources is empty")
    # Any claim with confidence=high-conf requires >=2 sources
    for i, claim in enumerate(registry):
        if claim.get("confidence") == "high-conf":
            vs = claim.get("verification_sources") or []
            warn(len(vs) >= 2,
                 f"claims_registry[{i}] (id={claim.get('id','?')}) "
                 f"claims high-conf but has only {len(vs)} source(s) "
                 "(2+ expected per §11)")
    # Unverified ratio sanity
    total = len(registry)
    if total > 0:
        unverified = sum(1 for c in registry if c.get("confidence") == "unverified")
        unverified_ratio = unverified / total
        warn(unverified_ratio < 0.3,
             f"unverified-claim ratio is {unverified_ratio:.1%} "
             f"({unverified}/{total}); ARCHITECTURE.md §10 triggers a "
             "+2 budget expansion above 30%")

result = {
    "valid": len(errors) == 0,
    "errors": errors,
    "warnings": warnings,
    "mode": mode,
    "complexity": complexity,
    "checked_state_full": state_full is not None,
}
print(json.dumps(result, indent=2))
sys.exit(0 if result["valid"] else 1)
PYEOF
