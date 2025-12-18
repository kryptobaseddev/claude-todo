#!/usr/bin/env bash
# CLAUDE-TODO Complete Task Script
# Mark a task as complete and optionally trigger archive
set -euo pipefail

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="${SCRIPT_DIR}/log.sh"
ARCHIVE_SCRIPT="${SCRIPT_DIR}/archive.sh"

# Version from central location
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"
if [[ -f "$CLAUDE_TODO_HOME/VERSION" ]]; then
  VERSION="$(cat "$CLAUDE_TODO_HOME/VERSION" | tr -d '[:space:]')"
elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
  VERSION="$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')"
else
  VERSION="0.16.0"
fi

# Command name for error-json library
COMMAND_NAME="complete"

# Source logging library for should_use_color function
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "$LIB_DIR/logging.sh" ]]; then
  # shellcheck source=../lib/logging.sh
  source "$LIB_DIR/logging.sh"
fi

# Source file operations library for atomic writes with locking
if [[ -f "$LIB_DIR/file-ops.sh" ]]; then
  # shellcheck source=../lib/file-ops.sh
  source "$LIB_DIR/file-ops.sh"
fi

# Source backup library for unified backup management
if [[ -f "$LIB_DIR/backup.sh" ]]; then
  # shellcheck source=../lib/backup.sh
  source "$LIB_DIR/backup.sh"
fi

# Source output formatting library for format resolution
if [[ -f "$LIB_DIR/output-format.sh" ]]; then
  # shellcheck source=../lib/output-format.sh
  source "$LIB_DIR/output-format.sh"
fi

# Source error JSON library (includes exit-codes.sh)
# Note: error-json.sh sources exit-codes.sh, so we don't source it separately
if [[ -f "$LIB_DIR/error-json.sh" ]]; then
  # shellcheck source=../lib/error-json.sh
  source "$LIB_DIR/error-json.sh"
elif [[ -f "$LIB_DIR/exit-codes.sh" ]]; then
  # Fallback: source exit codes directly if error-json.sh not available
  # shellcheck source=../lib/exit-codes.sh
  source "$LIB_DIR/exit-codes.sh"
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

# Defaults
TASK_ID=""
SKIP_ARCHIVE=false
NOTES=""
SKIP_NOTES=false
FORMAT=""
DRY_RUN=false
QUIET=false

usage() {
  cat << EOF
Usage: claude-todo complete TASK_ID [OPTIONS]

Mark a task as complete (status='done') and set completedAt timestamp.

Arguments:
  TASK_ID                 Task ID to complete (e.g., T001)

Options:
  -n, --notes TEXT        Completion notes describing what was done (required)
  --skip-notes            Skip notes requirement (use for quick completions)
  --skip-archive          Don't trigger auto-archive even if configured
  -f, --format FORMAT     Output format: text (default) or json
  --human                 Force human-readable text output (same as --format text)
  --json                  Force JSON output (same as --format json)
  --dry-run               Show what would be completed without making changes
  -q, --quiet             Suppress informational messages
  -h, --help              Show this help

Notes Requirement:
  Completion notes are required by default for better task tracking and audit trails.
  Use --skip-notes to bypass this for quick completions.

  Good notes describe: what was done, how it was verified, and any relevant references
  (commit hashes, PR numbers, documentation links).

Output Formats:
  text    Human-readable output with colors and status messages (default for TTY)
  json    Machine-readable JSON with full task data (default for pipes/agents)

JSON Output Structure:
  {
    "_meta": {"command": "complete", "timestamp": "...", "version": "..."},
    "success": true,
    "taskId": "T042",
    "completedAt": "2025-12-17T10:00:00Z",
    "cycleTimeDays": 3.5,
    "archived": false,
    "task": { /* full completed task */ }
  }

Examples:
  claude-todo complete T001 --notes "Implemented auth middleware. Tested with unit tests."
  claude-todo complete T042 --notes "Fixed bug #123. PR merged."
  claude-todo complete T042 --skip-notes --skip-archive
  claude-todo complete T001 --json --notes "Done"     # JSON output for agents
  claude-todo complete T001 --format json             # Same as --json

After completion, if autoArchiveOnComplete is enabled in config,
the archive script will run automatically.
EOF
  exit 0
}

log_info()  { [[ "$QUIET" != true ]] && echo -e "${GREEN}[INFO]${NC} $1" || true; }
log_warn()  { [[ "$QUIET" != true ]] && echo -e "${YELLOW}[WARN]${NC} $1" || true; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Check dependencies
check_deps() {
  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
  fi
}

# Parse arguments
if [[ $# -eq 0 ]]; then
  log_error "Task ID required"
  usage
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) usage ;;
    -q|--quiet) QUIET=true; shift ;;
    -n|--notes)
      NOTES="${2:-}"
      if [[ -z "$NOTES" ]]; then
        log_error "--notes requires a text argument"
        exit 1
      fi
      shift 2
      ;;
    -f|--format)
      FORMAT="${2:-}"
      if [[ -z "$FORMAT" ]]; then
        log_error "--format requires an argument (text or json)"
        exit 1
      fi
      shift 2
      ;;
    --human) FORMAT="text"; shift ;;
    --json) FORMAT="json"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-notes) SKIP_NOTES=true; shift ;;
    --skip-archive) SKIP_ARCHIVE=true; shift ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) TASK_ID="$1"; shift ;;
  esac
done

# Resolve format (CLI > env > config > TTY-aware default)
if declare -f resolve_format >/dev/null 2>&1; then
  FORMAT=$(resolve_format "$FORMAT" true "text,json")
else
  # Fallback if output-format.sh not available
  FORMAT="${FORMAT:-text}"
fi

# Require notes unless --skip-notes is provided
if [[ -z "$NOTES" && "$SKIP_NOTES" == false ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_INPUT_MISSING" "Completion notes required. Use --notes 'description' or --skip-notes to bypass." \
      "${EXIT_INVALID_INPUT:-2}" true "Example: claude-todo complete $TASK_ID --notes 'Implemented feature. Tests passing.'"
    exit "${EXIT_INVALID_INPUT:-2}"
  else
    log_error "Completion notes required. Use --notes 'description' or --skip-notes to bypass."
    echo "" >&2
    echo "Example:" >&2
    echo "  claude-todo complete $TASK_ID --notes 'Implemented feature. Tests passing.'" >&2
    echo "  claude-todo complete $TASK_ID --skip-notes" >&2
    exit 1
  fi
fi

check_deps

# Validate task ID format
if [[ ! "$TASK_ID" =~ ^T[0-9]{3,}$ ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_TASK_INVALID_ID" "Invalid task ID format: $TASK_ID (must be T### format)" \
      "${EXIT_INVALID_INPUT:-2}" false "Task IDs must be in T### format (e.g., T001, T042)"
    exit "${EXIT_INVALID_INPUT:-2}"
  else
    log_error "Invalid task ID format: $TASK_ID (must be T### format)"
    exit 1
  fi
fi

# Check files exist
if [[ ! -f "$TODO_FILE" ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_NOT_INITIALIZED" "$TODO_FILE not found. Run claude-todo init first." \
      "${EXIT_FILE_ERROR:-3}" true "Run 'claude-todo init' to initialize the project"
    exit "${EXIT_FILE_ERROR:-3}"
  else
    log_error "$TODO_FILE not found. Run claude-todo init first."
    exit 1
  fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_NOT_INITIALIZED" "$CONFIG_FILE not found. Run claude-todo init first." \
      "${EXIT_FILE_ERROR:-3}" true "Run 'claude-todo init' to initialize the project"
    exit "${EXIT_FILE_ERROR:-3}"
  else
    log_error "$CONFIG_FILE not found. Run claude-todo init first."
    exit 1
  fi
fi

# Check for external modifications (informational, not blocking)
# Note: Checksum verification is for audit/detection, not write-gating.
# In multi-writer scenarios (TodoWrite + CLI), external modifications are expected.
CURRENT_CHECKSUM=$(jq -r '._meta.checksum // ""' "$TODO_FILE")
CURRENT_TASKS=$(jq -c '.tasks' "$TODO_FILE")
CALCULATED_CHECKSUM=$(echo "$CURRENT_TASKS" | sha256sum | cut -c1-16)

if [[ -n "$CURRENT_CHECKSUM" && "$CURRENT_CHECKSUM" != "$CALCULATED_CHECKSUM" ]]; then
  [[ "$FORMAT" != "json" ]] && log_info "External modification detected (checksum: $CURRENT_CHECKSUM → $CALCULATED_CHECKSUM)"
fi

# Check task exists
TASK=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TODO_FILE")

if [[ -z "$TASK" ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_TASK_NOT_FOUND" "Task $TASK_ID not found" \
      "${EXIT_NOT_FOUND:-4}" true "Use 'claude-todo list' to see available tasks or 'claude-todo exists $TASK_ID --include-archive' to check archive"
    exit "${EXIT_NOT_FOUND:-4}"
  else
    log_error "Task $TASK_ID not found"
    exit 1
  fi
fi

# Check current status
CURRENT_STATUS=$(echo "$TASK" | jq -r '.status')

# Capture createdAt for cycle time calculation
CREATED_AT=$(echo "$TASK" | jq -r '.createdAt // empty')

if [[ "$CURRENT_STATUS" == "done" ]]; then
  TASK_TITLE=$(echo "$TASK" | jq -r '.title')
  COMPLETED_AT=$(echo "$TASK" | jq -r '.completedAt')

  if [[ "$FORMAT" == "json" ]]; then
    # For JSON output, report this as already completed (not an error)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
      --arg version "$VERSION" \
      --arg timestamp "$TIMESTAMP" \
      --arg taskId "$TASK_ID" \
      --arg completedAt "$COMPLETED_AT" \
      --argjson task "$TASK" \
      '{
        "$schema": "https://claude-todo.dev/schemas/output.schema.json",
        "_meta": {
          "format": "json",
          "command": "complete",
          "timestamp": $timestamp,
          "version": $version
        },
        "success": true,
        "alreadyCompleted": true,
        "taskId": $taskId,
        "completedAt": $completedAt,
        "task": $task
      }'
    exit "${EXIT_NO_CHANGE:-102}"
  else
    log_warn "Task $TASK_ID is already completed"
    echo ""
    echo "Task: $TASK_TITLE"
    echo "Completed at: $COMPLETED_AT"
    exit 0
  fi
fi

# Validate status transition (pending/active/blocked → done)
if [[ ! "$CURRENT_STATUS" =~ ^(pending|active|blocked)$ ]]; then
  if declare -f output_error >/dev/null 2>&1; then
    output_error "$E_TASK_INVALID_STATUS" "Invalid status transition: $CURRENT_STATUS → done" \
      "${EXIT_VALIDATION_ERROR:-6}" false "Tasks can only be completed from pending, active, or blocked status"
    exit "${EXIT_VALIDATION_ERROR:-6}"
  else
    log_error "Invalid status transition: $CURRENT_STATUS → done"
    exit 1
  fi
fi

# DRY-RUN: Show what would be completed without making changes
if [[ "$DRY_RUN" == true ]]; then
  TASK_TITLE=$(echo "$TASK" | jq -r '.title')
  DRY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Calculate cycle time for dry-run preview
  DRY_CYCLE_TIME=""
  if [[ -n "$CREATED_AT" ]]; then
    CREATED_EPOCH=$(date -d "$CREATED_AT" +%s 2>/dev/null || echo "")
    DRY_EPOCH=$(date -d "$DRY_TIMESTAMP" +%s 2>/dev/null || echo "")
    if [[ -n "$CREATED_EPOCH" && -n "$DRY_EPOCH" ]]; then
      DIFF_SECONDS=$((DRY_EPOCH - CREATED_EPOCH))
      DRY_CYCLE_TIME=$(awk "BEGIN {printf \"%.1f\", $DIFF_SECONDS / 86400}")
    fi
  fi

  if [[ "$FORMAT" == "json" ]]; then
    jq -n \
      --arg version "$VERSION" \
      --arg timestamp "$DRY_TIMESTAMP" \
      --arg taskId "$TASK_ID" \
      --arg completedAt "$DRY_TIMESTAMP" \
      --arg cycleTime "${DRY_CYCLE_TIME:-null}" \
      --arg currentStatus "$CURRENT_STATUS" \
      --argjson task "$TASK" \
      '{
        "$schema": "https://claude-todo.dev/schemas/output.schema.json",
        "_meta": {
          "format": "json",
          "command": "complete",
          "timestamp": $timestamp,
          "version": $version
        },
        "success": true,
        "dryRun": true,
        "wouldComplete": {
          "taskId": $taskId,
          "title": $task.title,
          "currentStatus": $currentStatus,
          "completedAt": $completedAt,
          "cycleTimeDays": (if $cycleTime == "null" then null else ($cycleTime | tonumber) end)
        },
        "task": $task
      }'
  else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would complete task:"
    echo ""
    echo -e "${BLUE}Task:${NC} $TASK_TITLE"
    echo -e "${BLUE}ID:${NC} $TASK_ID"
    echo -e "${BLUE}Status:${NC} $CURRENT_STATUS → done"
    echo -e "${BLUE}Would Complete:${NC} $DRY_TIMESTAMP"
    if [[ -n "$NOTES" ]]; then
      echo -e "${BLUE}Notes:${NC} $NOTES"
    fi
    if [[ -n "$DRY_CYCLE_TIME" ]]; then
      echo -e "${BLUE}Cycle Time:${NC} ${DRY_CYCLE_TIME} days"
    fi
    echo ""
    echo -e "${YELLOW}No changes made (dry-run mode)${NC}"
  fi
  exit 0
fi

# Create safety backup before modification using unified backup library
if declare -f create_safety_backup >/dev/null 2>&1; then
  BACKUP_PATH=$(create_safety_backup "$TODO_FILE" "complete" 2>&1) || {
    [[ "$FORMAT" != "json" ]] && log_warn "Backup library failed, using fallback backup method"
    # Fallback to inline backup if library fails
    BACKUP_DIR=".claude/backups/safety"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="${BACKUP_DIR}/todo.json.$(date +%Y%m%d_%H%M%S)"
    cp "$TODO_FILE" "$BACKUP_FILE"
    BACKUP_PATH="$BACKUP_FILE"
  }
  [[ "$FORMAT" != "json" ]] && log_info "Backup created: $BACKUP_PATH"
else
  # Fallback if backup library not available
  BACKUP_DIR=".claude/backups/safety"
  mkdir -p "$BACKUP_DIR"
  BACKUP_FILE="${BACKUP_DIR}/todo.json.$(date +%Y%m%d_%H%M%S)"
  cp "$TODO_FILE" "$BACKUP_FILE"
  [[ "$FORMAT" != "json" ]] && log_info "Backup created: $BACKUP_FILE"
fi

# Capture before state
BEFORE_STATE=$(echo "$TASK" | jq '{status, completedAt}')

# Update task with completion
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(jq -r '._meta.activeSession // "system"' "$TODO_FILE")

# Update task: set status=done, add completedAt, clear blockedBy, and add completion note
if [[ -n "$NOTES" ]]; then
  COMPLETION_NOTE="[COMPLETED $TIMESTAMP] $NOTES"
  UPDATED_TASKS=$(jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" --arg note "$COMPLETION_NOTE" '
    .tasks |= map(
      if .id == $id then
        .status = "done" |
        .completedAt = $ts |
        del(.blockedBy) |
        .notes = ((.notes // []) + [$note])
      else . end
    )
  ' "$TODO_FILE") || {
    log_error "jq failed to update tasks (with notes)"
    exit 1
  }
else
  UPDATED_TASKS=$(jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" '
    .tasks |= map(
      if .id == $id then
        .status = "done" |
        .completedAt = $ts |
        del(.blockedBy)
      else . end
    )
  ' "$TODO_FILE") || {
    log_error "jq failed to update tasks (no notes)"
    exit 1
  }
fi

# Verify UPDATED_TASKS is valid JSON and not empty
if [[ -z "$UPDATED_TASKS" ]]; then
  log_error "Generated empty JSON structure"
  exit 1
fi

if ! echo "$UPDATED_TASKS" | jq empty 2>/dev/null; then
  log_error "Generated invalid JSON structure"
  echo "DEBUG: UPDATED_TASKS content:" >&2
  echo "$UPDATED_TASKS" >&2
  exit 1
fi

# Recalculate checksum
NEW_TASKS=$(echo "$UPDATED_TASKS" | jq -c '.tasks')
NEW_CHECKSUM=$(echo "$NEW_TASKS" | sha256sum | cut -c1-16)

# Update file with new checksum and lastUpdated
FINAL_JSON=$(echo "$UPDATED_TASKS" | jq --arg checksum "$NEW_CHECKSUM" --arg ts "$TIMESTAMP" '
  ._meta.checksum = $checksum |
  .lastUpdated = $ts
')

# Atomic write with file locking (prevents race conditions)
# Using save_json from lib/file-ops.sh which includes:
# - File locking to prevent concurrent writes
# - Atomic write with backup
# - JSON validation
# - Proper error handling
if ! save_json "$TODO_FILE" "$FINAL_JSON"; then
  log_error "Failed to write todo file. Rolling back."
  exit 1
fi

# Verify task was actually updated
VERIFY_STATUS=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
if [[ "$VERIFY_STATUS" != '"done"' ]]; then
  log_error "Failed to update task status."
  exit 1
fi

# Capture after state
AFTER_STATE=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | {status, completedAt}' "$TODO_FILE")

# Get full completed task for output
COMPLETED_TASK=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TODO_FILE")
TASK_TITLE=$(echo "$COMPLETED_TASK" | jq -r '.title')

# Calculate cycle time (days between created and completed)
CYCLE_TIME_DAYS=""
if [[ -n "$CREATED_AT" ]]; then
  # Calculate using date epoch conversion
  CREATED_EPOCH=$(date -d "$CREATED_AT" +%s 2>/dev/null || echo "")
  COMPLETED_EPOCH=$(date -d "$TIMESTAMP" +%s 2>/dev/null || echo "")

  if [[ -n "$CREATED_EPOCH" && -n "$COMPLETED_EPOCH" ]]; then
    # Calculate days with one decimal precision
    DIFF_SECONDS=$((COMPLETED_EPOCH - CREATED_EPOCH))
    # Use awk for floating point division
    CYCLE_TIME_DAYS=$(awk "BEGIN {printf \"%.1f\", $DIFF_SECONDS / 86400}")
  fi
fi

# Log the operation (before output, so log entry is created regardless of format)
if [[ -f "$LOG_SCRIPT" ]]; then
  if [[ "$FORMAT" == "json" ]]; then
    # Suppress all log output in JSON mode
    "$LOG_SCRIPT" \
      --action "status_changed" \
      --task-id "$TASK_ID" \
      --before "$BEFORE_STATE" \
      --after "$AFTER_STATE" \
      --details "{\"field\":\"status\",\"operation\":\"complete\"}" \
      --actor "system" >/dev/null 2>&1 || true
  else
    "$LOG_SCRIPT" \
      --action "status_changed" \
      --task-id "$TASK_ID" \
      --before "$BEFORE_STATE" \
      --after "$AFTER_STATE" \
      --details "{\"field\":\"status\",\"operation\":\"complete\"}" \
      --actor "system" 2>/dev/null || log_warn "Failed to write log entry"
  fi
fi

# Check if current focus was this task and clear it
FOCUS_CLEARED=false
CURRENT_FOCUS=$(jq -r '.focus.currentTask // ""' "$TODO_FILE")
if [[ "$CURRENT_FOCUS" == "$TASK_ID" ]]; then
  jq '.focus.currentTask = null' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
  FOCUS_CLEARED=true
  [[ "$FORMAT" != "json" ]] && log_info "Clearing focus from completed task"
fi

# Check auto-archive configuration
ARCHIVED=false
if [[ "$SKIP_ARCHIVE" == false ]]; then
  AUTO_ARCHIVE=$(jq -r '.archive.autoArchiveOnComplete // false' "$CONFIG_FILE")

  if [[ "$AUTO_ARCHIVE" == "true" ]]; then
    if [[ "$FORMAT" != "json" ]]; then
      echo ""
      log_info "Auto-archive is enabled, checking archive policy..."
    fi

    if [[ -f "$ARCHIVE_SCRIPT" ]]; then
      # Run archive script (suppress output for JSON mode)
      if [[ "$FORMAT" == "json" ]]; then
        "$ARCHIVE_SCRIPT" >/dev/null 2>&1 && ARCHIVED=true
      else
        "$ARCHIVE_SCRIPT" 2>&1 | sed 's/^/  /' || log_warn "Archive script encountered issues"
        ARCHIVED=true
      fi
    else
      [[ "$FORMAT" != "json" ]] && log_warn "Archive script not found at $ARCHIVE_SCRIPT"
    fi
  fi
fi

# Output based on format
if [[ "$FORMAT" == "json" ]]; then
  # Build JSON output with all completion details
  jq -n \
    --arg version "$VERSION" \
    --arg timestamp "$TIMESTAMP" \
    --arg taskId "$TASK_ID" \
    --arg completedAt "$TIMESTAMP" \
    --arg cycleTime "${CYCLE_TIME_DAYS:-null}" \
    --argjson archived "$ARCHIVED" \
    --argjson focusCleared "$FOCUS_CLEARED" \
    --argjson task "$COMPLETED_TASK" \
    '{
      "$schema": "https://claude-todo.dev/schemas/output.schema.json",
      "_meta": {
        "format": "json",
        "command": "complete",
        "timestamp": $timestamp,
        "version": $version
      },
      "success": true,
      "taskId": $taskId,
      "completedAt": $completedAt,
      "cycleTimeDays": (if $cycleTime == "null" then null else ($cycleTime | tonumber) end),
      "archived": $archived,
      "focusCleared": $focusCleared,
      "task": $task
    }'
else
  # Human-readable text output
  log_info "Task $TASK_ID marked as complete"
  echo ""
  echo -e "${BLUE}Task:${NC} $TASK_TITLE"
  echo -e "${BLUE}ID:${NC} $TASK_ID"
  echo -e "${BLUE}Status:${NC} $CURRENT_STATUS → done"
  echo -e "${BLUE}Completed:${NC} $TIMESTAMP"
  if [[ -n "$NOTES" ]]; then
    echo -e "${BLUE}Notes:${NC} $NOTES"
  fi
  if [[ -n "$CYCLE_TIME_DAYS" ]]; then
    echo -e "${BLUE}Cycle Time:${NC} ${CYCLE_TIME_DAYS} days"
  fi
  echo ""
  log_info "Task completion successful"
fi
