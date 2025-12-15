#!/usr/bin/env bash
# CLAUDE-TODO Log Script
# Add entries to todo-log.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Source version from central location
if [[ -f "$CLAUDE_TODO_HOME/VERSION" ]]; then
  VERSION="$(cat "$CLAUDE_TODO_HOME/VERSION" | tr -d '[:space:]')"
elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
  VERSION="$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')"
else
  VERSION="0.1.0"
fi

# Source logging library for should_use_color function
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "$LIB_DIR/logging.sh" ]]; then
  # shellcheck source=../lib/logging.sh
  source "$LIB_DIR/logging.sh"
fi

# Set TODO_FILE after sourcing logging.sh (LOG_FILE is set by logging.sh)
TODO_FILE="${TODO_FILE:-.claude/todo.json}"

# Colors (respects NO_COLOR and FORCE_COLOR environment variables per https://no-color.org)
if declare -f should_use_color >/dev/null 2>&1 && should_use_color; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED='' GREEN='' NC=''
fi

# Defaults
ACTION=""
TASK_ID=""
SESSION_ID=""
BEFORE=""
AFTER=""
DETAILS=""
ACTOR="claude"

# Helper function to validate action against library's VALID_ACTIONS array
validate_action() {
  local action="$1"
  # Check if VALID_ACTIONS array is available from logging.sh
  if declare -p VALID_ACTIONS 2>/dev/null | grep -q 'declare -ar'; then
    for valid in "${VALID_ACTIONS[@]}"; do
      [[ "$action" == "$valid" ]] && return 0
    done
    return 1
  else
    # Fallback if library not sourced (shouldn't happen)
    local valid_actions="session_start session_end task_created task_updated status_changed task_archived focus_changed config_changed validation_run checksum_updated error_occurred"
    echo "$valid_actions" | grep -qw "$action"
  fi
}

# Helper function to get valid actions string for display
get_valid_actions_string() {
  if declare -p VALID_ACTIONS 2>/dev/null | grep -q 'declare -ar'; then
    echo "${VALID_ACTIONS[*]}"
  else
    echo "session_start session_end task_created task_updated status_changed task_archived focus_changed config_changed validation_run checksum_updated error_occurred"
  fi
}

usage() {
  cat << EOF
Usage: claude-todo log [SUBCOMMAND] [OPTIONS]

Manage todo-log.json entries.

Subcommands:
  list              List log entries (with filtering)
  show <log-id>     Show details of a specific log entry
  migrate           Migrate old schema entries to new schema
  add               Add a new log entry (default if --action specified)

List options:
  --limit N         Show last N entries (default: 20, 0 = all)
  --action ACTION   Filter by action type
  --task-id ID      Filter by task ID
  --actor ACTOR     Filter by actor (human|claude|system)
  --since DATE      Show entries since date (YYYY-MM-DD)
  --format FORMAT   Output format: text|json (default: text)

Add entry options:
  --action ACTION   One of: $(get_valid_actions_string)
  --task-id ID      Task ID (for task-related actions)
  --session-id ID   Session ID
  --before JSON     State before change
  --after JSON      State after change
  --details JSON    Additional details
  --actor ACTOR     human|claude|system (default: claude)
  -h, --help        Show this help

Examples:
  # List log entries
  claude-todo log list                              # Last 20 entries
  claude-todo log list --limit 50                   # Last 50 entries
  claude-todo log list --action task_created        # Filter by action
  claude-todo log list --task-id T001               # Filter by task
  claude-todo log list --since "2025-12-13"         # Since date
  claude-todo log list --format json                # JSON output

  # Show specific entry
  claude-todo log show log_abc123

  # Migrate old log entries
  claude-todo log migrate

  # Add log entries
  claude-todo log --action session_start --session-id "session_20251205_..."
  claude-todo log --action status_changed --task-id T001 --before '{"status":"pending"}' --after '{"status":"active"}'
  claude-todo log --action task_created --task-id T005 --after '{"title":"New task"}'
EOF
  exit 0
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Check dependencies
if ! command -v jq &> /dev/null; then
  log_error "jq is required but not installed"
  exit 1
fi

# Parse subcommand
SUBCOMMAND=""
if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
  SUBCOMMAND="$1"
  shift
fi

# Handle subcommands
case "$SUBCOMMAND" in
  list)
    # List log entries with filtering
    LIMIT=20
    FILTER_ACTION=""
    FILTER_TASK_ID=""
    FILTER_ACTOR=""
    FILTER_SINCE=""
    OUTPUT_FORMAT="text"

    # Parse list options
    while [[ $# -gt 0 ]]; do
      case $1 in
        --limit) LIMIT="$2"; shift 2 ;;
        --action) FILTER_ACTION="$2"; shift 2 ;;
        --task-id) FILTER_TASK_ID="$2"; shift 2 ;;
        --actor) FILTER_ACTOR="$2"; shift 2 ;;
        --since) FILTER_SINCE="$2"; shift 2 ;;
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) log_error "Unknown option: $1"; exit 1 ;;
        *) shift ;;
      esac
    done

    # Validate log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
      log_error "Log file not found: $LOG_FILE"
      exit 1
    fi

    # Build jq filter
    JQ_FILTER='.entries'

    # Apply filters
    if [[ -n "$FILTER_ACTION" ]]; then
      JQ_FILTER="$JQ_FILTER | map(select(.action == \"$FILTER_ACTION\"))"
    fi

    if [[ -n "$FILTER_TASK_ID" ]]; then
      JQ_FILTER="$JQ_FILTER | map(select(.taskId == \"$FILTER_TASK_ID\"))"
    fi

    if [[ -n "$FILTER_ACTOR" ]]; then
      JQ_FILTER="$JQ_FILTER | map(select(.actor == \"$FILTER_ACTOR\"))"
    fi

    if [[ -n "$FILTER_SINCE" ]]; then
      # Convert date to ISO format for comparison
      SINCE_ISO="${FILTER_SINCE}T00:00:00Z"
      JQ_FILTER="$JQ_FILTER | map(select(.timestamp >= \"$SINCE_ISO\"))"
    fi

    # Apply limit (0 = all entries)
    if [[ "$LIMIT" -gt 0 ]]; then
      JQ_FILTER="$JQ_FILTER | .[-$LIMIT:]"
    fi

    # Output format
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      jq "$JQ_FILTER" "$LOG_FILE"
    else
      # Text format - output each entry line by line
      jq -r "$JQ_FILTER"' | .[] |
        "[\(.timestamp | sub("T"; " ") | sub("Z"; ""))] \(.action) - \(.taskId // "(no task)") by \(.actor)" +
        (if .after.title then "\n  title: \"\(.after.title)\"" else "" end) +
        (if .details then "\n  details: \(.details | tostring)" else "" end)
      ' "$LOG_FILE"
    fi

    exit 0
    ;;

  show)
    # Show specific log entry
    if [[ $# -lt 1 ]]; then
      log_error "Log ID required. Usage: claude-todo log show <log-id>"
      exit 1
    fi

    LOG_ID="$1"
    shift

    # Validate log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
      log_error "Log file not found: $LOG_FILE"
      exit 1
    fi

    # Find and display entry
    ENTRY=$(jq --arg id "$LOG_ID" '.entries[] | select(.id == $id)' "$LOG_FILE")

    if [[ -z "$ENTRY" ]]; then
      log_error "Log entry not found: $LOG_ID"
      exit 1
    fi

    # Display entry in readable format
    echo "$ENTRY" | jq -r '
      "Log Entry: \(.id)",
      "Timestamp:  \(.timestamp | sub("T"; " ") | sub("Z"; ""))",
      "Action:     \(.action)",
      "Actor:      \(.actor)",
      (if .taskId then "Task ID:    \(.taskId)" else "" end),
      (if .sessionId then "Session ID: \(.sessionId)" else "" end),
      "",
      (if .before then "Before:\n\(.before | tojson)" else "" end),
      (if .after then "After:\n\(.after | tojson)" else "" end),
      (if .details then "Details:\n\(.details | if type == "string" then . else tojson end)" else "" end)
    ' | grep -v '^$' || true

    exit 0
    ;;

  migrate)
    # Migrate old schema to new schema
    if ! declare -f migrate_log_entries >/dev/null 2>&1; then
      log_error "migrate_log_entries function not available from logging.sh"
      exit 1
    fi

    log_info "Starting log migration..."
    migrated_count=$(migrate_log_entries "$LOG_FILE")
    if [[ $? -eq 0 ]]; then
      log_info "Migration completed successfully ($migrated_count entries migrated)"
      exit 0
    else
      log_error "Migration failed"
      exit 1
    fi
    ;;
  rotate)
    # Manual log rotation (T214)
    if ! declare -f rotate_log >/dev/null 2>&1; then
      log_error "rotate_log function not available from logging.sh"
      exit 1
    fi

    FORCE=false
    while [[ $# -gt 0 ]]; do
      case $1 in
        --force) FORCE=true; shift ;;
        -h|--help)
          echo "Usage: claude-todo log rotate [OPTIONS]"
          echo ""
          echo "Rotate log file if it exceeds configured threshold."
          echo ""
          echo "Options:"
          echo "  --force    Force rotation regardless of size"
          echo "  --help     Show this help"
          exit 0
          ;;
        *) shift ;;
      esac
    done

    if [[ ! -f "$LOG_FILE" ]]; then
      log_error "Log file not found: $LOG_FILE"
      exit 1
    fi

    current_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo "0")
    size_kb=$((current_size / 1024))

    CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"

    if [[ "$FORCE" == "true" ]]; then
      log_info "Forcing log rotation..."
      rotate_log 30 "$LOG_FILE"
      log_success "Log rotated successfully"
    else
      log_info "Current log size: ${size_kb}KB"
      if [[ -f "$CONFIG_FILE" ]]; then
        check_and_rotate_log "$CONFIG_FILE" "$LOG_FILE"
        log_info "Log rotation check complete"
      else
        log_warn "No config file found, skipping automatic rotation"
        log_info "Use --force to rotate anyway"
      fi
    fi
    exit 0
    ;;

  add|"")
    # Fall through to add entry logic
    ;;
  *)
    log_error "Unknown subcommand: $SUBCOMMAND"
    usage
    ;;
esac

# Parse arguments for add entry
while [[ $# -gt 0 ]]; do
  case $1 in
    --action) ACTION="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --before) BEFORE="$2"; shift 2 ;;
    --after) AFTER="$2"; shift 2 ;;
    --details) DETAILS="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) shift ;;
  esac
done

# Validate action
if [[ -z "$ACTION" ]]; then
  log_error "Action required. Use --action"
  exit 1
fi

if ! validate_action "$ACTION"; then
  log_error "Invalid action: $ACTION"
  echo "Valid actions: $(get_valid_actions_string)"
  exit 1
fi

# Validate actor
if ! echo "human claude system" | grep -qw "$ACTOR"; then
  log_error "Invalid actor: $ACTOR (must be human, claude, or system)"
  exit 1
fi

# Validate JSON inputs
for var in BEFORE AFTER DETAILS; do
  val="${!var}"
  if [[ -n "$val" ]] && ! echo "$val" | jq empty 2>/dev/null; then
    log_error "Invalid JSON for --$(echo $var | tr '[:upper:]' '[:lower:]'): $val"
    exit 1
  fi
done

# Get session ID from todo.json if not provided
if [[ -z "$SESSION_ID" ]] && [[ -f "$TODO_FILE" ]]; then
  SESSION_ID=$(jq -r '._meta.activeSession // ""' "$TODO_FILE")
fi

# Create log file if missing
if [[ ! -f "$LOG_FILE" ]]; then
  PROJECT=""
  [[ -f "$TODO_FILE" ]] && PROJECT=$(jq -r '.project' "$TODO_FILE")
  cat > "$LOG_FILE" << EOF
{
  "version": "$VERSION",
  "project": "$PROJECT",
  "_meta": {
    "totalEntries": 0,
    "firstEntry": null,
    "lastEntry": null,
    "entriesPruned": 0
  },
  "entries": []
}
EOF
  log_info "Created $LOG_FILE"
fi

# Generate entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_ID="log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 12)"

# Build entry JSON
ENTRY=$(jq -n \
  --arg id "$LOG_ID" \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg action "$ACTION" \
  --arg actor "$ACTOR" \
  --arg tid "$TASK_ID" \
  --argjson before "${BEFORE:-null}" \
  --argjson after "${AFTER:-null}" \
  --argjson details "${DETAILS:-null}" \
  '{
    id: $id,
    timestamp: $ts,
    sessionId: (if $sid == "" then null else $sid end),
    action: $action,
    actor: $actor,
    taskId: (if $tid == "" then null else $tid end),
    before: $before,
    after: $after,
    details: $details
  }')

# Add entry to log
jq --argjson entry "$ENTRY" --arg ts "$TIMESTAMP" '
  .entries += [$entry] |
  ._meta.totalEntries += 1 |
  ._meta.lastEntry = $ts |
  ._meta.firstEntry = (._meta.firstEntry // $ts)
' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"

log_info "Logged: $ACTION ($LOG_ID)"
