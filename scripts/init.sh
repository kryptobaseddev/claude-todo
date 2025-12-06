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

# Source library functions
if [[ -f "$CLAUDE_TODO_HOME/lib/logging.sh" ]]; then
  source "$CLAUDE_TODO_HOME/lib/logging.sh"
fi

# Always define console logging functions (lib/logging.sh provides task logging, not console output)
log_info()    { echo "[INFO] $1"; }
log_warn()    { echo "[WARN] $1" >&2; }
log_success() { echo "[SUCCESS] $1"; }
# Only define log_error if not already defined by library
type -t log_error &>/dev/null || log_error() { echo "[ERROR] $1" >&2; }

# Optional: source other libraries if needed
[[ -f "$CLAUDE_TODO_HOME/lib/file-ops.sh" ]] && source "$CLAUDE_TODO_HOME/lib/file-ops.sh" || true
[[ -f "$CLAUDE_TODO_HOME/lib/validation.sh" ]] && source "$CLAUDE_TODO_HOME/lib/validation.sh" || true

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
  .claude/todo.json         Active tasks
  .claude/todo-archive.json Completed tasks
  .claude/todo-config.json  Configuration
  .claude/todo-log.json     Change history
  .claude/schemas/          JSON Schema files
  .claude/.backups/         Backup directory
EOF
  exit 0
}

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

# Create .claude directory structure
mkdir -p "$TODO_DIR"
mkdir -p "$TODO_DIR/.backups"
mkdir -p "$TODO_DIR/schemas"
log_info "Created $TODO_DIR/ directory"

# Copy schemas for local validation
if [[ -d "$CLAUDE_TODO_HOME/schemas" ]]; then
  cp "$CLAUDE_TODO_HOME/schemas/"*.json "$TODO_DIR/schemas/"
  log_info "Copied schemas to $TODO_DIR/schemas/"
else
  log_warn "Schemas not found at $CLAUDE_TODO_HOME/schemas/ (schema validation may fail)"
fi

# Verify templates exist
if [[ ! -d "$CLAUDE_TODO_HOME/templates" ]]; then
  log_error "Templates directory not found at $CLAUDE_TODO_HOME/templates/"
  log_error "Run install.sh to set up CLAUDE-TODO globally first."
  exit 1
fi

# Create todo.json from template
log_info "Creating todo.json from template..."
if [[ -f "$CLAUDE_TODO_HOME/templates/todo.template.json" ]]; then
  cp "$CLAUDE_TODO_HOME/templates/todo.template.json" "$TODO_DIR/todo.json"

  # Substitute placeholders
  sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TODO_DIR/todo.json"
  sed -i "s/{{TIMESTAMP}}/$TIMESTAMP/g" "$TODO_DIR/todo.json"
  sed -i "s/{{CHECKSUM}}/$CHECKSUM/g" "$TODO_DIR/todo.json"
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/todo.schema.json"|"$schema": "./schemas/todo.schema.json"|' "$TODO_DIR/todo.json"

  log_info "Created $TODO_DIR/todo.json"
else
  log_error "Template not found: $CLAUDE_TODO_HOME/templates/todo.template.json"
  exit 1
fi

# Create todo-archive.json from template
log_info "Creating todo-archive.json from template..."
if [[ -f "$CLAUDE_TODO_HOME/templates/archive.template.json" ]]; then
  cp "$CLAUDE_TODO_HOME/templates/archive.template.json" "$TODO_DIR/todo-archive.json"

  # Substitute placeholders
  sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TODO_DIR/todo-archive.json"
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo-archive.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/archive.schema.json"|"$schema": "./schemas/archive.schema.json"|' "$TODO_DIR/todo-archive.json"

  log_info "Created $TODO_DIR/todo-archive.json"
else
  log_error "Template not found: $CLAUDE_TODO_HOME/templates/archive.template.json"
  exit 1
fi

# Create todo-config.json from template
log_info "Creating todo-config.json from template..."
if [[ -f "$CLAUDE_TODO_HOME/templates/config.template.json" ]]; then
  cp "$CLAUDE_TODO_HOME/templates/config.template.json" "$TODO_DIR/todo-config.json"

  # Substitute placeholders
  sed -i "s/{{VERSION}}/$VERSION/g" "$TODO_DIR/todo-config.json"

  # Fix schema path from relative to local
  sed -i 's|"\$schema": "../schemas/config.schema.json"|"$schema": "./schemas/config.schema.json"|' "$TODO_DIR/todo-config.json"

  log_info "Created $TODO_DIR/todo-config.json"
else
  log_error "Template not found: $CLAUDE_TODO_HOME/templates/config.template.json"
  exit 1
fi

# Create todo-log.json from template
log_info "Creating todo-log.json from template..."
if [[ -f "$CLAUDE_TODO_HOME/templates/log.template.json" ]]; then
  cp "$CLAUDE_TODO_HOME/templates/log.template.json" "$TODO_DIR/todo-log.json"

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
  log_error "Template not found: $CLAUDE_TODO_HOME/templates/log.template.json"
  exit 1
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
log_success "CLAUDE-TODO initialized successfully!"
echo ""
echo "Files created in .claude/:"
echo "  - .claude/todo.json         (active tasks)"
echo "  - .claude/todo-archive.json (completed tasks)"
echo "  - .claude/todo-config.json  (settings)"
echo "  - .claude/todo-log.json     (change history)"
echo "  - .claude/schemas/          (JSON schemas for validation)"
echo "  - .claude/.backups/         (automatic backups)"
echo ""
echo "Add to .gitignore (recommended):"
echo "  .claude/*.json"
echo "  .claude/.backups/"
echo ""
echo "Next steps:"
echo "  1. Add your first task to .claude/todo.json"
echo "  2. Set focus.currentTask when starting work"
echo "  3. Always verify checksum before modifying"
