#!/usr/bin/env bash
# CLAUDE-TODO Archive Script
# Archive completed tasks based on config rules
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

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
ARCHIVE_FILE="${ARCHIVE_FILE:-.claude/todo-archive.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
LOG_FILE="${LOG_FILE:-.claude/todo-log.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
DRY_RUN=false
FORCE=false
ARCHIVE_ALL=false
MAX_OVERRIDE=""

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Archive completed tasks from todo.json to todo-archive.json.

Options:
  --dry-run       Preview without making changes
  --force         Archive all completed (except preserved count)
  --all           Archive ALL completed tasks (bypasses retention AND preserve)
  --count N       Override maxCompletedTasks setting
  -h, --help      Show this help

Reads config from todo-config.json for:
  - daysUntilArchive: Days after completion before archiving
  - maxCompletedTasks: Threshold for completed tasks
  - preserveRecentCount: Number of recent completions to keep
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
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --all) ARCHIVE_ALL=true; shift ;;
    --count) MAX_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) shift ;;
  esac
done

check_deps

# Check files exist
for f in "$TODO_FILE" "$CONFIG_FILE"; do
  if [[ ! -f "$f" ]]; then
    log_error "$f not found"
    exit 1
  fi
done

# Create archive file if missing
if [[ ! -f "$ARCHIVE_FILE" ]]; then
  PROJECT=$(jq -r '.project' "$TODO_FILE")
  cat > "$ARCHIVE_FILE" << EOF
{
  "version": "$VERSION",
  "project": "$PROJECT",
  "_meta": { "totalArchived": 0, "lastArchived": null, "oldestTask": null, "newestTask": null },
  "archivedTasks": [],
  "statistics": { "byPhase": {}, "byPriority": {"critical":0,"high":0,"medium":0,"low":0}, "byLabel": {}, "averageCycleTime": null }
}
EOF
  log_info "Created $ARCHIVE_FILE"
fi

# Read config
DAYS_UNTIL_ARCHIVE=$(jq -r '.archive.daysUntilArchive // 7' "$CONFIG_FILE")
MAX_COMPLETED=$(jq -r '.archive.maxCompletedTasks // 15' "$CONFIG_FILE")
PRESERVE_COUNT=$(jq -r '.archive.preserveRecentCount // 3' "$CONFIG_FILE")

[[ -n "$MAX_OVERRIDE" ]] && MAX_COMPLETED="$MAX_OVERRIDE"

if [[ "$ARCHIVE_ALL" == true ]]; then
  log_warn "Mode: --all (bypassing retention AND preserve count)"
elif [[ "$FORCE" == true ]]; then
  log_info "Mode: --force (bypassing retention, preserving $PRESERVE_COUNT recent)"
else
  log_info "Config: daysUntilArchive=$DAYS_UNTIL_ARCHIVE, maxCompleted=$MAX_COMPLETED, preserve=$PRESERVE_COUNT"
fi

# Get completed tasks
COMPLETED_TASKS=$(jq '[.tasks[] | select(.status == "done")]' "$TODO_FILE")
COMPLETED_COUNT=$(echo "$COMPLETED_TASKS" | jq 'length')

log_info "Found $COMPLETED_COUNT completed tasks"

if [[ "$COMPLETED_COUNT" -eq 0 ]]; then
  log_info "No completed tasks to archive"
  exit 0
fi

# Calculate which tasks to archive
NOW=$(date +%s)
ARCHIVE_THRESHOLD=$((NOW - DAYS_UNTIL_ARCHIVE * 86400))

# Sort by completedAt (newest first) and determine which to archive
TASKS_TO_ARCHIVE=$(echo "$COMPLETED_TASKS" | jq --argjson threshold "$ARCHIVE_THRESHOLD" --argjson preserve "$PRESERVE_COUNT" --argjson force "$FORCE" --argjson all "$ARCHIVE_ALL" '
  sort_by(.completedAt) | reverse |
  to_entries |
  map(select(
    if $all then
      true  # Archive ALL completed tasks
    elif $force then
      .key >= $preserve  # Bypass retention, respect preserve count
    else
      .key >= $preserve and
      ((.value.completedAt | fromdateiso8601) < $threshold)
    end
  )) |
  map(.value)
')

ARCHIVE_COUNT=$(echo "$TASKS_TO_ARCHIVE" | jq 'length')

if [[ "$ARCHIVE_COUNT" -eq 0 ]]; then
  log_info "No tasks eligible for archiving (all within retention period or preserved)"
  exit 0
fi

log_info "Tasks to archive: $ARCHIVE_COUNT"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "DRY RUN - Would archive these tasks:"
  echo "$TASKS_TO_ARCHIVE" | jq -r '.[] | "  - \(.id): \(.title)"'
  echo ""
  echo "No changes made."
  exit 0
fi

# Get task IDs to archive
ARCHIVE_IDS=$(echo "$TASKS_TO_ARCHIVE" | jq -r '.[].id')

# Add archive metadata to tasks
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(jq -r '._meta.activeSession // "system"' "$TODO_FILE")

TASKS_WITH_METADATA=$(echo "$TASKS_TO_ARCHIVE" | jq --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" '
  map(. + {
    "_archive": {
      "archivedAt": $ts,
      "reason": "auto",
      "sessionId": $sid,
      "cycleTimeDays": (
        if .completedAt and .createdAt then
          (((.completedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 86400 | floor)
        else null end
      )
    }
  })
')

# Update archive file
jq --argjson tasks "$TASKS_WITH_METADATA" --arg ts "$TIMESTAMP" '
  .archivedTasks += $tasks |
  ._meta.totalArchived += ($tasks | length) |
  ._meta.lastArchived = $ts |
  ._meta.newestTask = ($tasks | max_by(.completedAt) | .completedAt) |
  ._meta.oldestTask = (if ._meta.oldestTask then ._meta.oldestTask else ($tasks | min_by(.completedAt) | .completedAt) end)
' "$ARCHIVE_FILE" > "${ARCHIVE_FILE}.tmp" && mv "${ARCHIVE_FILE}.tmp" "$ARCHIVE_FILE"

# Remove archived tasks from todo.json and update checksum
REMAINING_TASKS=$(jq --argjson ids "$(echo "$ARCHIVE_IDS" | jq -R . | jq -s .)" '
  .tasks | map(select(.id as $id | $ids | index($id) | not))
' "$TODO_FILE")

NEW_CHECKSUM=$(echo "$REMAINING_TASKS" | jq -c '.' | sha256sum | cut -c1-16)

jq --argjson tasks "$REMAINING_TASKS" --arg checksum "$NEW_CHECKSUM" --arg ts "$TIMESTAMP" '
  .tasks = $tasks |
  ._meta.checksum = $checksum |
  .lastUpdated = $ts
' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"

# Log the operation
if [[ -f "$LOG_FILE" ]]; then
  LOG_ID="log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 12)"
  jq --arg id "$LOG_ID" --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" --argjson count "$ARCHIVE_COUNT" --argjson ids "$(echo "$ARCHIVE_IDS" | jq -R . | jq -s .)" '
    .entries += [{
      "id": $id,
      "timestamp": $ts,
      "sessionId": $sid,
      "action": "task_archived",
      "actor": "system",
      "taskId": null,
      "before": null,
      "after": null,
      "details": {"count": $count, "taskIds": $ids}
    }] |
    ._meta.totalEntries += 1 |
    ._meta.lastEntry = $ts
  ' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

log_info "Archived $ARCHIVE_COUNT tasks"
echo ""
echo "Archived tasks:"
echo "$ARCHIVE_IDS" | while read -r id; do
  echo "  - $id"
done
