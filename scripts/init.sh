#!/usr/bin/env bash
# CLAUDE-TODO Init Script
# Initialize the todo system in a project directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Source version from central location
if [[ -f "$CLAUDE_TODO_HOME/VERSION" ]]; then
  VERSION="$(cat "$CLAUDE_TODO_HOME/VERSION" | tr -d '[:space:]')"
elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
  VERSION="$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')"
else
  VERSION="unknown"
fi

# Unset any existing log functions to prevent conflicts on re-initialization
unset -f log_info log_error log_warn log_debug 2>/dev/null || true

# Guard for re-sourcing libraries
if [[ -n "${_INIT_LOGGING_SOURCED:-}" ]]; then
    # Already sourced, skip
    :
else
    # Source library functions
    if [[ -f "$CLAUDE_TODO_HOME/lib/logging.sh" ]]; then
        source "$CLAUDE_TODO_HOME/lib/logging.sh"
        _INIT_LOGGING_SOURCED=true
    fi
fi

# Always define console logging functions (lib/logging.sh provides task logging, not console output)
log_info()    { echo "[INFO] $1"; }
log_warn()    { echo "[WARN] $1" >&2; }
log_success() { echo "[SUCCESS] $1"; }
# Only define log_error if not already defined by library
type -t log_error &>/dev/null || log_error() { echo "[ERROR] $1" >&2; }

# Optional: source other libraries if needed (with guards)
if [[ -z "${_INIT_FILE_OPS_SOURCED:-}" ]]; then
    [[ -f "$CLAUDE_TODO_HOME/lib/file-ops.sh" ]] && source "$CLAUDE_TODO_HOME/lib/file-ops.sh" && _INIT_FILE_OPS_SOURCED=true || true
fi
if [[ -z "${_INIT_VALIDATION_SOURCED:-}" ]]; then
    [[ -f "$CLAUDE_TODO_HOME/lib/validation.sh" ]] && source "$CLAUDE_TODO_HOME/lib/validation.sh" && _INIT_VALIDATION_SOURCED=true || true
fi
if [[ -z "${_INIT_BACKUP_SOURCED:-}" ]]; then
    [[ -f "$CLAUDE_TODO_HOME/lib/backup.sh" ]] && source "$CLAUDE_TODO_HOME/lib/backup.sh" && _INIT_BACKUP_SOURCED=true || true
fi

# Defaults
FORCE=false
NO_CLAUDE_MD=false
UPDATE_CLAUDE_MD=false
PROJECT_NAME=""
FORMAT=""
QUIET=false
COMMAND_NAME="init"

# Source output formatting and error libraries
LIB_DIR="$CLAUDE_TODO_HOME/lib"
if [[ -f "$LIB_DIR/output-format.sh" ]]; then
  source "$LIB_DIR/output-format.sh"
fi
if [[ -f "$LIB_DIR/exit-codes.sh" ]]; then
  source "$LIB_DIR/exit-codes.sh"
fi
if [[ -f "$LIB_DIR/error-json.sh" ]]; then
  source "$LIB_DIR/error-json.sh"
fi

usage() {
  cat << EOF
Usage: claude-todo init [PROJECT_NAME] [OPTIONS]

Initialize CLAUDE-TODO in the current directory.

Options:
  --force             Overwrite existing files
  --no-claude-md      Skip CLAUDE.md integration
  --update-claude-md  Update existing CLAUDE.md injection (idempotent)
  -f, --format FMT    Output format: text, json (default: auto-detect)
  --human             Force human-readable text output
  --json              Force JSON output
  -q, --quiet         Suppress non-essential output
  -h, --help          Show this help

Creates:
  .claude/todo.json         Active tasks
  .claude/todo-archive.json Completed tasks
  .claude/todo-config.json  Configuration
  .claude/todo-log.json     Change history
  .claude/schemas/          JSON Schema files
  .claude/.backups/         Backup directory

JSON Output:
  {
    "_meta": {"command": "init", "timestamp": "..."},
    "success": true,
    "initialized": {"directory": ".claude", "files": ["todo.json", ...]}
  }

Examples:
  claude-todo init                    # Initialize in current directory
  claude-todo init my-project         # Initialize with project name
  claude-todo init --json             # JSON output for scripting
  claude-todo init --update-claude-md # Update CLAUDE.md injection
EOF
  exit 0
}

calculate_checksum() {
  # Calculate SHA-256 checksum of empty tasks array, truncated to 16 chars
  # Must match validate.sh: jq -c '.tasks' outputs with newline
  echo '[]' | sha256sum | cut -c1-16
}

generate_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE=true; shift ;;
    --no-claude-md) NO_CLAUDE_MD=true; shift ;;
    --update-claude-md) UPDATE_CLAUDE_MD=true; shift ;;
    -f|--format) FORMAT="$2"; shift 2 ;;
    --human) FORMAT="text"; shift ;;
    --json) FORMAT="json"; shift ;;
    -q|--quiet) QUIET=true; shift ;;
    -h|--help) usage ;;
    -*)
      if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
        output_error "$E_INPUT_INVALID" "Unknown option: $1" "${EXIT_INVALID_INPUT:-1}" true "Run 'claude-todo init --help' for usage"
      else
        output_error "$E_INPUT_INVALID" "Unknown option: $1"
      fi
      exit "${EXIT_INVALID_INPUT:-1}"
      ;;
    *) PROJECT_NAME="$1"; shift ;;
  esac
done

# Resolve output format (CLI > env > config > TTY-aware default)
if declare -f resolve_format &>/dev/null; then
  FORMAT=$(resolve_format "$FORMAT")
else
  FORMAT="${FORMAT:-text}"
fi

# Redefine log functions to respect FORMAT
log_info()    { [[ "$QUIET" != true && "$FORMAT" != "json" ]] && echo "[INFO] $1" || true; }
log_warn()    { [[ "$FORMAT" != "json" ]] && echo "[WARN] $1" >&2 || true; }
log_success() { [[ "$FORMAT" != "json" ]] && echo "[SUCCESS] $1" || true; }
log_error()   { [[ "$FORMAT" != "json" ]] && echo "[ERROR] $1" >&2 || true; }

# Handle --update-claude-md as standalone operation
if [[ "$UPDATE_CLAUDE_MD" == true ]]; then
  if [[ ! -f "CLAUDE.md" ]]; then
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_FILE_NOT_FOUND" "CLAUDE.md not found in current directory" "${EXIT_NOT_FOUND:-4}" true "Create CLAUDE.md first or run from a directory with CLAUDE.md"
    else
      log_error "CLAUDE.md not found in current directory"
    fi
    exit "${EXIT_NOT_FOUND:-1}"
  fi

  injection_template="$CLAUDE_TODO_HOME/templates/CLAUDE-INJECTION.md"
  if [[ ! -f "$injection_template" ]]; then
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_FILE_NOT_FOUND" "Injection template not found: $injection_template" "${EXIT_NOT_FOUND:-4}" false "Reinstall claude-todo to restore templates"
    else
      log_error "Injection template not found: $injection_template"
    fi
    exit "${EXIT_NOT_FOUND:-1}"
  fi

  action_taken="updated"
  if grep -q "CLAUDE-TODO:START" CLAUDE.md 2>/dev/null; then
    # Replace existing block using sed
    # Create temp file with new content
    temp_file=$(mktemp)

    # Extract content before START tag (handles versioned tags like v0.12.1)
    sed -n '1,/<!-- CLAUDE-TODO:START/p' CLAUDE.md | head -n -1 > "$temp_file"

    # Append new injection template
    cat "$injection_template" >> "$temp_file"

    # Append content after END tag (if any)
    sed -n '/<!-- CLAUDE-TODO:END -->/,${/<!-- CLAUDE-TODO:END -->/d; p}' CLAUDE.md >> "$temp_file"

    # Replace original file
    mv "$temp_file" CLAUDE.md
    action_taken="updated"
  else
    # No existing block, append new one
    echo "" >> CLAUDE.md
    cat "$injection_template" >> CLAUDE.md
    action_taken="added"
  fi

  if [[ "$FORMAT" == "json" ]]; then
    jq -n \
      --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg action "$action_taken" \
      --arg version "$VERSION" \
      '{
        "$schema": "https://claude-todo.dev/schemas/output.schema.json",
        "_meta": {
          "command": "init",
          "subcommand": "update-claude-md",
          "timestamp": $timestamp,
          "format": "json",
          "version": $version
        },
        "success": true,
        "claudeMd": {
          "action": $action,
          "file": "CLAUDE.md"
        }
      }'
  else
    if [[ "$action_taken" == "updated" ]]; then
      log_success "CLAUDE.md injection updated"
    else
      log_success "CLAUDE.md injection added"
    fi
  fi
  exit 0
fi

# Determine project name
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME=$(basename "$PWD")
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# Check for existing files
if [[ -f ".claude/todo.json" ]] && [[ "$FORCE" != true ]]; then
  log_warn "Project already initialized at .claude/todo.json"
  log_warn "Use --force to reinitialize (will preserve existing tasks but reset config)"
  exit 1
fi

TIMESTAMP=$(generate_timestamp)
CHECKSUM=$(calculate_checksum)
TODO_DIR=".claude"

# Determine templates and schemas directories (installed or source)
if [[ -d "$CLAUDE_TODO_HOME/templates" ]]; then
  TEMPLATES_DIR="$CLAUDE_TODO_HOME/templates"
elif [[ -d "$SCRIPT_DIR/../templates" ]]; then
  TEMPLATES_DIR="$SCRIPT_DIR/../templates"
else
  if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
    output_error "$E_FILE_NOT_FOUND" "Templates directory not found at $CLAUDE_TODO_HOME/templates/ or $SCRIPT_DIR/../templates/" "${EXIT_FILE_ERROR:-4}" true "Run install.sh to set up CLAUDE-TODO globally, or run from source directory."
  else
    output_error "$E_FILE_NOT_FOUND" "Templates directory not found at $CLAUDE_TODO_HOME/templates/ or $SCRIPT_DIR/../templates/"
    log_error "Run install.sh to set up CLAUDE-TODO globally, or run from source directory."
  fi
  exit "${EXIT_FILE_ERROR:-1}"
fi

if [[ -d "$CLAUDE_TODO_HOME/schemas" ]]; then
  SCHEMAS_DIR="$CLAUDE_TODO_HOME/schemas"
elif [[ -d "$SCRIPT_DIR/../schemas" ]]; then
  SCHEMAS_DIR="$SCRIPT_DIR/../schemas"
else
  SCHEMAS_DIR=""
fi

log_info "Initializing CLAUDE-TODO for project: $PROJECT_NAME"

# Create .claude directory structure
mkdir -p "$TODO_DIR"
mkdir -p "$TODO_DIR/schemas"

# Copy backup directory structure from templates
if [[ -d "$TEMPLATES_DIR/backups" ]]; then
  # Create backups directory first
  mkdir -p "$TODO_DIR/backups"
  # Copy backup type directories and .gitkeep files
  for backup_type in snapshot safety incremental archive migration; do
    if [[ -d "$TEMPLATES_DIR/backups/$backup_type" ]]; then
      mkdir -p "$TODO_DIR/backups/$backup_type"
      # Copy .gitkeep if it exists
      if [[ -f "$TEMPLATES_DIR/backups/$backup_type/.gitkeep" ]]; then
        cp "$TEMPLATES_DIR/backups/$backup_type/.gitkeep" "$TODO_DIR/backups/$backup_type/"
      fi
    fi
  done
  log_info "Created $TODO_DIR/ directory with backup type subdirectories from templates"
else
  # Fallback: create directories manually if templates not available
  mkdir -p "$TODO_DIR/backups/snapshot"
  mkdir -p "$TODO_DIR/backups/safety"
  mkdir -p "$TODO_DIR/backups/incremental"
  mkdir -p "$TODO_DIR/backups/archive"
  mkdir -p "$TODO_DIR/backups/migration"
  # Create .gitkeep files to preserve directory structure in git
  touch "$TODO_DIR/backups/snapshot/.gitkeep"
  touch "$TODO_DIR/backups/safety/.gitkeep"
  touch "$TODO_DIR/backups/incremental/.gitkeep"
  touch "$TODO_DIR/backups/archive/.gitkeep"
  touch "$TODO_DIR/backups/migration/.gitkeep"
  log_info "Created $TODO_DIR/ directory with backup type subdirectories"
fi

# Copy schemas for local validation
if [[ -n "$SCHEMAS_DIR" ]]; then
  cp "$SCHEMAS_DIR/"*.json "$TODO_DIR/schemas/"
  log_info "Copied schemas to $TODO_DIR/schemas/"
else
  log_warn "Schemas not found (schema validation may fail)"
fi

# Create todo.json from template
log_info "Creating todo.json from template..."
if [[ -f "$TEMPLATES_DIR/todo.template.json" ]]; then
  cp "$TEMPLATES_DIR/todo.template.json" "$TODO_DIR/todo.json"

  # Substitute placeholders
  sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TODO_DIR/todo.json"
  sed -i "s/{{TIMESTAMP}}/$TIMESTAMP/g" "$TODO_DIR/todo.json"
  sed -i "s/{{CHECKSUM}}/$CHECKSUM/g" "$TODO_DIR/todo.json"
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/todo.schema.json"|"$schema": "./schemas/todo.schema.json"|' "$TODO_DIR/todo.json"

  log_info "Created $TODO_DIR/todo.json"
else
  log_error "Template not found: $TEMPLATES_DIR/todo.template.json"
  exit 1
fi

# Create todo-archive.json from template
log_info "Creating todo-archive.json from template..."
if [[ -f "$TEMPLATES_DIR/archive.template.json" ]]; then
  cp "$TEMPLATES_DIR/archive.template.json" "$TODO_DIR/todo-archive.json"

  # Substitute placeholders
  sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TODO_DIR/todo-archive.json"
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo-archive.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/archive.schema.json"|"$schema": "./schemas/archive.schema.json"|' "$TODO_DIR/todo-archive.json"

  log_info "Created $TODO_DIR/todo-archive.json"
else
  log_error "Template not found: $TEMPLATES_DIR/archive.template.json"
  exit 1
fi

# Create todo-config.json from template
log_info "Creating todo-config.json from template..."
if [[ -f "$TEMPLATES_DIR/config.template.json" ]]; then
  cp "$TEMPLATES_DIR/config.template.json" "$TODO_DIR/todo-config.json"

  # Substitute placeholders
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo-config.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/config.schema.json"|"$schema": "./schemas/config.schema.json"|' "$TODO_DIR/todo-config.json"

  log_info "Created $TODO_DIR/todo-config.json"
else
  log_error "Template not found: $TEMPLATES_DIR/config.template.json"
  exit 1
fi

# Create todo-log.json from template
log_info "Creating todo-log.json from template..."
if [[ -f "$TEMPLATES_DIR/log.template.json" ]]; then
  cp "$TEMPLATES_DIR/log.template.json" "$TODO_DIR/todo-log.json"

  # Substitute placeholders
  sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TODO_DIR/todo-log.json"
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo-log.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/log.schema.json"|"$schema": "./schemas/log.schema.json"|' "$TODO_DIR/todo-log.json"

  # Add initialization log entry
  # Generate random log ID
  LOG_ID="log_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 12)"

  # Update meta information and add entry using jq
  if command -v jq &> /dev/null; then
    jq --arg timestamp "$TIMESTAMP" \
       --arg log_id "$LOG_ID" \
       --arg project "$PROJECT_NAME" \
       '._meta.totalEntries = 1 |
        ._meta.firstEntry = $timestamp |
        ._meta.lastEntry = $timestamp |
        .entries = [{
          "id": $log_id,
          "timestamp": $timestamp,
          "sessionId": null,
          "action": "system_initialized",
          "actor": "system",
          "taskId": null,
          "before": null,
          "after": null,
          "details": ("CLAUDE-TODO system initialized for project: " + $project)
        }]' "$TODO_DIR/todo-log.json" > "$TODO_DIR/todo-log.json.tmp"

    mv "$TODO_DIR/todo-log.json.tmp" "$TODO_DIR/todo-log.json"
  else
    log_warn "jq not installed - log entry not added"
  fi

  log_info "Created $TODO_DIR/todo-log.json"
else
  log_error "Template not found: $TEMPLATES_DIR/log.template.json"
  exit 1
fi

# Recalculate checksum from actual tasks array to ensure validity
log_info "Recalculating checksum from actual tasks array..."
if command -v jq &> /dev/null && [[ -f "$TODO_DIR/todo.json" ]]; then
  ACTUAL_TASKS=$(jq -c '.tasks' "$TODO_DIR/todo.json")
  FINAL_CHECKSUM=$(echo "$ACTUAL_TASKS" | sha256sum | cut -c1-16)

  # Update checksum in the file
  jq --arg cs "$FINAL_CHECKSUM" '._meta.checksum = $cs' "$TODO_DIR/todo.json" > "$TODO_DIR/todo.json.tmp"
  mv "$TODO_DIR/todo.json.tmp" "$TODO_DIR/todo.json"
  log_info "Updated checksum to: $FINAL_CHECKSUM"
else
  log_warn "jq not installed - skipping checksum recalculation"
fi

# Validate created files
log_info "Validating created files..."
if command -v jq &> /dev/null; then
  # Validate JSON syntax
  for file in "$TODO_DIR/todo.json" "$TODO_DIR/todo-archive.json" "$TODO_DIR/todo-config.json" "$TODO_DIR/todo-log.json"; do
    if jq empty "$file" 2>/dev/null; then
      log_info "✓ Valid JSON: $(basename "$file")"
    else
      log_error "✗ Invalid JSON: $file"
      exit 1
    fi
  done
else
  log_warn "jq not installed - skipping JSON validation"
fi

# Update CLAUDE.md
if [[ "$NO_CLAUDE_MD" != true ]]; then
  if [[ -f "CLAUDE.md" ]]; then
    if grep -q "CLAUDE-TODO:START" CLAUDE.md 2>/dev/null; then
      log_warn "CLAUDE.md already has task integration (skipped)"
    else
      # Inject CLI-based task management instructions from template
      local injection_template="$CLAUDE_TODO_HOME/templates/CLAUDE-INJECTION.md"
      if [[ -f "$injection_template" ]]; then
        echo "" >> CLAUDE.md
        cat "$injection_template" >> CLAUDE.md
        log_info "Updated CLAUDE.md (from template)"
      else
        # Fallback minimal injection if template missing
        cat >> CLAUDE.md << 'CLAUDE_EOF'

<!-- CLAUDE-TODO:START -->
## Task Management (claude-todo)

Use `ct` (alias for `claude-todo`) for all task operations. Full docs: `~/.claude-todo/docs/TODO_Task_Management.md`

### Essential Commands
```bash
ct list                    # View tasks
ct add "Task"              # Create task
ct done <id>               # Complete task
ct focus set <id>          # Set active task
ct session start|end       # Session lifecycle
ct exists <id>             # Verify task exists
```

### Anti-Hallucination
- **CLI only** - Never edit `.claude/*.json` directly
- **Verify state** - Use `ct list` before assuming
<!-- CLAUDE-TODO:END -->
CLAUDE_EOF
        log_info "Updated CLAUDE.md (fallback)"
      fi
    fi
  else
    log_warn "No CLAUDE.md found (skipped)"
  fi
fi

# Build list of created files
CREATED_FILES=(
  "todo.json"
  "todo-archive.json"
  "todo-config.json"
  "todo-log.json"
)

if [[ "$FORMAT" == "json" ]]; then
  # JSON output
  jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg projectName "$PROJECT_NAME" \
    --arg directory "$TODO_DIR" \
    --arg version "$VERSION" \
    --argjson files "$(printf '%s\n' "${CREATED_FILES[@]}" | jq -R . | jq -s .)" \
    '{
      "$schema": "https://claude-todo.dev/schemas/output.schema.json",
      "_meta": {
        "command": "init",
        "timestamp": $timestamp,
        "format": "json",
        "version": $version
      },
      "success": true,
      "initialized": {
        "projectName": $projectName,
        "directory": $directory,
        "version": $version,
        "files": $files,
        "schemas": true,
        "backups": true
      }
    }'
else
  # Text output
  echo ""
  log_success "CLAUDE-TODO initialized successfully!"
  echo ""
  echo "Files created in .claude/:"
  echo "  - .claude/todo.json         (active tasks)"
  echo "  - .claude/todo-archive.json (completed tasks)"
  echo "  - .claude/todo-config.json  (settings)"
  echo "  - .claude/todo-log.json     (change history)"
  echo "  - .claude/schemas/          (JSON schemas for validation)"
  echo "  - .claude/backups/          (automatic backups)"
  echo "    ├── snapshot/             (point-in-time snapshots)"
  echo "    ├── safety/               (pre-operation backups)"
  echo "    ├── incremental/          (file version history)"
  echo "    ├── archive/              (long-term archives)"
  echo "    └── migration/            (schema migration backups)"
  echo ""
  echo "Add to .gitignore (recommended):"
  echo "  .claude/*.json"
  echo "  .claude/backups/"
  echo ""
  echo "Next steps:"
  echo "  1. claude-todo add \"Your first task\""
  echo "  2. claude-todo focus set <task-id>"
  echo "  3. claude-todo session start"
fi
