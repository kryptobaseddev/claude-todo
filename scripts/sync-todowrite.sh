#!/usr/bin/env bash
# =============================================================================
# sync-todowrite.sh - Orchestrate TodoWrite bidirectional sync
# =============================================================================
# Main entry point for claude-todo ↔ TodoWrite synchronization.
# Coordinates inject (session start) and extract (session end) operations.
#
# Research: T227 (todowrite-sync-research.md)
#
# Usage:
#   claude-todo sync --inject [OPTIONS]     # Session start: prepare tasks
#   claude-todo sync --extract [FILE]       # Session end: merge changes
#   claude-todo sync --status               # Show sync state
#
# This script is registered in the main CLI dispatcher.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source output formatting library
if [[ -f "$LIB_DIR/output-format.sh" ]]; then
  # shellcheck source=../lib/output-format.sh
  source "$LIB_DIR/output-format.sh"
fi

# Source error JSON library (includes exit-codes.sh)
if [[ -f "$LIB_DIR/error-json.sh" ]]; then
  # shellcheck source=../lib/error-json.sh
  source "$LIB_DIR/error-json.sh"
elif [[ -f "$LIB_DIR/exit-codes.sh" ]]; then
  # Fallback: source exit codes directly if error-json.sh not available
  # shellcheck source=../lib/exit-codes.sh
  source "$LIB_DIR/exit-codes.sh"
fi

# =============================================================================
# Colors and Logging
# =============================================================================
if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' NC=''
fi

log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { [[ "${QUIET:-false}" != "true" ]] && echo -e "${YELLOW}[WARN]${NC} $1" || true; }
log_info() { [[ "${QUIET:-false}" != "true" ]] && echo -e "${GREEN}[INFO]${NC} $1" || true; }

# =============================================================================
# Configuration
# =============================================================================
SYNC_DIR=".claude/sync"
STATE_FILE="${SYNC_DIR}/todowrite-session.json"
COMMAND_NAME="sync"

# Output options
FORMAT=""
QUIET=false

# Subcommand
SUBCOMMAND=""

# =============================================================================
# Help
# =============================================================================
show_help() {
    cat << 'EOF'
sync-todowrite.sh - TodoWrite bidirectional synchronization

USAGE
    claude-todo sync <subcommand> [OPTIONS]

SUBCOMMANDS
    --inject          Prepare tasks for TodoWrite (session start)
    --extract FILE    Merge TodoWrite state back (session end)
    --status          Show current sync state
    --clear           Clear sync state without merging

INJECT OPTIONS
    --max-tasks N     Maximum tasks to inject (default: 8)
    --focused-only    Only inject the focused task
    --output FILE     Write to file instead of stdout
    --quiet, -q       Suppress info messages

EXTRACT OPTIONS
    --default-phase SLUG  Override default phase for new tasks
    --dry-run             Preview changes without applying
    --quiet, -q           Suppress info messages

GLOBAL OPTIONS
    --format, -f      Output format: text (default) or json
    --json            Shorthand for --format json
    --human           Shorthand for --format text
    --quiet, -q       Suppress info messages

WORKFLOW
    1. Session Start:  claude-todo sync --inject
       → Outputs TodoWrite JSON
       → Saves session state for round-trip

    2. During Session: Claude uses TodoWrite normally

    3. Session End:    claude-todo sync --extract <state.json>
       → Parses TodoWrite state
       → Marks completed tasks as done
       → Creates new tasks
       → Clears session state

EXAMPLES
    # Start session - inject tasks to TodoWrite format
    claude-todo sync --inject

    # End session - extract and merge changes
    claude-todo sync --extract /tmp/todowrite-state.json

    # Check if sync state exists
    claude-todo sync --status

    # Clear stale sync state
    claude-todo sync --clear

EOF
    exit 0
}

# =============================================================================
# Subcommand Handlers
# =============================================================================

handle_inject() {
    shift  # Remove --inject
    exec "$SCRIPT_DIR/inject-todowrite.sh" "$@"
}

handle_extract() {
    shift  # Remove --extract
    exec "$SCRIPT_DIR/extract-todowrite.sh" "$@"
}

handle_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ "$FORMAT" == "json" ]]; then
            local timestamp version
            timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            version=$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || echo "0.15.0")
            jq -n \
                --arg version "$version" \
                --arg timestamp "$timestamp" \
                --arg state_file "$STATE_FILE" \
                '{
                    "$schema": "https://claude-todo.dev/schemas/output.schema.json",
                    "_meta": {
                        "format": "json",
                        "version": $version,
                        "command": "sync",
                        "subcommand": "status",
                        "timestamp": $timestamp
                    },
                    "success": true,
                    "active": false,
                    "state_file": $state_file,
                    "message": "No active sync session"
                }'
        else
            log_info "No active sync session"
            echo ""
            echo "State file: $STATE_FILE (not found)"
        fi
        exit 0
    fi

    local session_id=$(jq -r '.session_id // "unknown"' "$STATE_FILE")
    local injected_at=$(jq -r '.injected_at // "unknown"' "$STATE_FILE")
    local injected_phase=$(jq -r '.injectedPhase // "none"' "$STATE_FILE")
    local task_count=$(jq '.injected_tasks | length' "$STATE_FILE")
    local task_ids_json=$(jq '.injected_tasks' "$STATE_FILE")
    local task_ids=$(jq -r '.injected_tasks | join(", ")' "$STATE_FILE")

    # Get phase distribution if metadata exists
    local phases_json="null"
    if jq -e '.task_metadata' "$STATE_FILE" >/dev/null 2>&1; then
        phases_json=$(jq '[.task_metadata[] | .phase // "unknown"] | group_by(.) | map({phase: .[0], count: length})' "$STATE_FILE")
    fi

    if [[ "$FORMAT" == "json" ]]; then
        local timestamp version
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        version=$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || echo "0.15.0")
        jq -n \
            --arg version "$version" \
            --arg timestamp "$timestamp" \
            --arg state_file "$STATE_FILE" \
            --arg session_id "$session_id" \
            --arg injected_at "$injected_at" \
            --arg injected_phase "$injected_phase" \
            --argjson task_count "$task_count" \
            --argjson task_ids "$task_ids_json" \
            --argjson phases "$phases_json" \
            '{
                "$schema": "https://claude-todo.dev/schemas/output.schema.json",
                "_meta": {
                    "format": "json",
                    "version": $version,
                    "command": "sync",
                    "subcommand": "status",
                    "timestamp": $timestamp
                },
                "success": true,
                "active": true,
                "session_id": $session_id,
                "injected_at": $injected_at,
                "injected_phase": $injected_phase,
                "task_count": $task_count,
                "task_ids": $task_ids,
                "phases": $phases,
                "state_file": $state_file
            }'
    else
        log_info "Active sync session found"
        echo ""

        echo "Session ID:    $session_id"
        echo "Injected at:   $injected_at"
        echo "Injected phase: $injected_phase"
        echo "Task count:    $task_count"
        echo "Task IDs:      $task_ids"

        # Show phase distribution if metadata exists
        if [[ "$phases_json" != "null" ]]; then
            local phases
            phases=$(jq -r '[.task_metadata[] | .phase // "unknown"] | group_by(.) | map("\(.[0]): \(length)") | join(", ")' "$STATE_FILE")
            echo "Phases:        $phases"
        fi

        echo ""
        echo "State file:    $STATE_FILE"
    fi
}

handle_clear() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log_info "No sync state to clear"
        exit 0
    fi

    rm -f "$STATE_FILE"
    log_info "Sync state cleared"

    # Also clean up sync directory if empty
    rmdir "$SYNC_DIR" 2>/dev/null || true
}

# =============================================================================
# Main
# =============================================================================
main() {
    # Need at least one argument
    if [[ $# -eq 0 ]]; then
        show_help
    fi

    # Parse global options first, then subcommand
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--format)
                FORMAT="$2"
                shift 2
                ;;
            --json)
                FORMAT="json"
                shift
                ;;
            --human)
                FORMAT="text"
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Restore positional arguments
    set -- "${args[@]}"

    # Resolve format (TTY-aware auto-detection)
    FORMAT=$(resolve_format "${FORMAT:-}")

    # Need at least one argument after parsing global options
    if [[ $# -eq 0 ]]; then
        show_help
    fi

    # Parse subcommand
    case "$1" in
        --inject|-i)
            handle_inject "$@"
            ;;
        --extract|-e)
            handle_extract "$@"
            ;;
        --status|-s)
            handle_status
            ;;
        --clear|-c)
            handle_clear
            ;;
        --help|-h)
            show_help
            ;;
        *)
            if [[ "$FORMAT" == "json" ]] && declare -f output_error >/dev/null 2>&1; then
                output_error "E_INPUT_INVALID" "Unknown subcommand: $1" 1 true "Use 'claude-todo sync --help' for usage"
            else
                log_error "Unknown subcommand: $1"
                echo ""
                echo "Use 'claude-todo sync --help' for usage"
            fi
            exit 1
            ;;
    esac
}

main "$@"
