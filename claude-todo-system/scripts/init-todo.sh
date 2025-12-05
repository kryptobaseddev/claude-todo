#!/usr/bin/env bash
# CLAUDE-TODO Init Script v2.1.0
# Initialize the todo system in a project directory
set -euo pipefail

VERSION="2.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
FORCE=false
NO_CLAUDE_MD=false
PROJECT_NAME=""

usage() {
  cat << EOF
Usage: $(basename "$0") [PROJECT_NAME] [OPTIONS]

Initialize CLAUDE-TODO in the current directory.

Options:
  --force         Overwrite existing files
  --no-claude-md  Skip CLAUDE.md integration
  -h, --help      Show this help

Creates:
  todo.json         Active tasks
  todo-archive.json Completed tasks
  todo-config.json  Configuration
  todo-log.json     Change history
EOF
  exit 0
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

calculate_checksum() {
  # Calculate SHA-256 checksum of empty tasks array, truncated to 16 chars
  echo -n '[]' | sha256sum | cut -c1-16
}

generate_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE=true; shift ;;
    --no-claude-md) NO_CLAUDE_MD=true; shift ;;
    -h|--help) usage ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) PROJECT_NAME="$1"; shift ;;
  esac
done

# Determine project name
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME=$(basename "$PWD")
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# Check for existing files
if [[ -f ".claude/todo.json" ]] && [[ "$FORCE" != true ]]; then
  log_error ".claude/todo.json already exists. Use --force to overwrite."
  exit 1
fi

TIMESTAMP=$(generate_timestamp)
CHECKSUM=$(calculate_checksum)
TODO_DIR=".claude"

log_info "Initializing CLAUDE-TODO for project: $PROJECT_NAME"

# Create .claude directory
mkdir -p "$TODO_DIR"
log_info "Created $TODO_DIR/ directory"

# Create todo.json
cat > "$TODO_DIR/todo.json" << EOF
{
  "\$schema": "./schemas/todo.schema.json",
  "version": "$VERSION",
  "project": "$PROJECT_NAME",
  "lastUpdated": "$TIMESTAMP",
  "_meta": {
    "checksum": "$CHECKSUM",
    "configVersion": "$VERSION",
    "lastSessionId": null,
    "activeSession": null
  },
  "focus": {
    "currentTask": null,
    "blockedUntil": null,
    "sessionNote": null,
    "nextAction": null
  },
  "tasks": [],
  "phases": {
    "setup": { "order": 1, "name": "Setup & Foundation" },
    "core": { "order": 2, "name": "Core Development" },
    "polish": { "order": 3, "name": "Polish & Launch" }
  },
  "labels": {}
}
EOF
log_info "Created $TODO_DIR/todo.json"

# Create todo-archive.json
cat > "$TODO_DIR/todo-archive.json" << EOF
{
  "\$schema": "./schemas/archive.schema.json",
  "version": "$VERSION",
  "project": "$PROJECT_NAME",
  "_meta": {
    "totalArchived": 0,
    "lastArchived": null,
    "oldestTask": null,
    "newestTask": null
  },
  "archivedTasks": [],
  "statistics": {
    "byPhase": {},
    "byPriority": { "critical": 0, "high": 0, "medium": 0, "low": 0 },
    "byLabel": {},
    "averageCycleTime": null
  }
}
EOF
log_info "Created $TODO_DIR/todo-archive.json"

# Create todo-config.json
cat > "$TODO_DIR/todo-config.json" << EOF
{
  "\$schema": "./schemas/config.schema.json",
  "version": "$VERSION",
  "archive": {
    "enabled": true,
    "daysUntilArchive": 7,
    "maxCompletedTasks": 15,
    "preserveRecentCount": 3,
    "archiveOnSessionEnd": true
  },
  "logging": {
    "enabled": true,
    "retentionDays": 30,
    "level": "standard",
    "logSessionEvents": true
  },
  "validation": {
    "strictMode": false,
    "checksumEnabled": true,
    "enforceAcceptance": true,
    "requireDescription": false,
    "maxActiveTasks": 1,
    "validateDependencies": true,
    "detectCircularDeps": true
  },
  "defaults": {
    "priority": "medium",
    "phase": "core",
    "labels": []
  },
  "session": {
    "requireSessionNote": true,
    "warnOnNoFocus": true,
    "autoStartSession": true,
    "sessionTimeoutHours": 24
  },
  "display": {
    "showArchiveCount": true,
    "showLogSummary": true,
    "warnStaleDays": 30
  }
}
EOF
log_info "Created $TODO_DIR/todo-config.json"

# Create todo-log.json
cat > "$TODO_DIR/todo-log.json" << EOF
{
  "\$schema": "./schemas/log.schema.json",
  "version": "$VERSION",
  "project": "$PROJECT_NAME",
  "_meta": {
    "totalEntries": 1,
    "firstEntry": "$TIMESTAMP",
    "lastEntry": "$TIMESTAMP",
    "entriesPruned": 0
  },
  "entries": [
    {
      "id": "log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 12)",
      "timestamp": "$TIMESTAMP",
      "sessionId": null,
      "action": "task_created",
      "actor": "system",
      "taskId": null,
      "before": null,
      "after": null,
      "details": "CLAUDE-TODO system initialized for project: $PROJECT_NAME"
    }
  ]
}
EOF
log_info "Created $TODO_DIR/todo-log.json"

# Update CLAUDE.md
if [[ "$NO_CLAUDE_MD" != true ]]; then
  if [[ -f "CLAUDE.md" ]]; then
    if grep -q "CLAUDE-TODO:START" CLAUDE.md 2>/dev/null; then
      log_warn "CLAUDE.md already has task integration (skipped)"
    else
      # Read the template from install location or embed minimal version
      cat >> CLAUDE.md << 'CLAUDE_EOF'

<!-- CLAUDE-TODO:START -->
## Task Management

Tasks in `.claude/todo.json`. **Read at session start, verify checksum.**

### Protocol
- **START**: Read .claude/todo-config.json → Read .claude/todo.json → Verify checksum → Log session_start
- **WORK**: ONE active task only → Update notes → Log changes to .claude/todo-log.json
- **END**: Update sessionNote → Update checksum → Log session_end

### Anti-Hallucination
- **ALWAYS** verify checksum before writing
- **NEVER** have 2+ active tasks
- **NEVER** modify .claude/todo-archive.json
- **ALWAYS** log all changes

### Files
- `.claude/todo.json` - Active tasks
- `.claude/todo-archive.json` - Completed (immutable)
- `.claude/todo-config.json` - Settings
- `.claude/todo-log.json` - Audit trail
<!-- CLAUDE-TODO:END -->
CLAUDE_EOF
      log_info "Updated CLAUDE.md"
    fi
  else
    log_warn "No CLAUDE.md found (skipped)"
  fi
fi

echo ""
echo -e "${GREEN}CLAUDE-TODO initialized successfully!${NC}"
echo ""
echo "Files created in .claude/:"
echo "  - .claude/todo.json         (active tasks)"
echo "  - .claude/todo-archive.json (completed tasks)"
echo "  - .claude/todo-config.json  (settings)"
echo "  - .claude/todo-log.json     (change history)"
echo ""
echo "Add to .gitignore (recommended):"
echo "  .claude/*.json"
echo ""
echo "Next steps:"
echo "  1. Add your first task to .claude/todo.json"
echo "  2. Set focus.currentTask when starting work"
echo "  3. Always verify checksum before modifying"
