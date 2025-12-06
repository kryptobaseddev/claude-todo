#!/usr/bin/env bash
# logging.sh - Change log functions for CLAUDE-TODO system
# Part of the claude-todo-system library

set -euo pipefail

# ============================================================================
# VERSION
# ============================================================================
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

if [[ -f "$_CLAUDE_TODO_HOME/VERSION" ]]; then
  CLAUDE_TODO_VERSION="$(cat "$_CLAUDE_TODO_HOME/VERSION" | tr -d '[:space:]')"
elif [[ -f "$_LIB_DIR/../VERSION" ]]; then
  CLAUDE_TODO_VERSION="$(cat "$_LIB_DIR/../VERSION" | tr -d '[:space:]')"
else
  CLAUDE_TODO_VERSION="0.1.0"
fi

# ============================================================================
# CONFIGURATION AND GLOBALS
# ============================================================================

# Default log file location (relative to project .claude directory)
readonly LOG_FILE="${CLAUDE_TODO_DIR:-.claude}/todo-log.json"

# Log entry ID format: log_<12-hex-chars>
readonly LOG_ID_PATTERN="^log_[a-f0-9]{12}$"

# Valid action types per schema
readonly VALID_ACTIONS=(
    "session_start"
    "session_end"
    "task_created"
    "task_updated"
    "status_changed"
    "task_archived"
    "focus_changed"
    "config_changed"
    "validation_run"
    "checksum_updated"
    "error_occurred"
)

# Valid actor types
readonly VALID_ACTORS=("human" "claude" "system")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Generate unique log entry ID
# Format: log_<12-hex-chars>
# Output: log ID string
generate_log_id() {
    local timestamp
    local random_hex

    timestamp=$(date +%s)
    random_hex=$(openssl rand -hex 6 2>/dev/null || head -c 6 /dev/urandom | xxd -p)

    echo "log_${random_hex}"
}

# Get ISO 8601 timestamp
# Output: timestamp string in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Validate action type
# Arguments:
#   $1 - action string
# Returns: 0 if valid, 1 if invalid
validate_action() {
    local action="$1"
    local valid_action

    for valid_action in "${VALID_ACTIONS[@]}"; do
        if [[ "$action" == "$valid_action" ]]; then
            return 0
        fi
    done

    return 1
}

# Validate actor type
# Arguments:
#   $1 - actor string
# Returns: 0 if valid, 1 if invalid
validate_actor() {
    local actor="$1"
    local valid_actor

    for valid_actor in "${VALID_ACTORS[@]}"; do
        if [[ "$actor" == "$valid_actor" ]]; then
            return 0
        fi
    done

    return 1
}

# ============================================================================
# LOG FILE INITIALIZATION
# ============================================================================

# Initialize log file if it doesn't exist
# Arguments:
#   $1 - (optional) log file path, defaults to LOG_FILE
# Returns: 0 on success, 1 on failure
init_log_file() {
    local log_path="${1:-$LOG_FILE}"
    local log_dir

    log_dir=$(dirname "$log_path")

    # Create directory if needed
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: Cannot create log directory: $log_dir" >&2
            return 1
        }
    fi

    # Create empty log file if it doesn't exist
    if [[ ! -f "$log_path" ]]; then
        local project_name
        project_name=$(basename "$(pwd)")

        cat > "$log_path" <<EOF
{
  "version": "${CLAUDE_TODO_VERSION}",
  "project": "${project_name}",
  "_meta": {
    "totalEntries": 0,
    "firstEntry": null,
    "lastEntry": null,
    "entriesPruned": 0
  },
  "entries": []
}
EOF

        if [[ $? -eq 0 ]]; then
            echo "Initialized log file: $log_path" >&2
            return 0
        else
            echo "ERROR: Failed to create log file: $log_path" >&2
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# LOG ENTRY CREATION
# ============================================================================

# Create a log entry object as JSON
# Arguments:
#   $1 - action (required)
#   $2 - actor (required)
#   $3 - taskId (optional, use "null" if not applicable)
#   $4 - before state JSON (optional, use "null" if not applicable)
#   $5 - after state JSON (optional, use "null" if not applicable)
#   $6 - details JSON/string (optional, use "null" if not applicable)
#   $7 - sessionId (optional, use "null" if not applicable)
# Output: JSON log entry object
create_log_entry() {
    local action="$1"
    local actor="$2"
    local task_id="${3:-null}"
    local before="${4:-null}"
    local after="${5:-null}"
    local details="${6:-null}"
    local session_id="${7:-null}"
    local log_id
    local timestamp

    # Validate required fields
    if [[ -z "$action" ]] || [[ -z "$actor" ]]; then
        echo "ERROR: action and actor are required" >&2
        return 1
    fi

    if ! validate_action "$action"; then
        echo "ERROR: Invalid action type: $action" >&2
        return 1
    fi

    if ! validate_actor "$actor"; then
        echo "ERROR: Invalid actor type: $actor" >&2
        return 1
    fi

    # Generate ID and timestamp
    log_id=$(generate_log_id)
    timestamp=$(get_timestamp)

    # Build JSON entry using jq
    jq -n \
        --arg id "$log_id" \
        --arg ts "$timestamp" \
        --arg action "$action" \
        --arg actor "$actor" \
        --argjson taskId "$(echo "$task_id" | jq -R 'if . == "null" then null else . end')" \
        --argjson sessionId "$(echo "$session_id" | jq -R 'if . == "null" then null else . end')" \
        --argjson before "$before" \
        --argjson after "$after" \
        --argjson details "$details" \
        '{
            id: $id,
            timestamp: $ts,
            sessionId: $sessionId,
            action: $action,
            actor: $actor,
            taskId: $taskId,
            before: $before,
            after: $after,
            details: $details
        }'
}

# ============================================================================
# LOG OPERATIONS
# ============================================================================

# Append log entry to log file (atomic operation)
# Arguments:
#   $1 - action (required)
#   $2 - actor (required)
#   $3 - taskId (optional)
#   $4 - before state JSON (optional)
#   $5 - after state JSON (optional)
#   $6 - details JSON/string (optional)
#   $7 - sessionId (optional)
#   $8 - log file path (optional, defaults to LOG_FILE)
# Returns: 0 on success, 1 on failure
log_operation() {
    local action="$1"
    local actor="$2"
    local task_id="${3:-null}"
    local before="${4:-null}"
    local after="${5:-null}"
    local details="${6:-null}"
    local session_id="${7:-null}"
    local log_path="${8:-$LOG_FILE}"
    local log_entry
    local temp_file
    local timestamp

    # Initialize log file if needed
    if [[ ! -f "$log_path" ]]; then
        init_log_file "$log_path" || return 1
    fi

    # Create log entry
    log_entry=$(create_log_entry "$action" "$actor" "$task_id" "$before" "$after" "$details" "$session_id")
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to create log entry" >&2
        return 1
    fi

    timestamp=$(get_timestamp)
    temp_file=$(mktemp)

    # Atomic append using jq
    if jq \
        --argjson entry "$log_entry" \
        --arg timestamp "$timestamp" \
        '
        .entries += [$entry] |
        ._meta.totalEntries = (.entries | length) |
        ._meta.lastEntry = $timestamp |
        if ._meta.firstEntry == null then
            ._meta.firstEntry = $timestamp
        else
            .
        end
        ' "$log_path" > "$temp_file"; then

        # Replace original file atomically
        mv "$temp_file" "$log_path"
        return 0
    else
        echo "ERROR: Failed to append log entry" >&2
        rm -f "$temp_file"
        return 1
    fi
}

# ============================================================================
# LOG ROTATION AND PRUNING
# ============================================================================

# Rotate log file based on retention policy
# Arguments:
#   $1 - retention days (from config)
#   $2 - log file path (optional, defaults to LOG_FILE)
# Returns: 0 on success, 1 on failure
rotate_log() {
    local retention_days="${1:-30}"
    local log_path="${2:-$LOG_FILE}"
    local cutoff_timestamp
    local temp_file
    local pruned_count

    if [[ ! -f "$log_path" ]]; then
        echo "ERROR: Log file does not exist: $log_path" >&2
        return 1
    fi

    # Calculate cutoff date (retention_days ago)
    cutoff_timestamp=$(date -u -d "$retention_days days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                       date -u -v-"${retention_days}d" +"%Y-%m-%dT%H:%M:%SZ")

    temp_file=$(mktemp)

    # Filter entries and update metadata
    if jq \
        --arg cutoff "$cutoff_timestamp" \
        '
        .entries as $all_entries |
        (.entries | length) as $original_count |
        .entries = (.entries | map(select(.timestamp >= $cutoff))) |
        ._meta.totalEntries = (.entries | length) |
        ._meta.entriesPruned = (._meta.entriesPruned + ($original_count - (.entries | length))) |
        if (.entries | length) > 0 then
            ._meta.firstEntry = (.entries[0].timestamp) |
            ._meta.lastEntry = (.entries[-1].timestamp)
        else
            ._meta.firstEntry = null |
            ._meta.lastEntry = null
        end
        ' "$log_path" > "$temp_file"; then

        pruned_count=$(jq -r \
            --arg cutoff "$cutoff_timestamp" \
            '.entries | map(select(.timestamp < $cutoff)) | length' \
            "$log_path")

        mv "$temp_file" "$log_path"
        echo "Pruned $pruned_count log entries older than $retention_days days" >&2
        return 0
    else
        echo "ERROR: Failed to rotate log file" >&2
        rm -f "$temp_file"
        return 1
    fi
}

# Check if log rotation is needed based on config
# Arguments:
#   $1 - config file path
#   $2 - log file path (optional, defaults to LOG_FILE)
# Returns: 0 if rotation performed, 1 if not needed or error
check_and_rotate_log() {
    local config_path="$1"
    local log_path="${2:-$LOG_FILE}"
    local retention_days
    local logging_enabled

    if [[ ! -f "$config_path" ]]; then
        echo "ERROR: Config file not found: $config_path" >&2
        return 1
    fi

    # Read config settings
    logging_enabled=$(jq -r '.logging.enabled // true' "$config_path")
    retention_days=$(jq -r '.logging.retentionDays // 30' "$config_path")

    if [[ "$logging_enabled" != "true" ]]; then
        return 1
    fi

    # Perform rotation
    rotate_log "$retention_days" "$log_path"
}

# ============================================================================
# LOG QUERY FUNCTIONS
# ============================================================================

# Get log entries with optional filtering
# Arguments:
#   $1 - filter type (action|taskId|actor|date_range)
#   $2 - filter value(s)
#   $3 - log file path (optional, defaults to LOG_FILE)
# Output: JSON array of matching log entries
get_log_entries() {
    local filter_type="${1:-all}"
    local filter_value="${2:-}"
    local log_path="${3:-$LOG_FILE}"

    if [[ ! -f "$log_path" ]]; then
        echo "[]"
        return 0
    fi

    case "$filter_type" in
        action)
            jq --arg action "$filter_value" \
                '.entries | map(select(.action == $action))' \
                "$log_path"
            ;;
        taskId)
            jq --arg taskId "$filter_value" \
                '.entries | map(select(.taskId == $taskId))' \
                "$log_path"
            ;;
        actor)
            jq --arg actor "$filter_value" \
                '.entries | map(select(.actor == $actor))' \
                "$log_path"
            ;;
        date_range)
            # filter_value should be "start_date,end_date"
            local start_date="${filter_value%,*}"
            local end_date="${filter_value#*,}"
            jq --arg start "$start_date" --arg end "$end_date" \
                '.entries | map(select(.timestamp >= $start and .timestamp <= $end))' \
                "$log_path"
            ;;
        all)
            jq '.entries' "$log_path"
            ;;
        *)
            echo "ERROR: Invalid filter type: $filter_type" >&2
            echo "[]"
            return 1
            ;;
    esac
}

# Get most recent log entries
# Arguments:
#   $1 - count (number of entries to retrieve)
#   $2 - log file path (optional, defaults to LOG_FILE)
# Output: JSON array of log entries
get_recent_log_entries() {
    local count="${1:-10}"
    local log_path="${2:-$LOG_FILE}"

    if [[ ! -f "$log_path" ]]; then
        echo "[]"
        return 0
    fi

    jq --argjson count "$count" \
        '.entries | reverse | .[:$count] | reverse' \
        "$log_path"
}

# Get log statistics
# Arguments:
#   $1 - log file path (optional, defaults to LOG_FILE)
# Output: JSON object with statistics
get_log_stats() {
    local log_path="${1:-$LOG_FILE}"

    if [[ ! -f "$log_path" ]]; then
        echo '{"totalEntries":0,"firstEntry":null,"lastEntry":null,"entriesPruned":0}'
        return 0
    fi

    jq '._meta' "$log_path"
}

# ============================================================================
# CONVENIENCE LOGGING FUNCTIONS
# ============================================================================

# Log task creation
log_task_created() {
    local task_id="$1"
    local task_content="$2"
    local session_id="${3:-null}"
    local details

    details=$(jq -n --arg content "$task_content" '{content: $content}')
    log_operation "task_created" "claude" "$task_id" "null" "null" "$details" "$session_id"
}

# Log task status change
log_status_changed() {
    local task_id="$1"
    local old_status="$2"
    local new_status="$3"
    local session_id="${4:-null}"
    local before
    local after

    before=$(jq -n --arg status "$old_status" '{status: $status}')
    after=$(jq -n --arg status "$new_status" '{status: $status}')
    log_operation "status_changed" "claude" "$task_id" "$before" "$after" "null" "$session_id"
}

# Log task update
log_task_updated() {
    local task_id="$1"
    local field="$2"
    local old_value="$3"
    local new_value="$4"
    local session_id="${5:-null}"
    local details

    details=$(jq -n \
        --arg field "$field" \
        --arg old "$old_value" \
        --arg new "$new_value" \
        '{field: $field, oldValue: $old, newValue: $new}')
    log_operation "task_updated" "claude" "$task_id" "null" "null" "$details" "$session_id"
}

# Log session start
log_session_start() {
    local session_id="$1"
    local details="${2:-null}"

    log_operation "session_start" "system" "null" "null" "null" "$details" "$session_id"
}

# Log session end
log_session_end() {
    local session_id="$1"
    local details="${2:-null}"

    log_operation "session_end" "system" "null" "null" "null" "$details" "$session_id"
}

# Log validation run
log_validation() {
    local result="$1"
    local details="$2"

    log_operation "validation_run" "system" "null" "null" "null" "$details" "null"
}

# Log error
log_error() {
    local error_code="$1"
    local error_message="$2"
    local recoverable="${3:-false}"
    local task_id="${4:-null}"
    local details

    details=$(jq -n \
        --arg code "$error_code" \
        --arg message "$error_message" \
        --argjson recoverable "$recoverable" \
        '{error: {code: $code, message: $message, recoverable: $recoverable}}')
    log_operation "error_occurred" "system" "$task_id" "null" "null" "$details" "null"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Handle logging errors gracefully
# Arguments:
#   $1 - error message
handle_log_error() {
    local error_msg="$1"
    echo "WARNING: Logging failed: $error_msg" >&2
    echo "This will not prevent the operation from completing" >&2
}

# ============================================================================
# EXPORTS
# ============================================================================

# Export functions for use by other scripts
export -f generate_log_id
export -f get_timestamp
export -f init_log_file
export -f create_log_entry
export -f log_operation
export -f rotate_log
export -f check_and_rotate_log
export -f get_log_entries
export -f get_recent_log_entries
export -f get_log_stats
export -f log_task_created
export -f log_status_changed
export -f log_task_updated
export -f log_session_start
export -f log_session_end
export -f log_validation
export -f log_error
export -f handle_log_error
