#!/usr/bin/env bash
# jq-helpers.sh - Reusable jq wrapper functions for task operations
#
# LAYER: 1 (Core Infrastructure)
# DEPENDENCIES: none
# PROVIDES: get_task_field, get_tasks_by_status, get_task_by_id, array_to_json,
#           count_tasks_by_status, has_children, get_focus_task, get_task_count,
#           get_current_phase, get_all_task_ids, get_phase_tasks

#=== SOURCE GUARD ================================================
[[ -n "${_JQ_HELPERS_LOADED:-}" ]] && return 0
declare -r _JQ_HELPERS_LOADED=1

set -euo pipefail

# ============================================================================
# PUBLIC API
# ============================================================================

#######################################
# Extract a field from a task JSON object
# Arguments:
#   $1 - task_json: JSON string representing a task object
#   $2 - field_name: Name of the field to extract
# Outputs:
#   Writes field value to stdout (raw string, empty if field not found)
# Returns:
#   0 on success
#   1 on invalid arguments
#######################################
get_task_field() {
    local task_json="${1:-}"
    local field_name="${2:-}"

    if [[ -z "$task_json" ]]; then
        echo "Error: task_json required" >&2
        return 1
    fi

    if [[ -z "$field_name" ]]; then
        echo "Error: field_name required" >&2
        return 1
    fi

    echo "$task_json" | jq -r ".$field_name // empty"
}

#######################################
# Get tasks filtered by status
# Arguments:
#   $1 - status: Task status to filter by (pending|active|blocked|done)
#   $2 - todo_file: Path to todo.json file
# Outputs:
#   Writes JSON array of matching tasks to stdout
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
get_tasks_by_status() {
    local status="${1:-}"
    local todo_file="${2:-}"

    if [[ -z "$status" ]]; then
        echo "Error: status required" >&2
        return 1
    fi

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq --arg s "$status" '[.tasks[] | select(.status == $s)]' "$todo_file"
}

#######################################
# Get a single task by ID
# Arguments:
#   $1 - task_id: Task ID to find (e.g., T001)
#   $2 - todo_file: Path to todo.json file
# Outputs:
#   Writes task JSON object to stdout (empty if not found)
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
get_task_by_id() {
    local task_id="${1:-}"
    local todo_file="${2:-}"

    if [[ -z "$task_id" ]]; then
        echo "Error: task_id required" >&2
        return 1
    fi

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq --arg id "$task_id" '.tasks[] | select(.id == $id)' "$todo_file"
}

#######################################
# Convert bash array to JSON array
# Arguments:
#   $@ - Array elements to convert
# Outputs:
#   Writes JSON array to stdout
# Returns:
#   0 on success
# Notes:
#   Trims leading/trailing whitespace from each element
#######################################
array_to_json() {
    if [[ $# -eq 0 ]]; then
        echo "[]"
        return 0
    fi

    printf '%s\n' "$@" | jq -R . | jq -s 'map(gsub("^\\s+|\\s+$";""))'
}

#######################################
# Count tasks with given status
# Arguments:
#   $1 - status: Task status to count (pending|active|blocked|done)
#   $2 - todo_file: Path to todo.json file
# Outputs:
#   Writes integer count to stdout
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
count_tasks_by_status() {
    local status="${1:-}"
    local todo_file="${2:-}"

    if [[ -z "$status" ]]; then
        echo "Error: status required" >&2
        return 1
    fi

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq --arg s "$status" '[.tasks[] | select(.status == $s)] | length' "$todo_file"
}

#######################################
# Check if task has children
# Arguments:
#   $1 - task_id: Task ID to check (e.g., T001)
#   $2 - todo_file: Path to todo.json file
# Returns:
#   0 if task has children
#   1 if task has no children or on error
# Notes:
#   Checks for tasks where parentId matches the given task_id
#######################################
has_children() {
    local task_id="${1:-}"
    local todo_file="${2:-}"

    if [[ -z "$task_id" || -z "$todo_file" ]]; then
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        return 1
    fi

    local count
    count=$(jq --arg id "$task_id" '[.tasks[] | select(.parentId == $id)] | length' "$todo_file")
    [[ "$count" -gt 0 ]]
}

#######################################
# Get current focus task ID
# Arguments:
#   $1 - todo_file: Path to todo.json file
# Outputs:
#   Writes task ID to stdout (empty if no focus set)
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
get_focus_task() {
    local todo_file="${1:-}"

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq -r '.focus.currentTask // empty' "$todo_file"
}

#######################################
# Get total task count
# Arguments:
#   $1 - todo_file: Path to todo.json file
# Outputs:
#   Writes integer count to stdout
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
get_task_count() {
    local todo_file="${1:-}"

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq '.tasks | length' "$todo_file"
}

#######################################
# Get current project phase
# Arguments:
#   $1 - todo_file: Path to todo.json file
# Outputs:
#   Writes phase slug to stdout (empty if no phase set)
# Returns:
#   0 on success
#   1 on invalid arguments
#   2 on file not found
#######################################
get_current_phase() {
    local todo_file="${1:-}"

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq -r '.project.currentPhase // empty' "$todo_file"
}

#######################################
# Get all task IDs from todo file.
# Arguments:
#   $1 - Path to todo.json file
# Outputs:
#   Writes task IDs to stdout (one per line)
# Returns:
#   0 on success, 1 on invalid args, 2 on file not found
#######################################
get_all_task_ids() {
    local todo_file="$1"

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq -r '.tasks[].id' "$todo_file"
}

#######################################
# Get tasks filtered by phase.
# Arguments:
#   $1 - Phase slug (e.g., "core", "testing", "polish")
#   $2 - Path to todo.json file
# Outputs:
#   Writes JSON array of matching tasks to stdout
# Returns:
#   0 on success, 1 on invalid args, 2 on file not found
#######################################
get_phase_tasks() {
    local phase="$1"
    local todo_file="$2"

    if [[ -z "$phase" ]]; then
        echo "Error: phase required" >&2
        return 1
    fi

    if [[ -z "$todo_file" ]]; then
        echo "Error: todo_file required" >&2
        return 1
    fi

    if [[ ! -f "$todo_file" ]]; then
        echo "Error: File not found: $todo_file" >&2
        return 2
    fi

    jq --arg p "$phase" '[.tasks[] | select(.phase == $p)]' "$todo_file"
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f get_task_field
export -f get_tasks_by_status
export -f get_task_by_id
export -f array_to_json
export -f count_tasks_by_status
export -f has_children
export -f get_focus_task
export -f get_task_count
export -f get_current_phase
export -f get_all_task_ids
export -f get_phase_tasks
