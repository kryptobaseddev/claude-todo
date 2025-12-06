#!/usr/bin/env bash
# CLAUDE-TODO Complete Task Script
# Mark a task as complete and optionally trigger archive
set -euo pipefail

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="${SCRIPT_DIR}/log.sh"
ARCHIVE_SCRIPT="${SCRIPT_DIR}/archive.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
TASK_ID=""
SKIP_ARCHIVE=false

usage() {
  cat << EOF
Usage: $(basename "$0") TASK_ID [OPTIONS]

Mark a task as complete (status='done') and set completedAt timestamp.

Arguments:
  TASK_ID         Task ID to complete (e.g., T001)

Options:
  --skip-archive  Don't trigger auto-archive even if configured
  -h, --help      Show this help

Examples:
  $(basename "$0") T001
  $(basename "$0") T042 --skip-archive

After completion, if auto_archive_on_complete is enabled in config,
the archive script will run automatically.
EOF
  exit 0
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
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
    --skip-archive) SKIP_ARCHIVE=true; shift ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) TASK_ID="$1"; shift ;;
  esac
done

check_deps

# Validate task ID format
if [[ ! "$TASK_ID" =~ ^T[0-9]{3,}$ ]]; then
  log_error "Invalid task ID format: $TASK_ID (must be T### format)"
  exit 1
fi

# Check files exist
if [[ ! -f "$TODO_FILE" ]]; then
  log_error "$TODO_FILE not found. Run init.sh first."
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_error "$CONFIG_FILE not found. Run init.sh first."
  exit 1
fi

# Verify checksum before modification
CURRENT_CHECKSUM=$(jq -r '._meta.checksum' "$TODO_FILE")
CURRENT_TASKS=$(jq -c '.tasks' "$TODO_FILE")
CALCULATED_CHECKSUM=$(echo "$CURRENT_TASKS" | sha256sum | cut -c1-16)

if [[ "$CURRENT_CHECKSUM" != "$CALCULATED_CHECKSUM" ]]; then
  log_error "Checksum mismatch! File may be corrupted or modified externally."
  log_error "Expected: $CURRENT_CHECKSUM, Got: $CALCULATED_CHECKSUM"
  exit 1
fi

# Check task exists
TASK=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TODO_FILE")

if [[ -z "$TASK" ]]; then
  log_error "Task $TASK_ID not found"
  exit 1
fi

# Check current status
CURRENT_STATUS=$(echo "$TASK" | jq -r '.status')

if [[ "$CURRENT_STATUS" == "done" ]]; then
  log_warn "Task $TASK_ID is already completed"
  TASK_TITLE=$(echo "$TASK" | jq -r '.title')
  COMPLETED_AT=$(echo "$TASK" | jq -r '.completedAt')
  echo ""
  echo "Task: $TASK_TITLE"
  echo "Completed at: $COMPLETED_AT"
  exit 0
fi

# Validate status transition (pending/active/blocked → done)
if [[ ! "$CURRENT_STATUS" =~ ^(pending|active|blocked)$ ]]; then
  log_error "Invalid status transition: $CURRENT_STATUS → done"
  exit 1
fi

# Create backup before modification
BACKUP_DIR=".claude/.backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/todo.json.$(date +%Y%m%d_%H%M%S)"
cp "$TODO_FILE" "$BACKUP_FILE"
log_info "Backup created: $BACKUP_FILE"

# Capture before state
BEFORE_STATE=$(echo "$TASK" | jq '{status, completedAt}')

# Update task with completion
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(jq -r '._meta.activeSession // "system"' "$TODO_FILE")

# Update task: set status=done, add completedAt, clear blockedBy if present
UPDATED_TASKS=$(jq --arg id "$TASK_ID" --arg ts "$TIMESTAMP" '
  .tasks |= map(
    if .id == $id then
      .status = "done" |
      .completedAt = $ts |
      del(.blockedBy)
    else . end
  )
' "$TODO_FILE")

# Recalculate checksum
NEW_TASKS=$(echo "$UPDATED_TASKS" | jq -c '.tasks')
NEW_CHECKSUM=$(echo "$NEW_TASKS" | sha256sum | cut -c1-16)

# Update file with new checksum and lastUpdated
FINAL_JSON=$(echo "$UPDATED_TASKS" | jq --arg checksum "$NEW_CHECKSUM" --arg ts "$TIMESTAMP" '
  ._meta.checksum = $checksum |
  .lastUpdated = $ts
')

# Atomic write
echo "$FINAL_JSON" > "${TODO_FILE}.tmp"

# Validate the updated file structure
if ! jq empty "${TODO_FILE}.tmp" 2>/dev/null; then
  log_error "Generated invalid JSON. Rolling back."
  rm -f "${TODO_FILE}.tmp"
  exit 1
fi

# Verify task was actually updated
VERIFY_STATUS=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | .status' "${TODO_FILE}.tmp")
if [[ "$VERIFY_STATUS" != '"done"' ]]; then
  log_error "Failed to update task status. Rolling back."
  rm -f "${TODO_FILE}.tmp"
  exit 1
fi

# Commit changes
mv "${TODO_FILE}.tmp" "$TODO_FILE"

# Capture after state
AFTER_STATE=$(jq --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | {status, completedAt}' "$TODO_FILE")

# Get task details for display
TASK_TITLE=$(jq --arg id "$TASK_ID" -r '.tasks[] | select(.id == $id) | .title' "$TODO_FILE")

log_info "Task $TASK_ID marked as complete"
echo ""
echo -e "${BLUE}Task:${NC} $TASK_TITLE"
echo -e "${BLUE}ID:${NC} $TASK_ID"
echo -e "${BLUE}Status:${NC} $CURRENT_STATUS → done"
echo -e "${BLUE}Completed:${NC} $TIMESTAMP"

# Log the operation
if [[ -f "$LOG_SCRIPT" ]]; then
  "$LOG_SCRIPT" \
    --action "status_changed" \
    --task-id "$TASK_ID" \
    --before "$BEFORE_STATE" \
    --after "$AFTER_STATE" \
    --details "{\"field\":\"status\",\"operation\":\"complete\"}" \
    --actor "system" 2>/dev/null || log_warn "Failed to write log entry"
fi

# Check if current focus was this task and clear it
CURRENT_FOCUS=$(jq -r '.focus.currentTask // ""' "$TODO_FILE")
if [[ "$CURRENT_FOCUS" == "$TASK_ID" ]]; then
  log_info "Clearing focus from completed task"
  jq '.focus.currentTask = null' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
fi

# Check auto-archive configuration
if [[ "$SKIP_ARCHIVE" == false ]]; then
  AUTO_ARCHIVE=$(jq -r '.archive.auto_archive_on_complete // false' "$CONFIG_FILE")

  if [[ "$AUTO_ARCHIVE" == "true" ]]; then
    echo ""
    log_info "Auto-archive is enabled, checking archive policy..."

    if [[ -f "$ARCHIVE_SCRIPT" ]]; then
      # Run archive script
      "$ARCHIVE_SCRIPT" 2>&1 | sed 's/^/  /' || log_warn "Archive script encountered issues"
    else
      log_warn "Archive script not found at $ARCHIVE_SCRIPT"
    fi
  fi
fi

echo ""
log_info "✓ Task completion successful"
