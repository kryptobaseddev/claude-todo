#!/usr/bin/env bash
# lib/hierarchy.sh - Hierarchy validation and helper functions for claude-todo
#
# Provides validation functions for the Epic → Task → Subtask hierarchy:
# - Parent existence validation
# - Maximum depth enforcement (3 levels)
# - Maximum siblings enforcement (7 children)
# - Parent type validation (subtask cannot have children)
# - Circular reference detection
# - Orphan detection
#
# Version: 0.17.0
# Part of: Hierarchy Enhancement (v0.17.0)
# Spec: HIERARCHY-ENHANCEMENT-SPEC.md, LLM-TASK-ID-SYSTEM-DESIGN-SPEC.md
#
# Usage:
#   source "${LIB_DIR}/hierarchy.sh"
#   validate_parent_exists "T001" "$TODO_FILE" || exit $EXIT_PARENT_NOT_FOUND

set -euo pipefail

# ============================================================================
# CONSTANTS (guarded to prevent readonly collision on re-source)
# ============================================================================

# Maximum hierarchy depth (epic=0, task=1, subtask=2)
if [[ -z "${MAX_HIERARCHY_DEPTH:-}" ]]; then
    readonly MAX_HIERARCHY_DEPTH=3
fi

# Maximum children per parent
if [[ -z "${MAX_SIBLINGS:-}" ]]; then
    readonly MAX_SIBLINGS=7
fi

# Valid task types
if [[ -z "${VALID_TASK_TYPES:-}" ]]; then
    readonly VALID_TASK_TYPES="epic task subtask"
fi

# ============================================================================
# DEPENDENCIES
# ============================================================================

_HIERARCHY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source exit codes if not already loaded
if [[ -z "${EXIT_PARENT_NOT_FOUND:-}" ]]; then
    if [[ -f "$_HIERARCHY_LIB_DIR/exit-codes.sh" ]]; then
        # shellcheck source=lib/exit-codes.sh
        source "$_HIERARCHY_LIB_DIR/exit-codes.sh"
    fi
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# get_task_by_id - Get task JSON by ID
#
# Args:
#   $1 - Task ID (e.g., "T001")
#   $2 - Path to todo.json
#
# Returns: Task JSON object or empty string if not found
get_task_by_id() {
    local task_id="$1"
    local todo_file="$2"

    jq -r --arg id "$task_id" '.tasks[] | select(.id == $id)' "$todo_file" 2>/dev/null || echo ""
}

# get_task_type - Get the type of a task
#
# Args:
#   $1 - Task ID
#   $2 - Path to todo.json
#
# Returns: Task type (epic|task|subtask) or "task" if not set
get_task_type() {
    local task_id="$1"
    local todo_file="$2"

    local task_type
    task_type=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .type // "task"' "$todo_file" 2>/dev/null)
    echo "${task_type:-task}"
}

# get_task_parent - Get the parentId of a task
#
# Args:
#   $1 - Task ID
#   $2 - Path to todo.json
#
# Returns: Parent task ID or "null" if no parent
get_task_parent() {
    local task_id="$1"
    local todo_file="$2"

    local parent_id
    parent_id=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .parentId // "null"' "$todo_file" 2>/dev/null)
    echo "${parent_id:-null}"
}

# get_task_depth - Calculate hierarchy depth of a task
#
# Depth: 0=root, 1=child of root, 2=grandchild, etc.
# Epic without parent = 0
# Task under epic = 1
# Subtask under task = 2
#
# Args:
#   $1 - Task ID
#   $2 - Path to todo.json
#
# Returns: Numeric depth (0-based)
get_task_depth() {
    local task_id="$1"
    local todo_file="$2"
    local depth=0
    local current_id="$task_id"
    local visited=""

    while true; do
        local parent_id
        parent_id=$(get_task_parent "$current_id" "$todo_file")

        if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
            break
        fi

        # Prevent infinite loop from circular references
        if [[ "$visited" == *"$parent_id"* ]]; then
            echo "-1"  # Signal circular reference
            return 1
        fi
        visited="$visited $parent_id"

        depth=$((depth + 1))
        current_id="$parent_id"

        # Safety limit
        if [[ $depth -gt 10 ]]; then
            echo "-1"
            return 1
        fi
    done

    echo "$depth"
}

# get_parent_chain - Get list of ancestor task IDs
#
# Args:
#   $1 - Task ID
#   $2 - Path to todo.json
#
# Returns: Space-separated list of ancestor IDs (immediate parent first)
get_parent_chain() {
    local task_id="$1"
    local todo_file="$2"
    local chain=""
    local current_id="$task_id"
    local visited=""

    while true; do
        local parent_id
        parent_id=$(get_task_parent "$current_id" "$todo_file")

        if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
            break
        fi

        # Prevent infinite loop
        if [[ "$visited" == *"$parent_id"* ]]; then
            break
        fi
        visited="$visited $parent_id"

        chain="$chain $parent_id"
        current_id="$parent_id"

        # Safety limit
        if [[ ${#chain} -gt 100 ]]; then
            break
        fi
    done

    echo "${chain# }"  # Trim leading space
}

# get_children - Get direct children of a task
#
# Args:
#   $1 - Task ID (parent)
#   $2 - Path to todo.json
#
# Returns: Space-separated list of child task IDs
get_children() {
    local parent_id="$1"
    local todo_file="$2"

    local children
    children=$(jq -r --arg pid "$parent_id" '.tasks[] | select(.parentId == $pid) | .id' "$todo_file" 2>/dev/null | tr '\n' ' ')
    echo "${children% }"  # Trim trailing space
}

# count_siblings - Count tasks with the same parent
#
# Args:
#   $1 - Parent ID (use "null" for root-level tasks)
#   $2 - Path to todo.json
#
# Returns: Numeric count
count_siblings() {
    local parent_id="$1"
    local todo_file="$2"

    if [[ "$parent_id" == "null" ]]; then
        jq '[.tasks[] | select(.parentId == null or .parentId == "null")] | length' "$todo_file" 2>/dev/null || echo "0"
    else
        jq --arg pid "$parent_id" '[.tasks[] | select(.parentId == $pid)] | length' "$todo_file" 2>/dev/null || echo "0"
    fi
}

# get_descendants - Get all descendants of a task (recursive)
#
# Args:
#   $1 - Task ID (ancestor)
#   $2 - Path to todo.json
#
# Returns: Space-separated list of all descendant task IDs
get_descendants() {
    local ancestor_id="$1"
    local todo_file="$2"
    local descendants=""

    local children
    children=$(get_children "$ancestor_id" "$todo_file")

    for child in $children; do
        descendants="$descendants $child"
        local grandchildren
        grandchildren=$(get_descendants "$child" "$todo_file")
        if [[ -n "$grandchildren" ]]; then
            descendants="$descendants $grandchildren"
        fi
    done

    echo "${descendants# }"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# validate_parent_exists - Check if parent task exists
#
# Args:
#   $1 - Parent ID to validate
#   $2 - Path to todo.json
#
# Returns: 0 if valid, EXIT_PARENT_NOT_FOUND if invalid
validate_parent_exists() {
    local parent_id="$1"
    local todo_file="$2"

    # Null parent is always valid (root-level task)
    if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
        return 0
    fi

    # Check if parent exists
    local parent_task
    parent_task=$(get_task_by_id "$parent_id" "$todo_file")

    if [[ -z "$parent_task" ]]; then
        return "${EXIT_PARENT_NOT_FOUND:-10}"
    fi

    return 0
}

# validate_max_depth - Check if adding child would exceed max depth
#
# Args:
#   $1 - Parent ID (where new task would be added)
#   $2 - Path to todo.json
#
# Returns: 0 if valid, EXIT_DEPTH_EXCEEDED if too deep
validate_max_depth() {
    local parent_id="$1"
    local todo_file="$2"

    # Root-level is always valid
    if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
        return 0
    fi

    local parent_depth
    parent_depth=$(get_task_depth "$parent_id" "$todo_file")

    # Parent at depth 2 means child would be at depth 3 (max exceeded)
    if [[ "$parent_depth" -ge $((MAX_HIERARCHY_DEPTH - 1)) ]]; then
        return "${EXIT_DEPTH_EXCEEDED:-11}"
    fi

    return 0
}

# validate_max_siblings - Check if parent has room for another child
#
# Args:
#   $1 - Parent ID
#   $2 - Path to todo.json
#
# Returns: 0 if valid, EXIT_SIBLING_LIMIT if at limit
validate_max_siblings() {
    local parent_id="$1"
    local todo_file="$2"

    local sibling_count
    sibling_count=$(count_siblings "$parent_id" "$todo_file")

    if [[ "$sibling_count" -ge "$MAX_SIBLINGS" ]]; then
        return "${EXIT_SIBLING_LIMIT:-12}"
    fi

    return 0
}

# validate_parent_type - Check if parent can have children
#
# Subtasks cannot have children (would create depth > 3)
#
# Args:
#   $1 - Parent ID
#   $2 - Path to todo.json
#
# Returns: 0 if valid, EXIT_INVALID_PARENT_TYPE if subtask
validate_parent_type() {
    local parent_id="$1"
    local todo_file="$2"

    # Root-level is always valid
    if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
        return 0
    fi

    local parent_type
    parent_type=$(get_task_type "$parent_id" "$todo_file")

    if [[ "$parent_type" == "subtask" ]]; then
        return "${EXIT_INVALID_PARENT_TYPE:-13}"
    fi

    return 0
}

# validate_no_circular_reference - Check if operation would create a cycle
#
# Args:
#   $1 - Task ID being moved/created
#   $2 - Proposed parent ID
#   $3 - Path to todo.json
#
# Returns: 0 if valid, EXIT_CIRCULAR_REFERENCE if would create cycle
validate_no_circular_reference() {
    local task_id="$1"
    local new_parent_id="$2"
    local todo_file="$3"

    # Root-level is always valid
    if [[ "$new_parent_id" == "null" || -z "$new_parent_id" ]]; then
        return 0
    fi

    # Cannot be your own parent
    if [[ "$task_id" == "$new_parent_id" ]]; then
        return "${EXIT_CIRCULAR_REFERENCE:-14}"
    fi

    # Check if new_parent is a descendant of task_id
    local descendants
    descendants=$(get_descendants "$task_id" "$todo_file")

    for desc in $descendants; do
        if [[ "$desc" == "$new_parent_id" ]]; then
            return "${EXIT_CIRCULAR_REFERENCE:-14}"
        fi
    done

    return 0
}

# validate_hierarchy - Run all hierarchy validations for a new child
#
# Args:
#   $1 - Parent ID (where new task would be added)
#   $2 - Path to todo.json
#   $3 - (Optional) Task ID if reparenting
#
# Returns: First failing exit code, or 0 if all pass
validate_hierarchy() {
    local parent_id="$1"
    local todo_file="$2"
    local task_id="${3:-}"

    # Validate parent exists
    if ! validate_parent_exists "$parent_id" "$todo_file"; then
        return "${EXIT_PARENT_NOT_FOUND:-10}"
    fi

    # Validate depth
    if ! validate_max_depth "$parent_id" "$todo_file"; then
        return "${EXIT_DEPTH_EXCEEDED:-11}"
    fi

    # Validate siblings (only for new children, not reparenting)
    if [[ -z "$task_id" ]] && ! validate_max_siblings "$parent_id" "$todo_file"; then
        return "${EXIT_SIBLING_LIMIT:-12}"
    fi

    # Validate parent type
    if ! validate_parent_type "$parent_id" "$todo_file"; then
        return "${EXIT_INVALID_PARENT_TYPE:-13}"
    fi

    # Validate no circular reference (for reparenting)
    if [[ -n "$task_id" ]] && ! validate_no_circular_reference "$task_id" "$parent_id" "$todo_file"; then
        return "${EXIT_CIRCULAR_REFERENCE:-14}"
    fi

    return 0
}

# detect_orphans - Find tasks with invalid parentId references
#
# Args:
#   $1 - Path to todo.json
#
# Returns: Space-separated list of orphan task IDs, or empty if none
detect_orphans() {
    local todo_file="$1"
    local orphans=""

    # Get all task IDs
    local all_ids
    all_ids=$(jq -r '.tasks[].id' "$todo_file" 2>/dev/null)

    # Check each task's parentId
    for task_id in $all_ids; do
        local parent_id
        parent_id=$(get_task_parent "$task_id" "$todo_file")

        if [[ "$parent_id" != "null" && -n "$parent_id" ]]; then
            # Check if parent exists
            if ! echo "$all_ids" | grep -qw "$parent_id"; then
                orphans="$orphans $task_id"
            fi
        fi
    done

    echo "${orphans# }"
}

# infer_task_type - Infer type based on hierarchy position
#
# Args:
#   $1 - Parent ID (null for root)
#   $2 - Path to todo.json (optional, for checking parent's type)
#
# Returns: Suggested type (epic|task|subtask)
infer_task_type() {
    local parent_id="$1"
    local todo_file="${2:-}"

    # No parent = could be epic or task
    if [[ "$parent_id" == "null" || -z "$parent_id" ]]; then
        echo "task"  # Default to task for root-level
        return
    fi

    # Has parent - infer based on parent's type
    if [[ -n "$todo_file" && -f "$todo_file" ]]; then
        local parent_type
        parent_type=$(get_task_type "$parent_id" "$todo_file")

        case "$parent_type" in
            epic) echo "task" ;;
            task) echo "subtask" ;;
            *) echo "task" ;;
        esac
    else
        echo "task"
    fi
}

# validate_task_type - Check if type is valid enum value
#
# Args:
#   $1 - Type to validate
#
# Returns: 0 if valid, 1 if invalid
validate_task_type() {
    local task_type="$1"

    case "$task_type" in
        epic|task|subtask) return 0 ;;
        *) return 1 ;;
    esac
}

# validate_task_size - Check if size is valid enum value
#
# Args:
#   $1 - Size to validate
#
# Returns: 0 if valid, 1 if invalid
validate_task_size() {
    local size="$1"

    case "$size" in
        small|medium|large|""|null) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# EXPORTS
# ============================================================================

export MAX_HIERARCHY_DEPTH
export MAX_SIBLINGS
export VALID_TASK_TYPES

export -f get_task_by_id
export -f get_task_type
export -f get_task_parent
export -f get_task_depth
export -f get_parent_chain
export -f get_children
export -f count_siblings
export -f get_descendants

export -f validate_parent_exists
export -f validate_max_depth
export -f validate_max_siblings
export -f validate_parent_type
export -f validate_no_circular_reference
export -f validate_hierarchy
export -f detect_orphans
export -f infer_task_type
export -f validate_task_type
export -f validate_task_size
