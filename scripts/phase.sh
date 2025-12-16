#!/usr/bin/env bash
# phase.sh - Project-level phase management for claude-todo
# Usage: claude-todo phase <subcommand> [args]
# Subcommands: show, set, start, complete, advance, list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source libraries
source "$LIB_DIR/platform-compat.sh"
source "$LIB_DIR/file-ops.sh"
source "$LIB_DIR/phase-tracking.sh"
source "$LIB_DIR/logging.sh"

# Globals
TODO_FILE="${CLAUDE_TODO_DIR:-.claude}/todo.json"

# ============================================================================
# SUBCOMMANDS
# ============================================================================

# Show current phase
cmd_show() {
    local current_phase
    current_phase=$(get_current_phase "$TODO_FILE")

    if [[ -z "$current_phase" || "$current_phase" == "null" ]]; then
        echo "No current phase set"
        return 1
    fi

    local phase_info
    phase_info=$(get_phase "$current_phase" "$TODO_FILE")

    echo "Current Phase: $current_phase"
    echo "$phase_info" | jq -r '"  Name: \(.name)\n  Status: \(.status)\n  Started: \(.startedAt // "not started")"'
}

# Set current phase
cmd_set() {
    local slug="$1"
    local old_phase

    old_phase=$(get_current_phase "$TODO_FILE")

    if set_current_phase "$slug" "$TODO_FILE"; then
        echo "Phase set to: $slug"
        log_phase_changed "${old_phase:-none}" "$slug"
    else
        return 1
    fi
}

# Start a phase (pending → active)
cmd_start() {
    local slug="$1"

    if start_phase "$slug" "$TODO_FILE"; then
        echo "Started phase: $slug"
        log_phase_started "$slug"
    else
        return 1
    fi
}

# Complete a phase (active → completed)
cmd_complete() {
    local slug="$1"
    local started_at

    started_at=$(jq -r --arg slug "$slug" '.project.phases[$slug].startedAt // null' "$TODO_FILE")

    if complete_phase "$slug" "$TODO_FILE"; then
        echo "Completed phase: $slug"
        log_phase_completed "$slug" "$started_at"
    else
        return 1
    fi
}

# Advance to next phase
cmd_advance() {
    local current
    local current_started

    current=$(get_current_phase "$TODO_FILE")
    current_started=$(jq -r --arg slug "$current" '.project.phases[$slug].startedAt // null' "$TODO_FILE")

    local result
    result=$(advance_phase "$TODO_FILE")

    if [[ $? -eq 0 ]]; then
        echo "$result"
        log_phase_completed "$current" "$current_started"
        local new_phase
        new_phase=$(get_current_phase "$TODO_FILE")
        log_phase_started "$new_phase"
    else
        return 1
    fi
}

# List all phases
cmd_list() {
    echo "Project Phases:"
    echo "==============="

    local current_phase
    current_phase=$(get_current_phase "$TODO_FILE")

    jq -r --arg current "$current_phase" '
        .project.phases | to_entries | sort_by(.value.order) | .[] |
        (if .key == $current then "★ " else "  " end) +
        "[\(.value.order)] \(.key): \(.value.name) (\(.value.status))"
    ' "$TODO_FILE"
}

# ============================================================================
# USAGE
# ============================================================================

usage() {
    cat <<EOF
Usage: claude-todo phase <subcommand> [args]

Subcommands:
  show              Show current project phase
  set <slug>        Set current phase (doesn't change status)
  start <slug>      Start a phase (pending → active)
  complete <slug>   Complete a phase (active → completed)
  advance           Complete current phase and start next
  list              List all phases with status

Examples:
  claude-todo phase show
  claude-todo phase set core
  claude-todo phase start polish
  claude-todo phase advance
EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        show)
            cmd_show
            ;;
        set)
            [[ $# -lt 1 ]] && { echo "ERROR: phase slug required"; exit 1; }
            cmd_set "$1"
            ;;
        start)
            [[ $# -lt 1 ]] && { echo "ERROR: phase slug required"; exit 1; }
            cmd_start "$1"
            ;;
        complete)
            [[ $# -lt 1 ]] && { echo "ERROR: phase slug required"; exit 1; }
            cmd_complete "$1"
            ;;
        advance)
            cmd_advance
            ;;
        list)
            cmd_list
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "ERROR: Unknown subcommand: $subcommand"
            usage
            exit 1
            ;;
    esac
}

main "$@"
