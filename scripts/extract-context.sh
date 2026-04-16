#!/usr/bin/env bash
# Extracts project tech stack context for TAB sessions as JSON
# Usage: extract-context.sh [OPTIONS] [target_path]
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'HELP'
Usage: extract-context.sh [OPTIONS] [target_path]

Analyzes a project directory or file and outputs detected tech stack
context as structured JSON for use in TAB sessions.

Arguments:
  target_path    Path to analyze (default: current directory)

Options:
  -h, --help     Show this help message
  --json         Output as JSON (default)
  --text         Output as plain text (legacy)

Exit codes:
  0    Success
  1    Target not found
HELP
    exit 0
fi

OUTPUT_FORMAT="json"
TARGET=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --text) OUTPUT_FORMAT="text" ;;
        --json) OUTPUT_FORMAT="json" ;;
        --*) ;; # ignore unknown flags
        *) TARGET="$arg" ;;
    esac
done

TARGET="${TARGET:-.}"

# Resolve to absolute path
if [[ "$TARGET" != /* ]]; then
    TARGET="$(pwd)/$TARGET"
fi

# Check if target exists
if [ ! -e "$TARGET" ]; then
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo '{"error": "Target not found", "target": "'"$TARGET"'"}'
    else
        echo "Target not found: $TARGET"
    fi
    exit 1
fi

# If target is a file, find project root
if [ -f "$TARGET" ]; then
    FILE_PATH="$TARGET"
    FILE_EXT="${TARGET##*.}"
    FILE_LANG="unknown"
    case "$FILE_EXT" in
        py)     FILE_LANG="Python" ;;
        ts|tsx) FILE_LANG="TypeScript" ;;
        js|jsx) FILE_LANG="JavaScript" ;;
        go)     FILE_LANG="Go" ;;
        rs)     FILE_LANG="Rust" ;;
        java)   FILE_LANG="Java" ;;
        rb)     FILE_LANG="Ruby" ;;
        ex|exs) FILE_LANG="Elixir" ;;
        php)    FILE_LANG="PHP" ;;
        cs)     FILE_LANG="C#" ;;
        swift)  FILE_LANG="Swift" ;;
        dart)   FILE_LANG="Dart" ;;
    esac

    # Walk up to find project root
    dir="$(dirname "$TARGET")"
    PROJECT_ROOT=""
    MANIFEST=""
    while [ "$dir" != "/" ]; do
        for f in package.json requirements.txt pyproject.toml Cargo.toml go.mod pom.xml build.gradle Package.swift pubspec.yaml; do
            if [ -f "$dir/$f" ]; then
                PROJECT_ROOT="$dir"
                MANIFEST="$f"
                break 2
            fi
        done
        dir="$(dirname "$dir")"
    done

    if [ -z "$PROJECT_ROOT" ]; then
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            echo '{"target": "'"$FILE_PATH"'", "type": "file", "language": "'"$FILE_LANG"'", "manifests": []}'
        else
            echo "=== Single File Analysis ==="
            echo "File: $FILE_PATH"
            echo "Language: $FILE_LANG"
        fi
        exit 0
    fi
    TARGET="$PROJECT_ROOT"
fi

# From here, TARGET is a directory
cd "$TARGET"

# Collect data
MANIFESTS=()
for f in package.json requirements.txt pyproject.toml Cargo.toml go.mod \
         pom.xml build.gradle build.sbt mix.exs Gemfile composer.json \
         *.csproj *.fsproj Package.swift pubspec.yaml; do
    [ -f "$f" ] && MANIFESTS+=("$f")
done

CONFIGS=()
for pattern in tsconfig.json .eslintrc* eslint.config* vite.config* next.config* \
               tailwind.config* postcss.config* webpack.config* docker-compose*.yml \
               Dockerfile .env.example; do
    for match in $(compgen -G "$pattern" 2>/dev/null || true); do
        CONFIGS+=("$match")
    done
done

# Git context
GIT_BRANCH=""
GIT_COMMITS=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_BRANCH="$(git branch --show-current 2>/dev/null || echo '')"
    GIT_COMMITS="$(git log --oneline -5 2>/dev/null || echo '')"
fi

# Directory structure (limited)
STRUCTURE="$(find . -maxdepth 2 -type f \( \
    -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
    -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
    -o -name "*.rb" -o -name "*.ex" -o -name "*.exs" \
    -o -name "*.cs" -o -name "*.swift" -o -name "*.dart" \
    -o -name "Dockerfile" -o -name "docker-compose*.yml" \
    \) 2>/dev/null | head -15 | sort)"

if [ "$OUTPUT_FORMAT" = "text" ]; then
    echo "=== Analyzing: $TARGET ==="
    echo ""
    echo "=== Project Manifests ==="
    for f in "${MANIFESTS[@]}"; do echo "Found: $f"; done
    echo ""
    echo "=== Primary Stack ==="
    if [ -f package.json ] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
d = json.load(open('package.json'))
print('Name:', d.get('name', 'N/A'))
deps = d.get('dependencies', {})
dev = d.get('devDependencies', {})
print('Dependencies:', ', '.join(sorted(deps.keys())[:15]))
print('DevDependencies:', ', '.join(sorted(dev.keys())[:10]))
" 2>/dev/null || echo "package.json found but could not parse"
    elif [ -f requirements.txt ]; then
        echo "Python project"
        head -15 requirements.txt
    elif [ -f pyproject.toml ]; then
        echo "Python project (pyproject.toml)"
        head -20 pyproject.toml
    elif [ -f Cargo.toml ]; then
        echo "Rust project"
        head -12 Cargo.toml
    elif [ -f go.mod ]; then
        echo "Go project"
        head -8 go.mod
    else
        echo "No recognized project manifest"
    fi
    echo ""
    echo "=== Config Files ==="
    for f in "${CONFIGS[@]}"; do echo "Found: $f"; done
    echo ""
    echo "=== Git Context ==="
    if [ -n "$GIT_BRANCH" ]; then
        echo "Branch: $GIT_BRANCH"
        echo "Recent commits:"
        echo "$GIT_COMMITS"
    else
        echo "Not a git repository"
    fi
    echo ""
    echo "=== Directory Structure ==="
    echo "$STRUCTURE"
    exit 0
fi

# Encode arrays as JSON safely (handles spaces/quotes in paths)
_to_json_array() {
    local arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
        echo '[]'
        return
    fi
    printf '%s\n' "${arr[@]}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"
}

MANIFESTS_JSON=$(_to_json_array "${MANIFESTS[@]}")
CONFIGS_JSON=$(_to_json_array "${CONFIGS[@]}")

# JSON output via python3
if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json, sys, os

target = '$TARGET'
manifests = json.loads('$MANIFESTS_JSON')
configs = json.loads('$CONFIGS_JSON')
git_branch = '''$GIT_BRANCH'''
git_commits_raw = '''$GIT_COMMITS'''
structure_raw = '''$STRUCTURE'''

result = {
    'target': target,
    'manifests': manifests,
    'stack': {},
    'configs': configs,
    'git': {},
    'structure': [s for s in structure_raw.strip().split('\n') if s][:15]
}

# Parse stack from package.json
if os.path.exists('package.json'):
    try:
        d = json.load(open('package.json'))
        deps = sorted(d.get('dependencies', {}).keys())[:15]
        dev = sorted(d.get('devDependencies', {}).keys())[:10]
        result['stack'] = {
            'name': d.get('name', 'N/A'),
            'dependencies': deps,
            'devDependencies': dev
        }
    except:
        result['stack'] = {'error': 'could not parse package.json'}
elif os.path.exists('Cargo.toml'):
    result['stack'] = {'type': 'rust'}
elif os.path.exists('go.mod'):
    result['stack'] = {'type': 'go'}
elif os.path.exists('requirements.txt') or os.path.exists('pyproject.toml'):
    result['stack'] = {'type': 'python'}
elif any(f.endswith('.csproj') or f.endswith('.fsproj') for f in manifests):
    result['stack'] = {'type': 'dotnet'}
elif os.path.exists('Package.swift'):
    result['stack'] = {'type': 'swift'}
elif os.path.exists('pubspec.yaml'):
    result['stack'] = {'type': 'dart'}

# Git
if git_branch:
    commits = [c for c in git_commits_raw.strip().split('\n') if c][:5]
    result['git'] = {'branch': git_branch, 'recent_commits': commits}

print(json.dumps(result, indent=2, ensure_ascii=False))
" 2>/dev/null
else
    # Fallback: minimal JSON without python3
    echo '{"target": "'"$TARGET"'", "manifests": [], "note": "python3 not available for full JSON output"}'
fi
