#!/usr/bin/env bash
# CLAUDE-TODO Session Management Script
# Manage work sessions with automatic logging
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Source version
if [[ -f "$CLAUDE_TODO_HOME/VERSION" ]]; then
  VERSION="$(cat "$CLAUDE_TODO_HOME/VERSION" | tr -d '[:space:]')"
elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
  VERSION="$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')"
else
  VERSION="0.1.0"
fi

# Source libraries
[[ -f "$CLAUDE_TODO_HOME/lib/logging.sh" ]] && source "$CLAUDE_TODO_HOME/lib/logging.sh"
[[ -f "$CLAUDE_TODO_HOME/lib/file-ops.sh" ]] && source "$CLAUDE_TODO_HOME/lib/file-ops.sh"

# Also try local lib directory if home installation not found
LIB_DIR="${SCRIPT_DIR}/../lib"
[[ ! -f "$CLAUDE_TODO_HOME/lib/file-ops.sh" && -f "$LIB_DIR/file-ops.sh" ]] && source "$LIB_DIR/file-ops.sh"

# Source output-format library for format resolution
if [[ -f "$CLAUDE_TODO_HOME/lib/output-format.sh" ]]; then
  source "$CLAUDE_TODO_HOME/lib/output-format.sh"
elif [[ -f "$LIB_DIR/output-format.sh" ]]; then
  source "$LIB_DIR/output-format.sh"
fi

# Source exit codes and error-json libraries
if [[ -f "$CLAUDE_TODO_HOME/lib/exit-codes.sh" ]]; then
  source "$CLAUDE_TODO_HOME/lib/exit-codes.sh"
elif [[ -f "$LIB_DIR/exit-codes.sh" ]]; then
  source "$LIB_DIR/exit-codes.sh"
fi
if [[ -f "$CLAUDE_TODO_HOME/lib/error-json.sh" ]]; then
  source "$CLAUDE_TODO_HOME/lib/error-json.sh"
elif [[ -f "$LIB_DIR/error-json.sh" ]]; then
  source "$LIB_DIR/error-json.sh"
fi

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
# Note: LOG_FILE is set by lib/logging.sh (readonly) - don't reassign here
# If library wasn't sourced, set a fallback
if [[ -z "${LOG_FILE:-}" ]]; then
  LOG_FILE=".claude/todo-log.json"
fi

# Colors (respects NO_COLOR and FORCE_COLOR environment variables per https://no-color.org)
if declare -f should_use_color >/dev/null 2>&1 && should_use_color; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
# Format-aware log_error: uses output_error for JSON, text fallback otherwise
log_error() {
  local message="$1"
  local error_code="${2:-E_UNKNOWN}"
  local exit_code="${3:-1}"
  local suggestion="${4:-}"

  # Check if output_format is json (from cmd_status/cmd_info local vars or global)
  local current_format="${output_format:-${FORMAT:-text}}"

  if [[ "$current_format" == "json" ]] && declare -f output_error >/dev/null 2>&1; then
    FORMAT="$current_format"  # Sync FORMAT for output_error
    output_error "$error_code" "$message" "$exit_code" true "$suggestion"
  else
    echo -e "${RED}[ERROR]${NC} $message" >&2
    [[ -n "$suggestion" ]] && echo "Suggestion: $suggestion" >&2
  fi
}
log_step()    { echo -e "${BLUE}[SESSION]${NC} $1"; }

# Global format variable for output_error (empty allows TTY auto-detection)
FORMAT=""
QUIET=false

COMMAND_NAME="session"

usage() {
  cat << EOF
Usage: claude-todo session <command> [OPTIONS]

Manage claude-todo work sessions.

Commands:
  start       Start a new session
  end         End the current session
  status      Show current session status
  info        Show detailed session information

Options:
  --note TEXT       Add a note when ending session
  -f, --format FMT  Output format: text|json (default: auto)
  --human           Force text output (human-readable)
  --json            Force JSON output (machine-readable)
  -q, --quiet       Suppress informational messages
  -h, --help        Show this help

Format Auto-Detection:
  When no format is specified, output format is automatically detected:
  - Interactive terminal (TTY): human-readable text format
  - Pipe/redirect/agent context: machine-readable JSON format

Examples:
  claude-todo session start                    # Start new session
  claude-todo session end --note "Completed auth implementation"
  claude-todo session status                   # Check current session
  claude-todo session info --json              # Detailed info as JSON
  claude-todo session status --format json     # Machine-readable status
EOF
  exit 0
}

# Check dependencies
if ! command -v jq &> /dev/null; then
  log_error "jq is required but not installed" "E_DEPENDENCY_MISSING" 1 "Install jq: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

# Check todo.json exists
check_todo_exists() {
  if [[ ! -f "$TODO_FILE" ]]; then
    log_error "Todo file not found: $TODO_FILE. Run 'claude-todo init' first" "E_NOT_INITIALIZED" 1 "Run 'claude-todo init' to initialize"
    exit 1
  fi
}

# Generate session ID: session_YYYYMMDD_HHMMSS_<6hex>
generate_session_id() {
  local date_part
  local random_hex
  date_part=$(date +"%Y%m%d_%H%M%S")
  random_hex=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
  echo "session_${date_part}_${random_hex}"
}

# Get current session info
get_current_session() {
  jq -r '._meta.activeSession // ""' "$TODO_FILE"
}

# Start a new session
cmd_start() {
  check_todo_exists

  local current_session
  current_session=$(get_current_session)

  if [[ -n "$current_session" ]]; then
    log_error "Session already active: $current_session" "E_SESSION_ACTIVE" 1 "Use 'claude-todo session end' first, or continue with current session"
    exit 1
  fi

  local session_id
  session_id=$(generate_session_id)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update todo.json with new session
  local updated_todo
  updated_todo=$(jq --arg sid "$session_id" --arg ts "$timestamp" '
    ._meta.activeSession = $sid |
    ._meta.lastModified = $ts
  ' "$TODO_FILE")
  save_json "$TODO_FILE" "$updated_todo" || {
    log_error "Failed to start session" "E_FILE_WRITE_ERROR" 1 "Check file permissions on $TODO_FILE"
    exit 1
  }

  # Log session start
  if [[ -f "$LOG_FILE" ]]; then
    local log_id
    log_id="log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    local updated_log
    updated_log=$(jq --arg id "$log_id" --arg ts "$timestamp" --arg sid "$session_id" '
      .entries += [{
        id: $id,
        timestamp: $ts,
        sessionId: $sid,
        action: "session_start",
        actor: "system",
        taskId: null,
        before: null,
        after: null,
        details: "Session started"
      }] |
      ._meta.totalEntries += 1 |
      ._meta.lastEntry = $ts
    ' "$LOG_FILE")
    save_json "$LOG_FILE" "$updated_log" || log_warn "Failed to write log entry"
  fi

  log_step "Session started: $session_id"

  # Show current focus if any
  local focus_task
  focus_task=$(jq -r '.focus.currentTask // ""' "$TODO_FILE")
  if [[ -n "$focus_task" ]]; then
    local task_title
    task_title=$(jq -r --arg id "$focus_task" '.tasks[] | select(.id == $id) | .content // .title // "Unknown"' "$TODO_FILE")
    log_info "Resume focus: $task_title ($focus_task)"
  fi

  # Show session note from last session
  local last_note
  last_note=$(jq -r '.focus.sessionNote // ""' "$TODO_FILE")
  if [[ -n "$last_note" ]]; then
    log_info "Last session note: $last_note"
  fi

  # Show next action if any
  local next_action
  next_action=$(jq -r '.focus.nextAction // ""' "$TODO_FILE")
  if [[ -n "$next_action" ]]; then
    log_info "Suggested next action: $next_action"
  fi

  # Check if CLAUDE.md injection is outdated
  if [[ -f "CLAUDE.md" ]] && [[ -f "$CLAUDE_TODO_HOME/templates/CLAUDE-INJECTION.md" ]]; then
    local current_version installed_version
    current_version=$(grep -oP 'CLAUDE-TODO:START v\K[0-9.]+' CLAUDE.md 2>/dev/null || echo "")
    installed_version=$(grep -oP 'CLAUDE-TODO:START v\K[0-9.]+' "$CLAUDE_TODO_HOME/templates/CLAUDE-INJECTION.md" 2>/dev/null || echo "")

    if [[ -n "$installed_version" ]] && [[ "$current_version" != "$installed_version" ]]; then
      log_warn "CLAUDE.md injection outdated (${current_version:-unknown} → $installed_version)"
      log_warn "Run: claude-todo init --update-claude-md"
    fi
  fi
}

# End current session
cmd_end() {
  local note=""

  # Parse options
  while [[ $# -gt 0 ]]; do
    case $1 in
      --note) note="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  check_todo_exists

  local current_session
  current_session=$(get_current_session)

  if [[ -z "$current_session" ]]; then
    log_warn "No active session to end"
    exit 0
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build update JSON
  local update_expr='
    ._meta.activeSession = null |
    ._meta.lastModified = $ts
  '

  if [[ -n "$note" ]]; then
    update_expr="$update_expr | .focus.sessionNote = \$note"
  fi

  # Update todo.json
  local updated_todo
  if [[ -n "$note" ]]; then
    updated_todo=$(jq --arg ts "$timestamp" --arg note "$note" "$update_expr" "$TODO_FILE")
  else
    updated_todo=$(jq --arg ts "$timestamp" '
      ._meta.activeSession = null |
      ._meta.lastModified = $ts
    ' "$TODO_FILE")
  fi
  save_json "$TODO_FILE" "$updated_todo" || {
    log_error "Failed to end session" "E_FILE_WRITE_ERROR" 1 "Check file permissions on $TODO_FILE"
    exit 1
  }

  # Log session end
  if [[ -f "$LOG_FILE" ]]; then
    local log_id
    log_id="log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    local details_json
    if [[ -n "$note" ]]; then
      details_json=$(jq -n --arg note "$note" '{note: $note}')
    else
      details_json="null"
    fi

    local updated_log
    updated_log=$(jq --arg id "$log_id" --arg ts "$timestamp" --arg sid "$current_session" --argjson details "$details_json" '
      .entries += [{
        id: $id,
        timestamp: $ts,
        sessionId: $sid,
        action: "session_end",
        actor: "system",
        taskId: null,
        before: null,
        after: null,
        details: $details
      }] |
      ._meta.totalEntries += 1 |
      ._meta.lastEntry = $ts
    ' "$LOG_FILE")
    save_json "$LOG_FILE" "$updated_log" || log_warn "Failed to write log entry"
  fi

  log_step "Session ended: $current_session"
  [[ -n "$note" ]] && log_info "Note saved: $note" || true

  # Check and rotate log if needed (T214)
  if declare -f check_and_rotate_log >/dev/null 2>&1; then
    local config_file="${CONFIG_FILE:-.claude/todo-config.json}"
    [[ -f "$config_file" ]] && check_and_rotate_log "$config_file" "$LOG_FILE" 2>/dev/null || true
  fi
}

# Show session status
cmd_status() {
  local format_arg=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -f|--format) format_arg="$2"; shift 2 ;;
      --human) format_arg="text"; shift ;;
      --json) format_arg="json"; shift ;;
      -q|--quiet) QUIET=true; shift ;;
      *) shift ;;
    esac
  done

  # Resolve format with TTY-aware detection
  local output_format
  output_format=$(resolve_format "$format_arg")

  check_todo_exists

  local session_id
  local focus_task
  local session_note
  local next_action

  session_id=$(jq -r '._meta.activeSession // ""' "$TODO_FILE")
  focus_task=$(jq -r '.focus.currentTask // ""' "$TODO_FILE")
  session_note=$(jq -r '.focus.sessionNote // ""' "$TODO_FILE")
  next_action=$(jq -r '.focus.nextAction // ""' "$TODO_FILE")

  if [[ "$output_format" == "json" ]]; then
    local current_timestamp
    current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
      --arg timestamp "$current_timestamp" \
      --arg version "$VERSION" \
      --arg session "$session_id" \
      --arg focus "$focus_task" \
      --arg note "$session_note" \
      --arg next "$next_action" \
      '{
        "$schema": "https://claude-todo.dev/schemas/v1/output.schema.json",
        "_meta": {
          "format": "json",
          "command": "session status",
          "timestamp": $timestamp,
          "version": $version
        },
        "success": true,
        "session": {
          "active": ($session != ""),
          "sessionId": (if $session == "" then null else $session end),
          "focusTask": (if $focus == "" then null else $focus end),
          "sessionNote": (if $note == "" then null else $note end),
          "nextAction": (if $next == "" then null else $next end)
        }
      }'
  else
    if [[ -n "$session_id" ]]; then
      echo -e "${GREEN}Session Active${NC}: $session_id"
    else
      echo -e "${YELLOW}No Active Session${NC}"
    fi

    if [[ -n "$focus_task" ]]; then
      local task_title
      task_title=$(jq -r --arg id "$focus_task" '.tasks[] | select(.id == $id) | .content // .title // "Unknown"' "$TODO_FILE")
      echo -e "Focus Task: $task_title ($focus_task)"
    fi

    [[ -n "$session_note" ]] && echo -e "Session Note: $session_note" || true
    [[ -n "$next_action" ]] && echo -e "Next Action: $next_action" || true
  fi
}

# Show detailed session info
cmd_info() {
  local format_arg=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -f|--format) format_arg="$2"; shift 2 ;;
      --human) format_arg="text"; shift ;;
      --json) format_arg="json"; shift ;;
      -q|--quiet) QUIET=true; shift ;;
      *) shift ;;
    esac
  done

  # Resolve format with TTY-aware detection
  local output_format
  output_format=$(resolve_format "$format_arg")

  check_todo_exists

  if [[ "$output_format" == "json" ]]; then
    local current_timestamp
    current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg timestamp "$current_timestamp" --arg version "$VERSION" '{
      "$schema": "https://claude-todo.dev/schemas/v1/output.schema.json",
      "_meta": {
        "format": "json",
        "command": "session info",
        "timestamp": $timestamp,
        "version": $version
      },
      "success": true,
      "session": {
        "meta": ._meta,
        "focus": .focus,
        "taskCounts": {
          "total": (.tasks | length),
          "pending": ([.tasks[] | select(.status == "pending")] | length),
          "active": ([.tasks[] | select(.status == "active")] | length),
          "blocked": ([.tasks[] | select(.status == "blocked")] | length),
          "done": ([.tasks[] | select(.status == "done")] | length)
        }
      }
    }' "$TODO_FILE"
  else
    echo ""
    echo "=== Session Information ==="
    echo ""

    local session_id
    session_id=$(jq -r '._meta.activeSession // "none"' "$TODO_FILE")
    echo "Session ID: $session_id"

    local last_modified
    last_modified=$(jq -r '._meta.lastModified // "unknown"' "$TODO_FILE")
    echo "Last Modified: $last_modified"

    echo ""
    echo "=== Focus State ==="
    jq -r '.focus | to_entries[] | "  \(.key): \(.value // "not set")"' "$TODO_FILE"

    echo ""
    echo "=== Task Counts ==="
    echo "  Total: $(jq '.tasks | length' "$TODO_FILE")"
    echo "  Pending: $(jq '[.tasks[] | select(.status == "pending")] | length' "$TODO_FILE")"
    echo "  Active: $(jq '[.tasks[] | select(.status == "active")] | length' "$TODO_FILE")"
    echo "  Blocked: $(jq '[.tasks[] | select(.status == "blocked")] | length' "$TODO_FILE")"
    echo "  Done: $(jq '[.tasks[] | select(.status == "done")] | length' "$TODO_FILE")"
    echo ""
  fi
}

# Main command dispatch
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  start)  cmd_start "$@" ;;
  end)    cmd_end "$@" ;;
  status) cmd_status "$@" ;;
  info)   cmd_info "$@" ;;
  -h|--help|help) usage ;;
  *)
    log_error "Unknown command: $COMMAND" "E_INPUT_INVALID" 1 "Run 'claude-todo session --help' for usage"
    exit 1
    ;;
esac
