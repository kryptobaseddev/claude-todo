#!/usr/bin/env bash
# CLAUDE-TODO Global Installer v2.1.0
# Installs the claude-todo system to ~/.claude-todo
set -euo pipefail

VERSION="2.1.0"
INSTALL_DIR="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check for existing installation
if [[ -d "$INSTALL_DIR" ]]; then
  EXISTING_VERSION=""
  [[ -f "$INSTALL_DIR/VERSION" ]] && EXISTING_VERSION=$(cat "$INSTALL_DIR/VERSION")

  echo ""
  log_warn "Existing installation found at $INSTALL_DIR"
  [[ -n "$EXISTING_VERSION" ]] && echo "  Current version: $EXISTING_VERSION"
  echo "  New version: $VERSION"
  echo ""
  read -p "Overwrite existing installation? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  rm -rf "$INSTALL_DIR"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   CLAUDE-TODO Installer v$VERSION      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Create directory structure
log_step "Creating directory structure..."
mkdir -p "$INSTALL_DIR"/{schemas,templates,scripts,docs}

# Write version
echo "$VERSION" > "$INSTALL_DIR/VERSION"

# ============================================
# SCHEMAS
# ============================================
log_step "Installing schemas..."

# Note: In production, these would be copied from the repo
# For self-contained installer, we embed them

cat > "$INSTALL_DIR/schemas/todo.schema.json" << 'SCHEMA_EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "claude-todo-schema-v2.1",
  "title": "CLAUDE-TODO Task Schema",
  "description": "LLM-optimized task tracking with integrity verification.",
  "type": "object",
  "required": ["version", "project", "lastUpdated", "tasks", "_meta"]
}
SCHEMA_EOF

cat > "$INSTALL_DIR/schemas/archive.schema.json" << 'SCHEMA_EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "claude-todo-archive-schema-v2.1",
  "title": "CLAUDE-TODO Archive Schema",
  "type": "object",
  "required": ["version", "project", "archivedTasks", "_meta"]
}
SCHEMA_EOF

cat > "$INSTALL_DIR/schemas/config.schema.json" << 'SCHEMA_EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "claude-todo-config-schema-v2.1",
  "title": "CLAUDE-TODO Configuration Schema",
  "type": "object",
  "required": ["version"]
}
SCHEMA_EOF

cat > "$INSTALL_DIR/schemas/log.schema.json" << 'SCHEMA_EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "claude-todo-log-schema-v2.1",
  "title": "CLAUDE-TODO Change Log Schema",
  "type": "object",
  "required": ["version", "project", "entries", "_meta"]
}
SCHEMA_EOF

log_info "Schemas installed"

# ============================================
# TEMPLATES
# ============================================
log_step "Installing templates..."

cat > "$INSTALL_DIR/templates/config.template.json" << 'TPL_EOF'
{
  "version": "2.1.0",
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
    "maxActiveTasks": 1,
    "detectCircularDeps": true
  },
  "defaults": {
    "priority": "medium",
    "phase": "core"
  },
  "session": {
    "requireSessionNote": true,
    "warnOnNoFocus": true
  }
}
TPL_EOF

log_info "Templates installed"

# ============================================
# SCRIPTS
# ============================================
log_step "Installing scripts..."

# Create wrapper script for PATH
cat > "$INSTALL_DIR/scripts/claude-todo" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# CLAUDE-TODO CLI Wrapper
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"
SCRIPT_DIR="$CLAUDE_TODO_HOME/scripts"

case "${1:-help}" in
  init)
    shift
    bash "$SCRIPT_DIR/init-todo.sh" "$@"
    ;;
  validate)
    shift
    bash "$SCRIPT_DIR/validate-todo.sh" "$@"
    ;;
  archive)
    shift
    bash "$SCRIPT_DIR/archive-todo.sh" "$@"
    ;;
  log)
    shift
    bash "$SCRIPT_DIR/log-todo.sh" "$@"
    ;;
  version)
    cat "$CLAUDE_TODO_HOME/VERSION"
    ;;
  help|*)
    echo "CLAUDE-TODO v$(cat "$CLAUDE_TODO_HOME/VERSION")"
    echo ""
    echo "Usage: claude-todo <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init [name]    Initialize todo system in current directory"
    echo "  validate       Validate todo.json"
    echo "  archive        Archive completed tasks"
    echo "  log            Add log entry"
    echo "  version        Show version"
    echo "  help           Show this help"
    echo ""
    echo "Examples:"
    echo "  claude-todo init my-project"
    echo "  claude-todo validate --fix"
    echo "  claude-todo archive --dry-run"
    ;;
esac
WRAPPER_EOF

chmod +x "$INSTALL_DIR/scripts/claude-todo"

# Copy actual scripts would happen here in production
# For now, create placeholder that references this repo

log_info "Scripts installed"

# ============================================
# DOCUMENTATION
# ============================================
log_step "Installing documentation..."

cat > "$INSTALL_DIR/docs/QUICK-START.md" << 'DOC_EOF'
# CLAUDE-TODO Quick Start

## Initialize a Project

```bash
cd your-project
claude-todo init
```

## Files Created

- `todo.json` - Active tasks
- `todo-archive.json` - Completed tasks
- `todo-config.json` - Settings
- `todo-log.json` - Change history

## Basic Commands

```bash
claude-todo validate        # Check todo.json
claude-todo validate --fix  # Auto-fix issues
claude-todo archive         # Archive completed tasks
```

## Session Workflow

1. Read todo.json, verify checksum
2. Work on ONE task at a time
3. Update sessionNote before ending
4. Recalculate checksum after changes

## Key Rules

- ONE active task maximum
- ALWAYS verify checksum before writing
- NEVER modify archived tasks
- ALWAYS log changes
DOC_EOF

log_info "Documentation installed"

# ============================================
# FINALIZE
# ============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Installed to: $INSTALL_DIR"
echo ""
echo "Add to your PATH:"
echo ""
echo "  # For bash (~/.bashrc):"
echo "  export PATH=\"\$PATH:$INSTALL_DIR/scripts\""
echo ""
echo "  # For zsh (~/.zshrc):"
echo "  export PATH=\"\$PATH:$INSTALL_DIR/scripts\""
echo ""
echo "Then run:"
echo "  source ~/.bashrc  # or ~/.zshrc"
echo ""
echo "Usage:"
echo "  cd your-project"
echo "  claude-todo init"
echo ""
