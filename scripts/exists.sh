#!/usr/bin/env bash
# CLAUDE-TODO Exists Command
# Check if a task ID exists without listing all tasks
# Provides clean exit codes for scripting and CI/CD integration
set -uo pipefail

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
ARCHIVE_FILE="${ARCHIVE_FILE:-.claude/todo-archive.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging library for should_use_color function
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "$LIB_DIR/logging.sh" ]]; then
  source "$LIB_DIR/logging.sh"
fi

# Colors (respects NO_COLOR and FORCE_COLOR environment variables)
if declare -f should_use_color >/dev/null 2>&1 && should_use_color; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' NC=''
fi

# Exit codes
EXIT_EXISTS=0
EXIT_NOT_FOUND=1
EXIT_INVALID_ID=2
EXIT_FILE_ERROR=3

# Options
QUIET=false
VERBOSE=false
INCLUDE_ARCHIVE=false
FORMAT="text"

usage() {
  cat << EOF
Usage: claude-todo exists <task-id> [OPTIONS]

Check if a task ID exists without listing all tasks.

Arguments:
  <task-id>           Task ID to check (e.g., T001)

Options:
  --quiet             No output, exit code only
  --verbose           Show which file contains the task
  --include-archive   Search archive file too
  --format <format>   Output format: text (default) or json
  --help              Show this help message

Exit Codes:
  0  Task exists
  1  Task not found
  2  Invalid task ID format
  3  File read error

Examples:
  # Basic check
  claude-todo exists T001

  # Silent check for scripting
  if claude-todo exists T001 --quiet; then
    echo "Task exists"
  fi

  # Check with archive
  claude-todo exists T050 --include-archive

  # JSON output
  claude-todo exists T001 --format json
EOF
}

# Validate task ID format (T followed by 3+ digits)
validate_task_id() {
  local id="$1"
  [[ "$id" =~ ^T[0-9]{3,}$ ]]
}

# Check if task exists in a file
task_exists_in_file() {
  local task_id="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  if ! jq -e --arg id "$task_id" '.tasks[] | select(.id == $id)' "$file" > /dev/null 2>&1; then
    return 1
  fi

  return 0
}

# Main function
main() {
  local task_id=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet)
        QUIET=true
        ;;
      --verbose)
        VERBOSE=true
        ;;
      --include-archive)
        INCLUDE_ARCHIVE=true
        ;;
      --format)
        if [[ $# -lt 2 ]]; then
          echo -e "${RED}[ERROR]${NC} --format requires a value" >&2
          exit $EXIT_INVALID_ID
        fi
        FORMAT="$2"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      -*)
        echo -e "${RED}[ERROR]${NC} Unknown option: $1" >&2
        usage >&2
        exit $EXIT_INVALID_ID
        ;;
      *)
        if [[ -z "$task_id" ]]; then
          task_id="$1"
        else
          echo -e "${RED}[ERROR]${NC} Multiple task IDs provided" >&2
          exit $EXIT_INVALID_ID
        fi
        ;;
    esac
    shift
  done

  # Require task ID
  if [[ -z "$task_id" ]]; then
    if [[ "$QUIET" == false ]]; then
      echo -e "${RED}[ERROR]${NC} Task ID required" >&2
      usage >&2
    fi
    exit $EXIT_INVALID_ID
  fi

  # Validate task ID format
  if ! validate_task_id "$task_id"; then
    if [[ "$QUIET" == false ]]; then
      echo -e "${RED}[ERROR]${NC} Invalid task ID format: $task_id (expected: T001, T002, etc.)" >&2
    fi
    exit $EXIT_INVALID_ID
  fi

  # Check todo.json exists
  if [[ ! -f "$TODO_FILE" ]]; then
    if [[ "$QUIET" == false ]]; then
      echo -e "${RED}[ERROR]${NC} Todo file not found: $TODO_FILE" >&2
    fi
    exit $EXIT_FILE_ERROR
  fi

  local found=false
  local location=""

  # Check todo.json
  if task_exists_in_file "$task_id" "$TODO_FILE"; then
    found=true
    location="todo.json"
  fi

  # Check archive if requested and not found yet
  if [[ "$INCLUDE_ARCHIVE" == true && "$found" == false ]]; then
    if [[ -f "$ARCHIVE_FILE" ]]; then
      if task_exists_in_file "$task_id" "$ARCHIVE_FILE"; then
        found=true
        location="todo-archive.json"
      fi
    fi
  fi

  # Output handling
  if [[ "$found" == true ]]; then
    if [[ "$QUIET" == false ]]; then
      if [[ "$FORMAT" == "json" ]]; then
        jq -n --arg id "$task_id" --arg loc "$location" \
          '{exists: true, taskId: $id, location: $loc}'
      elif [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}[EXISTS]${NC} Task $task_id found in $location"
      else
        echo -e "${GREEN}[EXISTS]${NC} Task $task_id exists"
      fi
    fi
    exit $EXIT_EXISTS
  else
    if [[ "$QUIET" == false ]]; then
      if [[ "$FORMAT" == "json" ]]; then
        jq -n --arg id "$task_id" --argjson archive "$INCLUDE_ARCHIVE" \
          '{exists: false, taskId: $id, searchedArchive: $archive}'
      else
        local msg="Task $task_id not found"
        [[ "$INCLUDE_ARCHIVE" == true ]] && msg="$msg (searched archive too)"
        echo -e "${YELLOW}[NOT FOUND]${NC} $msg"
      fi
    fi
    exit $EXIT_NOT_FOUND
  fi
}

main "$@"
