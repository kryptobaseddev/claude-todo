# Suggested Commands

## Development Commands

### Installation and Setup
```bash
# Global installation
./install.sh

# Upgrade existing installation
./install.sh --upgrade

# Initialize project
~/.claude-todo/scripts/init.sh
```

### Task Management
```bash
# Add new task
~/.claude-todo/scripts/add-task.sh "Task description" --status pending

# Complete task
~/.claude-todo/scripts/complete-task.sh <task-id>

# List tasks
~/.claude-todo/scripts/list-tasks.sh
~/.claude-todo/scripts/list-tasks.sh --status pending
~/.claude-todo/scripts/list-tasks.sh --format json
```

### Archival and Maintenance
```bash
# Archive completed tasks (automatic based on policy)
~/.claude-todo/scripts/archive.sh

# Archive with custom retention period
~/.claude-todo/scripts/archive.sh --days 30

# Force immediate archive
~/.claude-todo/scripts/archive.sh --force
```

### Validation and Health Checks
```bash
# Validate all JSON files
~/.claude-todo/scripts/validate.sh

# Validate with automatic fixes
~/.claude-todo/scripts/validate.sh --fix

# Run health check
~/.claude-todo/scripts/health-check.sh
```

### Statistics and Reporting
```bash
# Show statistics
~/.claude-todo/scripts/stats.sh

# Statistics for specific period
~/.claude-todo/scripts/stats.sh --period 30

# Export statistics as JSON
~/.claude-todo/scripts/stats.sh --format json
```

### Backup and Restore
```bash
# Manual backup
~/.claude-todo/scripts/backup.sh

# Backup to specific directory
~/.claude-todo/scripts/backup.sh --destination /path/to/backup

# Restore from backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1

# List available backups
ls -lh .claude/.backups/
```

## Testing Commands

### Run Test Suite
```bash
# All tests
./tests/run-all-tests.sh

# Specific test category
./tests/test-validation.sh
./tests/test-archive.sh
./tests/test-add-task.sh
```

### Manual Testing
```bash
# Test schema validation
jq -e . schemas/todo.schema.json > /dev/null && echo "Valid JSON"

# Test jq processing
jq '.todos[] | select(.status == "completed")' .claude/todo.json

# Test atomic write
./lib/file-ops.sh atomic_write .claude/todo.json '{"todos":[]}'
```

## Utility Commands

### JSON Operations
```bash
# Pretty-print JSON
jq '.' .claude/todo.json

# Filter tasks by status
jq '.todos[] | select(.status == "pending")' .claude/todo.json

# Count tasks
jq '.todos | length' .claude/todo.json

# Extract specific field
jq -r '.todos[].content' .claude/todo.json
```

### File Operations
```bash
# Check file permissions
ls -l .claude/todo*.json

# Check file sizes
du -h .claude/*.json

# Find all todo files
find . -name "todo*.json" -type f
```

### Schema Validation (Manual)
```bash
# Using ajv (if installed)
ajv validate -s schemas/todo.schema.json -d .claude/todo.json

# Using jsonschema (Python, if installed)
jsonschema -i .claude/todo.json schemas/todo.schema.json

# Using jq (always available)
jq -e --arg schema "$(cat schemas/todo.schema.json)" 'validate($schema)' .claude/todo.json
```

### Log Analysis
```bash
# Recent operations
jq '.entries[-10:]' .claude/todo-log.json

# Filter by operation type
jq '.entries[] | select(.operation == "create")' .claude/todo-log.json

# Count operations
jq '.entries | group_by(.operation) | map({operation: .[0].operation, count: length})' .claude/todo-log.json
```

## Git Commands

### Version Control
```bash
# Initialize git (if not already)
git init

# Ensure .gitignore is correct
cat .gitignore  # Should include .claude/todo*.json

# Add system files
git add schemas/ templates/ scripts/ lib/ docs/ tests/
git commit -m "Add claude-todo system files"

# Track changes to templates/schemas
git add schemas/todo.schema.json
git commit -m "Update todo schema to v1.1.0"
```

## Environment Setup

### Configuration
```bash
# Set environment variables
export CLAUDE_TODO_ARCHIVE_DAYS=14
export CLAUDE_TODO_STRICT_MODE=true
export CLAUDE_TODO_LOG_LEVEL=debug

# Add to shell profile for persistence
echo 'export CLAUDE_TODO_ARCHIVE_DAYS=14' >> ~/.bashrc
```

### PATH Setup (Optional)
```bash
# Add scripts to PATH
echo 'export PATH="$HOME/.claude-todo/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Now can run directly
add-task.sh "New task"
list-tasks.sh
```

## Debugging Commands

### Verbose Mode
```bash
# Enable debug output
CLAUDE_TODO_LOG_LEVEL=debug ~/.claude-todo/scripts/add-task.sh "Test task"

# Trace script execution
bash -x ~/.claude-todo/scripts/archive.sh
```

### Validation Debugging
```bash
# Check schema structure
jq '.' schemas/todo.schema.json

# Validate specific task object
echo '{"id":"test","status":"pending","content":"Test","activeForm":"Testing"}' | \
  jq --slurpfile schema schemas/todo.schema.json 'validate($schema[0])'

# Check for duplicate IDs
jq '[.todos[].id] | group_by(.) | map(select(length > 1))' .claude/todo.json
```

## Performance Profiling

### Timing Operations
```bash
# Measure command execution time
time ~/.claude-todo/scripts/archive.sh

# Profile with detailed timing
TIMEFORMAT='Real: %R, User: %U, System: %S'
time ~/.claude-todo/scripts/stats.sh
```

### File Size Monitoring
```bash
# Check all file sizes
du -h .claude/*.json

# Monitor log growth
watch -n 60 'du -h .claude/todo-log.json'
```

## Quick Reference Aliases

### Recommended Shell Aliases
```bash
# Add to ~/.bashrc or ~/.zshrc
alias ct-add='~/.claude-todo/scripts/add-task.sh'
alias ct-complete='~/.claude-todo/scripts/complete-task.sh'
alias ct-list='~/.claude-todo/scripts/list-tasks.sh'
alias ct-archive='~/.claude-todo/scripts/archive.sh'
alias ct-stats='~/.claude-todo/scripts/stats.sh'
alias ct-validate='~/.claude-todo/scripts/validate.sh'
alias ct-backup='~/.claude-todo/scripts/backup.sh'
```
