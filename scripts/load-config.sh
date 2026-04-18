#!/usr/bin/env bash
# load-config.sh — load and merge TAB configuration.
# Precedence:
#   userConfig env vars > TAB/config.json > hardcoded defaults
# Usage:
#   load-config.sh [--base DIR] [--tab-dir DIR]
# Resolution of TAB/config.json:
#   1. If --tab-dir is given, use <tab-dir>/config.json
#   2. Else if --base is given, use <base>/TAB/config.json
#   3. Else walk up from $PWD looking for a TAB/ directory; use its config.json
#   4. Else no file — defaults only
# Output (JSON on stdout): merged config object matching schemas/config.schema.json
# userConfig env var mapping:
#   CLAUDE_PLUGIN_OPTION_max_cost_per_session_usd → budget.max_cost_per_session_usd
#   CLAUDE_PLUGIN_OPTION_warn_at_usd              → budget.warn_at_usd
#   CLAUDE_PLUGIN_OPTION_language_preference      → language_preference
#   CLAUDE_PLUGIN_OPTION_default_mode             → default_mode (legacy
#     aliases Express/Quick normalized to Instant/Fast — removal in 0.3)
set -uo pipefail

BASE=""
TAB_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)     BASE="$2"; shift ;;
        --tab-dir)  TAB_DIR="$2"; shift ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

# Resolve config.json location
if [[ -z "$TAB_DIR" ]]; then
    if [[ -n "$BASE" ]]; then
        TAB_DIR="$BASE/TAB"
    else
        # Walk up from $PWD looking for TAB/
        dir="$PWD"
        while [[ "$dir" != "/" ]]; do
            if [[ -d "$dir/TAB" ]]; then
                TAB_DIR="$dir/TAB"
                break
            fi
            dir="$(dirname "$dir")"
        done
    fi
fi

CONFIG_PATH="${TAB_DIR:-}/config.json"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 required" >&2
    exit 1
fi

python3 - "$CONFIG_PATH" <<'PYEOF'
import json, os, sys

config_path = sys.argv[1]

# --- Hardcoded defaults ---
defaults = {
    "project_name": None,
    "default_stage": "MVP",
    "language_preference": None,
    "budget": {
        "max_cost_per_session_usd": 5.00,
        "warn_at_usd": 3.00,
        "max_duration_s": 900,
    },
    "preferences": {
        "cloud": None,
        "preferred_languages": [],
        "avoided_licenses": [],
        "team_size": None,
        "team_expertise": [],
    },
    "legacy_stack": {
        "must_consider": [],
        "must_integrate_with": [],
    },
    "cache": {
        "share_across_projects": False,
        "max_age_fresh_days": 30,
        "max_age_stale_days": 180,
    },
    "output": {
        "auto_generate_adr": True,
        "auto_archive_sessions": True,
        "session_archive_idle_hours": 24,
        "use_git_root": False,
    },
    "adversarial": {
        "auditor_mandatory_modes": ["Complete", "Complete+", "Rechallenge"],
        "supervisor_trigger_threshold": 0.8,
        "concession_ratio_threshold": 0.6,
    },
}

# --- Load TAB/config.json (if present) ---
file_config = {}
file_exists = False
if config_path and config_path != "/config.json" and os.path.isfile(config_path):
    file_exists = True
    try:
        with open(config_path) as f:
            file_config = json.load(f)
    except Exception as e:
        print(json.dumps({"error": f"invalid config.json: {e}",
                          "path": config_path}), file=sys.stderr)
        sys.exit(1)

# --- Deep-merge file_config over defaults ---
def deep_merge(base, overlay):
    if not isinstance(overlay, dict):
        return overlay
    out = dict(base) if isinstance(base, dict) else {}
    for k, v in overlay.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out

merged = deep_merge(defaults, file_config)

# --- userConfig env-var overrides (win over everything) ---
overrides_applied = []

def getenv_num(key):
    v = os.environ.get(f"CLAUDE_PLUGIN_OPTION_{key}")
    if v is None or v == "":
        return None
    try:
        return float(v)
    except ValueError:
        return None

def getenv_str(key):
    v = os.environ.get(f"CLAUDE_PLUGIN_OPTION_{key}")
    return v if v else None

v = getenv_num("max_cost_per_session_usd")
if v is not None:
    merged.setdefault("budget", {})["max_cost_per_session_usd"] = v
    overrides_applied.append("budget.max_cost_per_session_usd")

v = getenv_num("warn_at_usd")
if v is not None:
    merged.setdefault("budget", {})["warn_at_usd"] = v
    overrides_applied.append("budget.warn_at_usd")

v = getenv_str("language_preference")
if v is not None:
    merged["language_preference"] = v
    overrides_applied.append("language_preference")

# default_mode (userConfig) — normalize legacy aliases Express/Quick
# (Express → Instant, Quick → Fast) and surface them in provenance so
# downstream consumers can see the rewrite.
v = getenv_str("default_mode")
if v is not None:
    alias_map = {"Express": "Instant", "Quick": "Fast"}
    normalized = alias_map.get(v, v)
    merged["default_mode"] = normalized
    overrides_applied.append("default_mode")
    if normalized != v:
        overrides_applied.append(f"default_mode:legacy-alias({v}→{normalized})")

# --- Envelope with provenance ---
result = {
    "config": merged,
    "_source": {
        "config_path": config_path if file_exists else None,
        "config_loaded": file_exists,
        "userconfig_overrides": overrides_applied,
    },
}
print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF
