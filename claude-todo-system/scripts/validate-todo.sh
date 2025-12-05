#!/usr/bin/env bash
# CLAUDE-TODO Validate Script v2.1.0
# Validate todo.json against schema and business rules
set -uo pipefail
# Note: Not using -e because we track errors manually

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
STRICT=false
FIX=false
JSON_OUTPUT=false

ERRORS=0
WARNINGS=0

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Validate todo.json against schema and business rules.

Options:
  --strict    Treat warnings as errors
  --fix       Auto-fix simple issues
  --json      Output as JSON
  -h, --help  Show this help

Validations:
  - JSON syntax
  - Only ONE active task
  - All depends[] references exist
  - No circular dependencies
  - blocked tasks have blockedBy
  - done tasks have completedAt
  - focus.currentTask matches active task
  - Checksum integrity
EOF
  exit 0
}

log_error() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    echo "{\"level\":\"error\",\"message\":\"$1\"}"
  else
    echo -e "${RED}[ERROR]${NC} $1"
  fi
  ((ERRORS++))
}

log_warn() {
  if [[ "$JSON_OUTPUT" == true ]]; then
    echo "{\"level\":\"warning\",\"message\":\"$1\"}"
  else
    echo -e "${YELLOW}[WARN]${NC} $1"
  fi
  ((WARNINGS++))
}

log_info() {
  if [[ "$JSON_OUTPUT" != true ]]; then
    echo -e "${GREEN}[OK]${NC} $1"
  fi
}

# Check dependencies
check_deps() {
  if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed" >&2
    exit 1
  fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict) STRICT=true; shift ;;
    --fix) FIX=true; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) shift ;;
  esac
done

check_deps

# Check file exists
if [[ ! -f "$TODO_FILE" ]]; then
  log_error "File not found: $TODO_FILE"
  exit 1
fi

# 1. JSON syntax
if ! jq empty "$TODO_FILE" 2>/dev/null; then
  log_error "Invalid JSON syntax"
  exit 1
fi
log_info "JSON syntax valid"

# 2. Check only ONE active task
ACTIVE_COUNT=$(jq '[.tasks[] | select(.status == "active")] | length' "$TODO_FILE")
if [[ "$ACTIVE_COUNT" -gt 1 ]]; then
  log_error "Multiple active tasks found ($ACTIVE_COUNT). Only ONE allowed."
  if [[ "$FIX" == true ]]; then
    # Keep only the first active task
    FIRST_ACTIVE=$(jq -r '[.tasks[] | select(.status == "active")][0].id' "$TODO_FILE")
    jq --arg keep "$FIRST_ACTIVE" '
      .tasks |= map(if .status == "active" and .id != $keep then .status = "pending" else . end)
    ' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
    echo "  Fixed: Set all but $FIRST_ACTIVE to pending"
  fi
elif [[ "$ACTIVE_COUNT" -eq 1 ]]; then
  log_info "Single active task"
else
  log_info "No active tasks"
fi

# 3. Check all depends[] references exist
TASK_IDS=$(jq -r '[.tasks[].id] | @json' "$TODO_FILE")
MISSING_DEPS=$(jq --argjson ids "$TASK_IDS" '
  [.tasks[] | select(.depends != null) | .depends[] | select(. as $d | $ids | index($d) | not)]
' "$TODO_FILE")
MISSING_COUNT=$(echo "$MISSING_DEPS" | jq 'length')
if [[ "$MISSING_COUNT" -gt 0 ]]; then
  log_error "Missing dependency references: $(echo "$MISSING_DEPS" | jq -r 'join(", ")')"
else
  log_info "All dependencies exist"
fi

# 4. Check for circular dependencies (2-level)
CIRCULARS=$(jq '
  .tasks as $tasks |
  [.tasks[] | select(.depends != null) |
   . as $task |
   .depends[] |
   . as $dep |
   ($tasks[] | select(.id == $dep and .depends != null) | .depends[] | select(. == $task.id)) |
   {task: $task.id, dep: $dep}
  ]
' "$TODO_FILE")
CIRCULAR_COUNT=$(echo "$CIRCULARS" | jq 'length')
if [[ "$CIRCULAR_COUNT" -gt 0 ]]; then
  log_error "Circular dependencies detected: $(echo "$CIRCULARS" | jq -c '.')"
else
  log_info "No circular dependencies"
fi

# 5. Check blocked tasks have blockedBy
BLOCKED_NO_REASON=$(jq '[.tasks[] | select(.status == "blocked" and (.blockedBy == null or .blockedBy == ""))] | length' "$TODO_FILE")
if [[ "$BLOCKED_NO_REASON" -gt 0 ]]; then
  log_error "$BLOCKED_NO_REASON blocked task(s) missing blockedBy reason"
else
  log_info "All blocked tasks have reasons"
fi

# 6. Check done tasks have completedAt
DONE_NO_DATE=$(jq '[.tasks[] | select(.status == "done" and (.completedAt == null or .completedAt == ""))] | length' "$TODO_FILE")
if [[ "$DONE_NO_DATE" -gt 0 ]]; then
  log_error "$DONE_NO_DATE done task(s) missing completedAt"
  if [[ "$FIX" == true ]]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg now "$NOW" '
      .tasks |= map(if .status == "done" and (.completedAt == null or .completedAt == "") then .completedAt = $now else . end)
    ' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
    echo "  Fixed: Set completedAt to now"
  fi
else
  log_info "All done tasks have completedAt"
fi

# 7. Check focus.currentTask matches active task
FOCUS_TASK=$(jq -r '.focus.currentTask // ""' "$TODO_FILE")
ACTIVE_TASK=$(jq -r '[.tasks[] | select(.status == "active")][0].id // ""' "$TODO_FILE")
if [[ -n "$FOCUS_TASK" ]] && [[ "$FOCUS_TASK" != "$ACTIVE_TASK" ]]; then
  log_error "focus.currentTask ($FOCUS_TASK) doesn't match active task ($ACTIVE_TASK)"
  if [[ "$FIX" == true ]]; then
    if [[ -n "$ACTIVE_TASK" ]]; then
      jq --arg task "$ACTIVE_TASK" '.focus.currentTask = $task' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
      echo "  Fixed: Set focus.currentTask to $ACTIVE_TASK"
    else
      jq '.focus.currentTask = null' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
      echo "  Fixed: Cleared focus.currentTask"
    fi
  fi
elif [[ -z "$FOCUS_TASK" ]] && [[ -n "$ACTIVE_TASK" ]]; then
  log_warn "Active task ($ACTIVE_TASK) but focus.currentTask is null"
  if [[ "$FIX" == true ]]; then
    jq --arg task "$ACTIVE_TASK" '.focus.currentTask = $task' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
    echo "  Fixed: Set focus.currentTask to $ACTIVE_TASK"
  fi
else
  log_info "Focus matches active task"
fi

# 8. Verify checksum
STORED_CHECKSUM=$(jq -r '._meta.checksum // ""' "$TODO_FILE")
if [[ -n "$STORED_CHECKSUM" ]]; then
  COMPUTED_CHECKSUM=$(jq -c '.tasks' "$TODO_FILE" | sha256sum | cut -c1-16)
  if [[ "$STORED_CHECKSUM" != "$COMPUTED_CHECKSUM" ]]; then
    log_error "Checksum mismatch: stored=$STORED_CHECKSUM, computed=$COMPUTED_CHECKSUM"
    if [[ "$FIX" == true ]]; then
      jq --arg cs "$COMPUTED_CHECKSUM" '._meta.checksum = $cs' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"
      echo "  Fixed: Updated checksum"
    fi
  else
    log_info "Checksum valid"
  fi
else
  log_warn "No checksum found"
fi

# 9. WARNINGS: Stale tasks
STALE_DAYS=30
STALE_THRESHOLD=$(($(date +%s) - STALE_DAYS * 86400))
STALE_TASKS=$(jq --argjson threshold "$STALE_THRESHOLD" '
  [.tasks[] | select(.status == "pending" and .createdAt != null and ((.createdAt | fromdateiso8601) < $threshold))]
' "$TODO_FILE" 2>/dev/null || echo "[]")
STALE_COUNT=$(echo "$STALE_TASKS" | jq 'length')
if [[ "$STALE_COUNT" -gt 0 ]]; then
  log_warn "$STALE_COUNT task(s) pending for >$STALE_DAYS days"
fi

# Summary
echo ""
if [[ "$JSON_OUTPUT" == true ]]; then
  echo "{\"errors\":$ERRORS,\"warnings\":$WARNINGS,\"valid\":$([[ $ERRORS -eq 0 ]] && echo true || echo false)}"
else
  if [[ "$ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}Validation passed${NC} ($WARNINGS warnings)"
    exit 0
  else
    echo -e "${RED}Validation failed${NC} ($ERRORS errors, $WARNINGS warnings)"
    if [[ "$STRICT" == true ]] && [[ "$WARNINGS" -gt 0 ]]; then
      exit 1
    fi
    exit 1
  fi
fi
