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

LOG_FILE="${LOG_FILE:-.claude/todo-log.json}"
TODO_FILE="${TODO_FILE:-.claude/todo.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Defaults
ACTION=""
TASK_ID=""
SESSION_ID=""
BEFORE=""
AFTER=""
DETAILS=""
ACTOR="claude"

VALID_ACTIONS="session_start session_end task_created task_updated status_changed task_archived focus_changed config_changed validation_run checksum_updated error_occurred"

usage() {
  cat << EOF
Usage: $(basename "$0") --action ACTION [OPTIONS]

Add an entry to todo-log.json.

Required:
  --action ACTION   One of: $VALID_ACTIONS

Options:
  --task-id ID      Task ID (for task-related actions)
  --session-id ID   Session ID
  --before JSON     State before change
  --after JSON      State after change
  --details JSON    Additional details
  --actor ACTOR     human|claude|system (default: claude)
  -h, --help        Show this help

Examples:
  $(basename "$0") --action session_start --session-id "session_20251205_..."
  $(basename "$0") --action status_changed --task-id T001 --before '{"status":"pending"}' --after '{"status":"active"}'
  $(basename "$0") --action task_created --task-id T005 --after '{"title":"New task"}'
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

# Parse arguments
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

if ! echo "$VALID_ACTIONS" | grep -qw "$ACTION"; then
  log_error "Invalid action: $ACTION"
  echo "Valid actions: $VALID_ACTIONS"
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
