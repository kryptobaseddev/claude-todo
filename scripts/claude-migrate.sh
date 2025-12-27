#!/usr/bin/env bash
# CLEO Migration Command - claude-migrate
# Detects and migrates legacy claude-todo installations to CLEO format
#
# Usage:
#   cleo claude-migrate --check         # Detect legacy (no changes)
#   cleo claude-migrate --global        # Migrate ~/.claude-todo → ~/.cleo
#   cleo claude-migrate --project       # Migrate .claude → .cleo
#   cleo claude-migrate --all           # Migrate both
#
# Exit Codes (--check mode):
#   0 = Legacy installation found (migration needed)
#   1 = No legacy installation (already clean)
#   2 = Error during detection
#
# Exit Codes (migration modes):
#   0 = Migration successful
#   1 = No legacy found (nothing to migrate)
#   2 = Backup failed
#   3 = Rename failed
#   4 = Validation failed
#
# Version: 1.0.0 (CLEO v1.0.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source required libraries
if [[ -f "$LIB_DIR/paths.sh" ]]; then
    # shellcheck source=../lib/paths.sh
    source "$LIB_DIR/paths.sh"
else
    echo '{"error":"paths.sh not found","code":2}' >&2
    exit 2
fi

if [[ -f "$LIB_DIR/output-format.sh" ]]; then
    # shellcheck source=../lib/output-format.sh
    source "$LIB_DIR/output-format.sh"
fi

if [[ -f "$LIB_DIR/logging.sh" ]]; then
    # shellcheck source=../lib/logging.sh
    source "$LIB_DIR/logging.sh"
fi

# Suppress migration warnings in this script (we're handling migration explicitly)
suppress_migration_warnings

# =============================================================================
# EXIT CODES
# =============================================================================

readonly MIGRATE_SUCCESS=0
readonly MIGRATE_NO_LEGACY=1
readonly MIGRATE_BACKUP_FAILED=2
readonly MIGRATE_RENAME_FAILED=3
readonly MIGRATE_VALIDATION_FAILED=4

# For --check mode (grep-like semantics)
readonly CHECK_LEGACY_FOUND=0
readonly CHECK_NO_LEGACY=1
readonly CHECK_ERROR=2

# =============================================================================
# GLOBALS
# =============================================================================

FORMAT=""
MODE=""
VERBOSE=false

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat << 'EOF'
Usage: cleo claude-migrate [OPTIONS]

Detect and migrate legacy claude-todo installations to CLEO format.

Modes:
  --check            Detect legacy installations (read-only)
  --global           Migrate global: ~/.claude-todo → ~/.cleo
  --project          Migrate project: .claude → .cleo
  --all              Migrate both global and project

Options:
  --format FORMAT    Output format: text, json (default: auto-detect)
  --verbose, -v      Show detailed output
  --help, -h         Show this help message

Exit Codes (--check):
  0 = Legacy found (migration needed)
  1 = No legacy found (already clean)
  2 = Error during detection

Exit Codes (migration):
  0 = Migration successful
  1 = No legacy found (nothing to migrate)
  2 = Backup failed
  3 = Rename failed
  4 = Validation failed

Examples:
  cleo claude-migrate --check
  cleo claude-migrate --check --format json
  cleo claude-migrate --global
  cleo claude-migrate --project
  cleo claude-migrate --all
EOF
}

# =============================================================================
# DETECTION FUNCTIONS
# =============================================================================

# Detect legacy global installation
# Returns: JSON object with detection results
detect_legacy_global() {
    local legacy_path
    legacy_path=$(get_legacy_global_home)

    if [[ -d "$legacy_path" ]]; then
        local file_count=0
        local has_todo=false
        local has_config=false

        if [[ -f "$legacy_path/todo.json" ]]; then
            has_todo=true
        fi
        if [[ -f "$legacy_path/todo-config.json" ]]; then
            has_config=true
        fi
        if command -v find >/dev/null 2>&1; then
            file_count=$(find "$legacy_path" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi

        printf '{"found":true,"path":"%s","fileCount":%d,"hasTodo":%s,"hasConfig":%s}' \
            "$legacy_path" \
            "$file_count" \
            "$has_todo" \
            "$has_config"
    else
        printf '{"found":false,"path":"%s"}' "$legacy_path"
    fi
}

# Detect legacy project directory
# Returns: JSON object with detection results
detect_legacy_project() {
    local legacy_path
    legacy_path=$(get_legacy_project_dir)

    if [[ -d "$legacy_path" ]]; then
        local file_count=0
        local has_todo=false
        local has_config=false
        local has_log=false
        local has_archive=false

        if [[ -f "$legacy_path/todo.json" ]]; then
            has_todo=true
        fi
        if [[ -f "$legacy_path/todo-config.json" ]]; then
            has_config=true
        fi
        if [[ -f "$legacy_path/todo-log.json" ]]; then
            has_log=true
        fi
        if [[ -f "$legacy_path/todo-archive.json" ]]; then
            has_archive=true
        fi
        if command -v find >/dev/null 2>&1; then
            file_count=$(find "$legacy_path" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi

        printf '{"found":true,"path":"%s","fileCount":%d,"hasTodo":%s,"hasConfig":%s,"hasLog":%s,"hasArchive":%s}' \
            "$legacy_path" \
            "$file_count" \
            "$has_todo" \
            "$has_config" \
            "$has_log" \
            "$has_archive"
    else
        printf '{"found":false,"path":"%s"}' "$legacy_path"
    fi
}

# Detect legacy environment variables
# Returns: JSON object with detection results
detect_legacy_env() {
    local vars_found=()
    local json_vars="[]"

    if [[ -n "${CLAUDE_TODO_HOME:-}" ]]; then
        vars_found+=("CLAUDE_TODO_HOME")
    fi
    if [[ -n "${CLAUDE_TODO_DIR:-}" ]]; then
        vars_found+=("CLAUDE_TODO_DIR")
    fi
    if [[ -n "${CLAUDE_TODO_FORMAT:-}" ]]; then
        vars_found+=("CLAUDE_TODO_FORMAT")
    fi
    if [[ -n "${CLAUDE_TODO_DEBUG:-}" ]]; then
        vars_found+=("CLAUDE_TODO_DEBUG")
    fi

    if [[ ${#vars_found[@]} -gt 0 ]]; then
        local first=true
        local json_array="["
        for var in "${vars_found[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json_array+=","
            fi
            json_array+="\"$var\""
        done
        json_array+="]"
        json_vars="$json_array"
    fi

    if [[ ${#vars_found[@]} -gt 0 ]]; then
        printf '{"found":true,"count":%d,"variables":%s}' \
            "${#vars_found[@]}" \
            "$json_vars"
    else
        printf '{"found":false,"count":0,"variables":[]}'
    fi
}

# =============================================================================
# CHECK MODE
# =============================================================================

run_check_mode() {
    local global_result project_result env_result
    local global_found=false project_found=false env_found=false
    local any_legacy=false

    # Detect all legacy installations
    global_result=$(detect_legacy_global)
    project_result=$(detect_legacy_project)
    env_result=$(detect_legacy_env)

    # Parse results
    if echo "$global_result" | grep -q '"found":true'; then
        global_found=true
        any_legacy=true
    fi
    if echo "$project_result" | grep -q '"found":true'; then
        project_found=true
        any_legacy=true
    fi
    if echo "$env_result" | grep -q '"found":true'; then
        env_found=true
        any_legacy=true
    fi

    # Build JSON output
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local json_output
    json_output=$(cat <<EOF
{
  "\$schema": "https://claude-todo.dev/schemas/v1/output.schema.json",
  "_meta": {
    "command": "claude-migrate --check",
    "timestamp": "${timestamp}",
    "version": "1.0.0"
  },
  "success": true,
  "migrationNeeded": ${any_legacy},
  "global": ${global_result},
  "project": ${project_result},
  "environment": ${env_result}
}
EOF
    )

    # Output based on format
    if is_json_output "$FORMAT"; then
        echo "$json_output"
    else
        # Human-readable output
        echo ""
        echo "CLEO Migration Check"
        echo "===================="
        echo ""

        if [[ "$global_found" == "true" ]]; then
            echo "✗ Global: ~/.claude-todo/ found (legacy)"
            if [[ "$VERBOSE" == "true" ]]; then
                echo "  → Run: cleo claude-migrate --global"
            fi
        else
            echo "✓ Global: ~/.cleo (current)"
        fi

        if [[ "$project_found" == "true" ]]; then
            echo "✗ Project: .claude/ found (legacy)"
            if [[ "$VERBOSE" == "true" ]]; then
                echo "  → Run: cleo claude-migrate --project"
            fi
        else
            echo "✓ Project: .cleo (current)"
        fi

        if [[ "$env_found" == "true" ]]; then
            echo "⚠ Environment: Legacy variables detected"
            if [[ "$VERBOSE" == "true" ]]; then
                echo "  Variables: $(echo "$env_result" | grep -o '"variables":\[[^]]*\]' | sed 's/"variables":\[//;s/\]$//' | tr ',' ' ')"
                echo "  → Update to CLEO_* equivalents"
            fi
        else
            echo "✓ Environment: Clean (no legacy vars)"
        fi

        echo ""
        if [[ "$any_legacy" == "true" ]]; then
            echo "Migration needed. Run: cleo claude-migrate --all"
        else
            echo "No migration needed. System is clean."
        fi
        echo ""
    fi

    # Exit codes per spec
    if [[ "$any_legacy" == "true" ]]; then
        return $CHECK_LEGACY_FOUND
    else
        return $CHECK_NO_LEGACY
    fi
}

# =============================================================================
# OUTPUT FORMAT DETECTION
# =============================================================================

# Check if JSON output should be used
is_json_output() {
    local format="${1:-}"

    # Explicit format takes precedence
    if [[ "$format" == "json" ]]; then
        return 0
    fi
    if [[ "$format" == "text" ]]; then
        return 1
    fi

    # Auto-detect: JSON if not a TTY (piped output)
    if [[ ! -t 1 ]]; then
        return 0
    fi

    return 1
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                MODE="check"
                shift
                ;;
            --global)
                MODE="global"
                shift
                ;;
            --project)
                MODE="project"
                shift
                ;;
            --all)
                MODE="all"
                shift
                ;;
            --format)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --format requires a value" >&2
                    exit 2
                fi
                FORMAT="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Run 'cleo claude-migrate --help' for usage." >&2
                exit 2
                ;;
        esac
    done

    # Require a mode
    if [[ -z "$MODE" ]]; then
        echo "Error: Must specify --check, --global, --project, or --all" >&2
        echo "Run 'cleo claude-migrate --help' for usage." >&2
        exit 2
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_args "$@"

    case "$MODE" in
        check)
            run_check_mode
            ;;
        global)
            echo "Error: --global mode not yet implemented (T916)" >&2
            exit 2
            ;;
        project)
            echo "Error: --project mode not yet implemented (T917)" >&2
            exit 2
            ;;
        all)
            echo "Error: --all mode not yet implemented (T918)" >&2
            exit 2
            ;;
        *)
            echo "Error: Invalid mode: $MODE" >&2
            exit 2
            ;;
    esac
}

main "$@"
