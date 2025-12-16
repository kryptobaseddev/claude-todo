#!/usr/bin/env bash
# =============================================================================
# extract-todowrite.sh - Merge TodoWrite state back to claude-todo
# =============================================================================
# Parses TodoWrite JSON state, recovers task IDs from content prefix,
# and merges changes back to claude-todo. Used at session end.
#
# Research: T227 (todowrite-sync-research.md)
#
# Diff Detection:
#   - completed: Task marked completed in TodoWrite → mark done in claude-todo
#   - progressed: Task moved to in_progress → update notes
#   - new_tasks: Items without [T###] prefix → create in claude-todo
#   - removed: Injected task not in TodoWrite → log only (no delete)
#
# Usage:
#   claude-todo sync --extract [FILE]
#   ./extract-todowrite.sh <todowrite-state.json>
#
# Options:
#   --dry-run         Show what would change without modifying
#   --quiet, -q       Suppress info messages
#   --help, -h        Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source required libraries
source "$LIB_DIR/todowrite-integration.sh"

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
TODO_FILE=".claude/todo.json"
SYNC_DIR=".claude/sync"
STATE_FILE="${SYNC_DIR}/todowrite-session.json"
LOG_FILE=".claude/todo-log.json"
TODOWRITE_INPUT=""
DRY_RUN=false
QUIET=false

# =============================================================================
# Help
# =============================================================================
show_help() {
    cat << 'EOF'
extract-todowrite.sh - Merge TodoWrite state back to claude-todo

USAGE
    claude-todo sync --extract [FILE]
    ./extract-todowrite.sh <todowrite-state.json>

DESCRIPTION
    Parses TodoWrite JSON state from Claude's session, recovers task IDs
    from content prefixes, detects changes, and merges updates back to
    the persistent claude-todo system.

DIFF DETECTION
    completed    Task status=completed → mark done in claude-todo
    progressed   Task status=in_progress (was pending) → update to active
    new_tasks    No [T###] prefix → create new task in claude-todo
    removed      Injected ID missing → log only (no deletion)

CONFLICT RESOLUTION
    - claude-todo is authoritative for task existence
    - TodoWrite is authoritative for session progress
    - Warn but don't fail on conflicts

OPTIONS
    --dry-run         Show changes without modifying files
    --quiet, -q       Suppress info messages
    --help, -h        Show this help

INPUT FORMAT
    {
      "todos": [
        {"content": "[T001] Task", "status": "completed", "activeForm": "..."},
        {"content": "New task", "status": "pending", "activeForm": "..."}
      ]
    }

EXAMPLES
    # Extract from file
    claude-todo sync --extract /tmp/todowrite-state.json

    # Dry run to preview changes
    claude-todo sync --extract --dry-run /tmp/todowrite-state.json

EOF
    exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$TODOWRITE_INPUT" ]]; then
                    TODOWRITE_INPUT="$1"
                else
                    log_error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# =============================================================================
# Core Functions
# =============================================================================

# Parse task ID from content prefix: "[T001] ..." → "T001"
parse_task_id() {
    local content="$1"
    if [[ "$content" =~ ^\[T([0-9]+)\] ]]; then
        echo "T${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Strip prefixes from content to get clean title
strip_prefixes() {
    local content="$1"
    # Remove [T###], [!], [BLOCKED] prefixes
    echo "$content" | sed -E 's/^\[T[0-9]+\]\s*//' | sed -E 's/^\[!\]\s*//' | sed -E 's/^\[BLOCKED\]\s*//'
}

# Load session state (injected task IDs)
load_session_state() {
    if [[ -f "$STATE_FILE" ]]; then
        jq -r '.injected_tasks[]' "$STATE_FILE" 2>/dev/null || true
    fi
}

# Analyze TodoWrite state and detect changes
analyze_changes() {
    local todowrite_json="$1"
    local state_file="$2"

    # Get injected task IDs from session state
    local injected_ids=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r id; do
            [[ -n "$id" ]] && injected_ids+=("$id")
        done < <(jq -r '.injected_tasks[]' "$state_file" 2>/dev/null || true)
    fi

    # Track what we find in TodoWrite
    local found_ids=()
    local completed_ids=()
    local progressed_ids=()
    local new_tasks=()

    # Process each TodoWrite item
    while IFS= read -r item; do
        local content=$(echo "$item" | jq -r '.content // ""')
        local status=$(echo "$item" | jq -r '.status // "pending"')

        local task_id
        task_id=$(parse_task_id "$content")

        if [[ -n "$task_id" ]]; then
            found_ids+=("$task_id")

            if [[ "$status" == "completed" ]]; then
                completed_ids+=("$task_id")
            elif [[ "$status" == "in_progress" ]]; then
                progressed_ids+=("$task_id")
            fi
        else
            # New task (no ID prefix)
            local clean_title
            clean_title=$(strip_prefixes "$content")
            new_tasks+=("$clean_title")
        fi
    done < <(echo "$todowrite_json" | jq -c '.todos[]' 2>/dev/null || true)

    # Find removed IDs (in injected but not in found)
    local removed_ids=()
    for id in "${injected_ids[@]}"; do
        local found=false
        for fid in "${found_ids[@]}"; do
            [[ "$id" == "$fid" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && removed_ids+=("$id")
    done

    # Output as JSON
    jq -n \
        --argjson completed "$(printf '%s\n' "${completed_ids[@]}" | jq -R . | jq -s .)" \
        --argjson progressed "$(printf '%s\n' "${progressed_ids[@]}" | jq -R . | jq -s .)" \
        --argjson new_tasks "$(printf '%s\n' "${new_tasks[@]}" | jq -R . | jq -s .)" \
        --argjson removed "$(printf '%s\n' "${removed_ids[@]}" | jq -R . | jq -s .)" \
        '{completed: $completed, progressed: $progressed, new_tasks: $new_tasks, removed: $removed}'
}

# Apply changes to claude-todo
apply_changes() {
    local changes_json="$1"
    local todo_file="$2"
    local dry_run="$3"

    local completed=$(echo "$changes_json" | jq -r '.completed[]' 2>/dev/null || true)
    local progressed=$(echo "$changes_json" | jq -r '.progressed[]' 2>/dev/null || true)
    local new_tasks=$(echo "$changes_json" | jq -r '.new_tasks[]' 2>/dev/null || true)
    local removed=$(echo "$changes_json" | jq -r '.removed[]' 2>/dev/null || true)

    local changes_made=0

    # Phase inheritance for new tasks (T258)
    # Strategy: focus task phase → most active phase → project.currentPhase (via add-task.sh)
    local inherit_phase=""
    local phase_source=""

    # 1. Try focused task's phase from session metadata
    if [[ -f "$STATE_FILE" ]]; then
        local focus_id
        focus_id=$(jq -r '.injected_tasks[0] // ""' "$STATE_FILE" 2>/dev/null || echo "")

        if [[ -n "$focus_id" ]]; then
            inherit_phase=$(jq -r ".task_metadata.\"$focus_id\".phase // \"\"" "$STATE_FILE" 2>/dev/null || echo "")
            if [[ -n "$inherit_phase" && "$inherit_phase" != "null" ]]; then
                phase_source="focus"
            fi
        fi
    fi

    # 2. Fallback to most active phase (phase with most non-done tasks)
    if [[ -z "$inherit_phase" || "$inherit_phase" == "null" ]]; then
        inherit_phase=$(jq -r '
            [.tasks[] | select(.status != "done") | .phase // empty] |
            group_by(.) |
            map({phase: .[0], count: length}) |
            sort_by(-.count) |
            .[0].phase // ""
        ' "$todo_file" 2>/dev/null || echo "")

        if [[ -n "$inherit_phase" && "$inherit_phase" != "null" ]]; then
            phase_source="most-active"
        else
            inherit_phase=""
        fi
    fi

    # 3. Final fallback to project.currentPhase handled by add-task.sh

    # Process completed tasks
    while IFS= read -r task_id; do
        [[ -z "$task_id" ]] && continue

        # Check if task exists and isn't already done
        local current_status
        current_status=$(jq -r ".tasks[] | select(.id == \"$task_id\") | .status" "$todo_file" 2>/dev/null || echo "")

        if [[ -z "$current_status" ]]; then
            log_warn "Task $task_id not found in claude-todo (may have been deleted)"
            continue
        fi

        if [[ "$current_status" == "done" ]]; then
            log_info "Task $task_id already done (idempotent)"
            continue
        fi

        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY RUN] Would complete: $task_id"
        else
            # Use complete-task.sh for proper completion
            "$SCRIPT_DIR/complete-task.sh" "$task_id" --notes "Completed via TodoWrite session sync" --skip-archive >/dev/null 2>&1 || {
                log_warn "Failed to complete $task_id"
                continue
            }
            log_info "Completed: $task_id"
        fi
        ((changes_made++))
    done <<< "$completed"

    # Process progressed tasks (in_progress → active)
    while IFS= read -r task_id; do
        [[ -z "$task_id" ]] && continue

        local current_status
        current_status=$(jq -r ".tasks[] | select(.id == \"$task_id\") | .status" "$todo_file" 2>/dev/null || echo "")

        if [[ -z "$current_status" ]]; then
            log_warn "Task $task_id not found"
            continue
        fi

        # Only update if was pending/blocked, now progressed
        if [[ "$current_status" == "pending" || "$current_status" == "blocked" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY RUN] Would mark active: $task_id"
            else
                "$SCRIPT_DIR/update-task.sh" "$task_id" --status active --notes "Progressed during TodoWrite session" >/dev/null 2>&1 || {
                    log_warn "Failed to update $task_id"
                    continue
                }
                log_info "Marked active: $task_id"
            fi
            ((changes_made++))
        fi
    done <<< "$progressed"

    # Process new tasks
    # Phase inheritance strategy:
    # 1. Use focused task's phase from session metadata (if available)
    # 2. Fall back to project.currentPhase (automatic via add-task.sh)
    # 3. Fall back to config.defaults.phase (automatic via add-task.sh)
    while IFS= read -r title; do
        [[ -z "$title" ]] && continue

        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY RUN] Would create: $title"
        else
            local new_id
            local add_args=(
                "$title"
                --labels "session-created"
                --description "Created during TodoWrite session"
                --quiet
            )

            # Add phase flag if we have phase metadata from session
            if [[ -n "$inherit_phase" ]]; then
                add_args+=(--phase "$inherit_phase")
            fi

            new_id=$("$SCRIPT_DIR/add-task.sh" "${add_args[@]}" 2>/dev/null || echo "")
            if [[ -n "$new_id" ]]; then
                if [[ -n "$inherit_phase" ]]; then
                    log_info "Created: $new_id - $title (phase: $inherit_phase, source: $phase_source)"
                else
                    log_info "Created: $new_id - $title (no phase inherited)"
                fi
            else
                log_warn "Failed to create task: $title"
            fi
        fi
        ((changes_made++))
    done <<< "$new_tasks"

    # Log removed tasks (no action, just informational)
    while IFS= read -r task_id; do
        [[ -z "$task_id" ]] && continue
        log_info "Removed from session (no action): $task_id"
    done <<< "$removed"

    echo "$changes_made"
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    # Validate inputs
    if [[ -z "$TODOWRITE_INPUT" ]]; then
        log_error "TodoWrite state file required"
        echo "Usage: extract-todowrite.sh <todowrite-state.json>"
        exit 1
    fi

    if [[ ! -f "$TODOWRITE_INPUT" ]]; then
        log_error "File not found: $TODOWRITE_INPUT"
        exit 1
    fi

    if [[ ! -f "$TODO_FILE" ]]; then
        log_error "todo.json not found at $TODO_FILE"
        exit 1
    fi

    # Load TodoWrite state
    local todowrite_json
    todowrite_json=$(cat "$TODOWRITE_INPUT")

    # Validate JSON
    if ! echo "$todowrite_json" | jq . >/dev/null 2>&1; then
        log_error "Invalid JSON in $TODOWRITE_INPUT"
        exit 1
    fi

    log_info "Analyzing TodoWrite state..."

    # Analyze changes
    local changes_json
    changes_json=$(analyze_changes "$todowrite_json" "$STATE_FILE")

    # Show summary
    local completed_count=$(echo "$changes_json" | jq '.completed | length')
    local progressed_count=$(echo "$changes_json" | jq '.progressed | length')
    local new_count=$(echo "$changes_json" | jq '.new_tasks | length')
    local removed_count=$(echo "$changes_json" | jq '.removed | length')

    log_info "Changes detected: $completed_count completed, $progressed_count progressed, $new_count new, $removed_count removed"

    if [[ "$completed_count" -eq 0 && "$progressed_count" -eq 0 && "$new_count" -eq 0 ]]; then
        log_info "No changes to apply"
        exit 0
    fi

    # Apply changes
    local changes_made
    changes_made=$(apply_changes "$changes_json" "$TODO_FILE" "$DRY_RUN")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. Would apply $changes_made changes."
    else
        log_info "Applied $changes_made changes"

        # Clean up session state file
        if [[ -f "$STATE_FILE" ]]; then
            rm -f "$STATE_FILE"
            log_info "Session state cleared"
        fi
    fi
}

main "$@"
