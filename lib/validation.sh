#!/usr/bin/env bash
# validation.sh - Core validation library for claude-todo system
# Provides schema validation and anti-hallucination checks

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================

readonly VALID_STATUSES=("pending" "active" "done" "blocked")
readonly VALID_OPERATIONS=("create" "update" "complete" "archive" "restore" "delete" "validate" "backup")

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_SCHEMA_ERROR=1
readonly EXIT_SEMANTIC_ERROR=2
readonly EXIT_BOTH_ERRORS=3

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get current timestamp in ISO 8601 format
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Convert ISO 8601 timestamp to Unix epoch
timestamp_to_epoch() {
    local timestamp="$1"
    date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "0"
}

# ============================================================================
# JSON SYNTAX VALIDATION
# ============================================================================

# Validate JSON syntax using jq
# Args: $1 = file path
# Returns: 0 if valid, 1 if invalid
validate_json_syntax() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    if ! jq empty "$file" 2>/dev/null; then
        echo "ERROR: Invalid JSON syntax in file: $file" >&2
        echo "Details:" >&2
        jq empty "$file" 2>&1 | head -10 >&2
        echo "Fix: Check for missing commas, brackets, or quotes" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# SCHEMA VALIDATION
# ============================================================================

# Validate JSON against schema
# Args: $1 = file path, $2 = schema type (todo|archive|config|log)
# Returns: 0 if valid, 1 if invalid
validate_schema() {
    local file="$1"
    local schema_type="$2"
    local schema_file

    # Determine schema file location
    if [[ -n "${CLAUDE_TODO_HOME:-}" ]]; then
        schema_file="$CLAUDE_TODO_HOME/schemas/todo-${schema_type}.schema.json"
    elif [[ -f "$HOME/.claude-todo/schemas/todo-${schema_type}.schema.json" ]]; then
        schema_file="$HOME/.claude-todo/schemas/todo-${schema_type}.schema.json"
    else
        schema_file="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/schemas/todo-${schema_type}.schema.json"
    fi

    if [[ ! -f "$schema_file" ]]; then
        echo "WARNING: Schema file not found: $schema_file" >&2
        echo "Skipping schema validation" >&2
        return 0
    fi

    # First check JSON syntax
    if ! validate_json_syntax "$file"; then
        return 1
    fi

    # Try ajv if available
    if command_exists ajv; then
        if ! ajv validate -s "$schema_file" -d "$file" 2>&1; then
            echo "ERROR: Schema validation failed for $file" >&2
            echo "Fix: Ensure file matches schema: $schema_file" >&2
            return 1
        fi
        return 0
    fi

    # Fallback to jq-based validation
    echo "INFO: Using jq-based schema validation (install ajv for better validation)" >&2
    _validate_schema_jq "$file" "$schema_type"
}

# JQ-based schema validation fallback
# Args: $1 = file path, $2 = schema type
_validate_schema_jq() {
    local file="$1"
    local schema_type="$2"
    local errors=0

    case "$schema_type" in
        "todo")
            # Validate todo.json structure
            if ! jq -e '.tasks | type == "array"' "$file" >/dev/null 2>&1; then
                echo "ERROR: Missing or invalid 'tasks' array" >&2
                ((errors++))
            fi

            # Check each task has required fields
            local task_count
            task_count=$(jq '.tasks | length' "$file")
            for ((i=0; i<task_count; i++)); do
                if ! jq -e ".tasks[$i] | has(\"content\") and has(\"status\") and has(\"activeForm\")" "$file" >/dev/null 2>&1; then
                    echo "ERROR: Task at index $i missing required fields (content, status, activeForm)" >&2
                    ((errors++))
                fi
            done
            ;;

        "archive")
            # Validate archive structure
            if ! jq -e '.archived_tasks | type == "array"' "$file" >/dev/null 2>&1; then
                echo "ERROR: Missing or invalid 'archived_tasks' array" >&2
                ((errors++))
            fi
            ;;

        "config")
            # Validate config structure
            if ! jq -e 'has("archive") and has("validation") and has("logging")' "$file" >/dev/null 2>&1; then
                echo "ERROR: Missing required config sections (archive, validation, logging)" >&2
                ((errors++))
            fi
            ;;

        "log")
            # Validate log structure
            if ! jq -e '.entries | type == "array"' "$file" >/dev/null 2>&1; then
                echo "ERROR: Missing or invalid 'entries' array" >&2
                ((errors++))
            fi
            ;;

        *)
            echo "ERROR: Unknown schema type: $schema_type" >&2
            return 1
            ;;
    esac

    if [[ $errors -gt 0 ]]; then
        echo "Fix: Ensure file structure matches schema requirements" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# TASK VALIDATION
# ============================================================================

# Validate a single task object
# Args: $1 = file path, $2 = task index
# Returns: 0 if valid, 1 if invalid
validate_task() {
    local file="$1"
    local task_idx="$2"
    local errors=0

    # Check task exists
    if ! jq -e ".tasks[$task_idx]" "$file" >/dev/null 2>&1; then
        echo "ERROR: Task at index $task_idx does not exist" >&2
        return 1
    fi

    # 1. Check required fields exist
    local content status activeForm
    content=$(jq -r ".tasks[$task_idx].content // empty" "$file")
    status=$(jq -r ".tasks[$task_idx].status // empty" "$file")
    activeForm=$(jq -r ".tasks[$task_idx].activeForm // empty" "$file")

    if [[ -z "$content" ]]; then
        echo "ERROR: Task $task_idx missing 'content' field" >&2
        echo "Fix: Add content field with task description" >&2
        ((errors++))
    fi

    if [[ -z "$status" ]]; then
        echo "ERROR: Task $task_idx missing 'status' field" >&2
        echo "Fix: Add status field (pending|active|done|blocked)" >&2
        ((errors++))
    fi

    if [[ -z "$activeForm" ]]; then
        echo "ERROR: Task $task_idx missing 'activeForm' field" >&2
        echo "Fix: Add activeForm field with present continuous form" >&2
        ((errors++))
    fi

    # 2. Validate status enum
    if [[ -n "$status" ]]; then
        local valid_status=false
        for valid in "${VALID_STATUSES[@]}"; do
            if [[ "$status" == "$valid" ]]; then
                valid_status=true
                break
            fi
        done

        if [[ "$valid_status" == "false" ]]; then
            echo "ERROR: Task $task_idx has invalid status: '$status'" >&2
            echo "Fix: Status must be one of: ${VALID_STATUSES[*]}" >&2
            ((errors++))
        fi
    fi

    # 3. Check content/activeForm pairing
    if [[ -n "$content" && -n "$activeForm" ]]; then
        if [[ "$content" == "$activeForm" ]]; then
            echo "WARNING: Task $task_idx has identical content and activeForm" >&2
            echo "Fix: activeForm should be present continuous (e.g., 'Implementing auth')" >&2
        fi
    fi

    # 4. Check timestamp fields if present
    local created_at completed_at
    created_at=$(jq -r ".tasks[$task_idx].created_at // empty" "$file")
    completed_at=$(jq -r ".tasks[$task_idx].completed_at // empty" "$file")

    if [[ -n "$created_at" ]]; then
        if ! check_timestamp_sanity "$created_at" ""; then
            echo "ERROR: Task $task_idx has invalid created_at timestamp" >&2
            ((errors++))
        fi
    fi

    if [[ -n "$completed_at" ]]; then
        if [[ -n "$created_at" ]]; then
            if ! check_timestamp_sanity "$created_at" "$completed_at"; then
                echo "ERROR: Task $task_idx has completed_at before created_at" >&2
                ((errors++))
            fi
        fi
    fi

    # 5. Check ID format if present
    local task_id
    task_id=$(jq -r ".tasks[$task_idx].id // empty" "$file")
    if [[ -n "$task_id" ]]; then
        if [[ ! "$task_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "ERROR: Task $task_idx has invalid ID format: '$task_id'" >&2
            echo "Fix: ID should contain only alphanumeric, dash, and underscore" >&2
            ((errors++))
        fi
    fi

    [[ $errors -eq 0 ]]
}

# ============================================================================
# ID UNIQUENESS CHECK
# ============================================================================

# Check ID uniqueness within file and across files
# Args: $1 = todo file, $2 = archive file (optional)
# Returns: 0 if unique, 1 if duplicates found
check_id_uniqueness() {
    local todo_file="$1"
    local archive_file="${2:-}"
    local errors=0

    # Extract all IDs from todo file
    local todo_ids
    todo_ids=$(jq -r '.tasks[].id // empty' "$todo_file" 2>/dev/null | sort)

    if [[ -z "$todo_ids" ]]; then
        return 0  # No IDs to check
    fi

    # Check for duplicates within todo file
    local duplicate_ids
    duplicate_ids=$(echo "$todo_ids" | uniq -d)

    if [[ -n "$duplicate_ids" ]]; then
        echo "ERROR: Duplicate task IDs found in $todo_file:" >&2
        echo "$duplicate_ids" | while read -r id; do
            echo "  - $id" >&2
            # Show line numbers
            jq --arg id "$id" '.tasks[] | select(.id == $id)' "$todo_file" | head -5 >&2
        done
        echo "Fix: Regenerate unique IDs for duplicate tasks" >&2
        ((errors++))
    fi

    # Check against archive file if provided
    if [[ -n "$archive_file" && -f "$archive_file" ]]; then
        local archive_ids
        archive_ids=$(jq -r '.archived_tasks[].id // empty' "$archive_file" 2>/dev/null | sort)

        if [[ -n "$archive_ids" ]]; then
            local cross_duplicates
            cross_duplicates=$(comm -12 <(echo "$todo_ids") <(echo "$archive_ids"))

            if [[ -n "$cross_duplicates" ]]; then
                echo "ERROR: Task IDs exist in both todo and archive:" >&2
                echo "$cross_duplicates" | while read -r id; do
                    echo "  - $id" >&2
                done
                echo "Fix: Remove duplicate from one of the files" >&2
                ((errors++))
            fi
        fi
    fi

    [[ $errors -eq 0 ]]
}

# ============================================================================
# TIMESTAMP VALIDATION
# ============================================================================

# Check timestamp sanity
# Args: $1 = created_at timestamp, $2 = completed_at timestamp (optional)
# Returns: 0 if valid, 1 if invalid
check_timestamp_sanity() {
    local created_at="$1"
    local completed_at="${2:-}"

    # Validate created_at format
    if [[ ! "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        echo "ERROR: Invalid timestamp format: '$created_at'" >&2
        echo "Fix: Use ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ" >&2
        return 1
    fi

    # Check created_at is not in the future
    local created_epoch current_epoch
    created_epoch=$(timestamp_to_epoch "$created_at")
    current_epoch=$(date +%s)

    if [[ $created_epoch -gt $current_epoch ]]; then
        echo "ERROR: created_at is in the future: $created_at" >&2
        echo "Fix: Use current or past timestamp" >&2
        return 1
    fi

    # If completed_at provided, check it's after created_at
    if [[ -n "$completed_at" ]]; then
        if [[ ! "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
            echo "ERROR: Invalid completed_at format: '$completed_at'" >&2
            echo "Fix: Use ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ" >&2
            return 1
        fi

        local completed_epoch
        completed_epoch=$(timestamp_to_epoch "$completed_at")

        if [[ $completed_epoch -lt $created_epoch ]]; then
            echo "ERROR: completed_at ($completed_at) is before created_at ($created_at)" >&2
            echo "Fix: Ensure completed_at is after created_at" >&2
            return 1
        fi

        if [[ $completed_epoch -gt $current_epoch ]]; then
            echo "ERROR: completed_at is in the future: $completed_at" >&2
            echo "Fix: Use current or past timestamp" >&2
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# STATUS TRANSITION VALIDATION
# ============================================================================

# Validate status transition is allowed
# Args: $1 = old status, $2 = new status
# Returns: 0 if valid, 1 if invalid
validate_status_transition() {
    local old_status="$1"
    local new_status="$2"

    # Same status is always valid
    if [[ "$old_status" == "$new_status" ]]; then
        return 0
    fi

    # Define valid transitions
    case "$old_status" in
        "pending")
            case "$new_status" in
                "active"|"blocked") return 0 ;;
                *) ;;
            esac
            ;;
        "active")
            case "$new_status" in
                "done"|"blocked"|"pending") return 0 ;;
                *) ;;
            esac
            ;;
        "done")
            # Done tasks can only go back to pending (rare)
            case "$new_status" in
                "pending") return 0 ;;
                *) ;;
            esac
            ;;
        "blocked")
            # Blocked tasks can return to pending or active
            case "$new_status" in
                "pending"|"active") return 0 ;;
                *) ;;
            esac
            ;;
    esac

    echo "ERROR: Invalid status transition: '$old_status' → '$new_status'" >&2
    echo "Valid transitions:" >&2
    echo "  pending → active, blocked" >&2
    echo "  active → done, blocked, pending" >&2
    echo "  done → pending" >&2
    echo "  blocked → pending, active" >&2
    return 1
}

# ============================================================================
# COMPREHENSIVE VALIDATION
# ============================================================================

# Validate all aspects of a file
# Args: $1 = file path, $2 = schema type, $3 = archive file (optional)
# Returns: exit code based on validation results
validate_all() {
    local file="$1"
    local schema_type="$2"
    local archive_file="${3:-}"

    local schema_errors=0
    local semantic_errors=0

    echo "Validating: $file"
    echo "Schema type: $schema_type"
    echo "----------------------------------------"

    # 1. JSON Syntax Validation
    echo "[1/6] Checking JSON syntax..."
    if ! validate_json_syntax "$file"; then
        ((schema_errors++))
        echo "✗ FAILED: JSON syntax invalid"
    else
        echo "✓ PASSED: JSON syntax valid"
    fi

    # 2. Schema Validation
    echo "[2/6] Checking schema compliance..."
    if ! validate_schema "$file" "$schema_type"; then
        ((schema_errors++))
        echo "✗ FAILED: Schema validation failed"
    else
        echo "✓ PASSED: Schema valid"
    fi

    # Stop here if schema validation failed
    if [[ $schema_errors -gt 0 ]]; then
        echo "----------------------------------------"
        echo "RESULT: Schema validation failed"
        echo "Skipping semantic checks due to schema errors"
        return $EXIT_SCHEMA_ERROR
    fi

    # 3. ID Uniqueness Check
    if [[ "$schema_type" == "todo" || "$schema_type" == "archive" ]]; then
        echo "[3/6] Checking ID uniqueness..."
        if ! check_id_uniqueness "$file" "$archive_file"; then
            ((semantic_errors++))
            echo "✗ FAILED: Duplicate IDs found"
        else
            echo "✓ PASSED: All IDs unique"
        fi
    else
        echo "[3/6] Skipping ID uniqueness check (not applicable)"
    fi

    # 4. Individual Task Validation
    if [[ "$schema_type" == "todo" ]]; then
        echo "[4/6] Validating individual tasks..."
        local task_count
        task_count=$(jq '.tasks | length' "$file")
        local task_errors=0

        for ((i=0; i<task_count; i++)); do
            if ! validate_task "$file" "$i" 2>/dev/null; then
                validate_task "$file" "$i" 2>&1  # Show errors
                ((task_errors++))
            fi
        done

        if [[ $task_errors -gt 0 ]]; then
            ((semantic_errors++))
            echo "✗ FAILED: $task_errors task(s) have validation errors"
        else
            echo "✓ PASSED: All tasks valid ($task_count tasks)"
        fi
    else
        echo "[4/6] Skipping task validation (not applicable)"
    fi

    # 5. Content Duplicate Check
    if [[ "$schema_type" == "todo" ]]; then
        echo "[5/6] Checking for duplicate content..."
        local duplicate_content
        duplicate_content=$(jq -r '.tasks[].content' "$file" | sort | uniq -d)

        if [[ -n "$duplicate_content" ]]; then
            echo "⚠ WARNING: Duplicate task content found:" >&2
            echo "$duplicate_content" | head -5 >&2
            echo "Fix: Review tasks for duplicates" >&2
            # Not counted as error, just warning
        else
            echo "✓ PASSED: No duplicate content"
        fi
    else
        echo "[5/6] Skipping duplicate content check (not applicable)"
    fi

    # 6. Done Status Consistency
    if [[ "$schema_type" == "todo" ]]; then
        echo "[6/6] Checking done status consistency..."
        local invalid_done
        invalid_done=$(jq -r '.tasks[] | select(.status == "done" and (.completed_at == null or .completed_at == "")) | .id // "unknown"' "$file")

        if [[ -n "$invalid_done" ]]; then
            echo "ERROR: Done tasks missing completed_at timestamp:" >&2
            echo "$invalid_done" >&2
            ((semantic_errors++))
            echo "✗ FAILED: Done tasks missing timestamps"
        else
            echo "✓ PASSED: Done status consistent"
        fi
    elif [[ "$schema_type" == "archive" ]]; then
        echo "[6/6] Checking archive contains only done tasks..."
        local non_done
        non_done=$(jq -r '.archived_tasks[] | select(.status != "done") | .id // "unknown"' "$file")

        if [[ -n "$non_done" ]]; then
            echo "ERROR: Archive contains non-done tasks:" >&2
            echo "$non_done" >&2
            ((semantic_errors++))
            echo "✗ FAILED: Archive validation failed"
        else
            echo "✓ PASSED: Archive valid"
        fi
    else
        echo "[6/6] Skipping status consistency check (not applicable)"
    fi

    # Summary
    echo "----------------------------------------"
    echo "VALIDATION SUMMARY:"
    echo "  Schema errors: $schema_errors"
    echo "  Semantic errors: $semantic_errors"

    if [[ $schema_errors -eq 0 && $semantic_errors -eq 0 ]]; then
        echo "✓ RESULT: All validations passed"
        return $EXIT_SUCCESS
    elif [[ $schema_errors -gt 0 && $semantic_errors -eq 0 ]]; then
        echo "✗ RESULT: Schema validation failed"
        return $EXIT_SCHEMA_ERROR
    elif [[ $schema_errors -eq 0 && $semantic_errors -gt 0 ]]; then
        echo "✗ RESULT: Semantic validation failed"
        return $EXIT_SEMANTIC_ERROR
    else
        echo "✗ RESULT: Both schema and semantic validation failed"
        return $EXIT_BOTH_ERRORS
    fi
}

# ============================================================================
# MAIN (for testing)
# ============================================================================

# If script is executed directly (not sourced), run validation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <file> <schema_type> [archive_file]" >&2
        echo "Schema types: todo, archive, config, log" >&2
        exit 1
    fi

    validate_all "$@"
    exit $?
fi
