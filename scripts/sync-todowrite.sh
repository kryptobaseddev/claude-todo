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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# =============================================================================
# Configuration
# =============================================================================
SYNC_DIR=".claude/sync"
STATE_FILE="${SYNC_DIR}/todowrite-session.json"

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
    --dry-run         Preview changes without applying
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
        log_info "No active sync session"
        echo ""
        echo "State file: $STATE_FILE (not found)"
        exit 0
    fi

    log_info "Active sync session found"
    echo ""

    local session_id=$(jq -r '.session_id // "unknown"' "$STATE_FILE")
    local injected_at=$(jq -r '.injected_at // "unknown"' "$STATE_FILE")
    local task_count=$(jq '.injected_tasks | length' "$STATE_FILE")
    local task_ids=$(jq -r '.injected_tasks | join(", ")' "$STATE_FILE")

    echo "Session ID:    $session_id"
    echo "Injected at:   $injected_at"
    echo "Task count:    $task_count"
    echo "Task IDs:      $task_ids"

    # Show phase distribution if metadata exists
    if jq -e '.task_metadata' "$STATE_FILE" >/dev/null 2>&1; then
        local phases
        phases=$(jq -r '[.task_metadata[] | .phase // "unknown"] | group_by(.) | map("\(.[0]): \(length)") | join(", ")' "$STATE_FILE")
        echo "Phases:        $phases"
    fi

    echo ""
    echo "State file:    $STATE_FILE"
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
            log_error "Unknown subcommand: $1"
            echo ""
            echo "Use 'claude-todo sync --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
