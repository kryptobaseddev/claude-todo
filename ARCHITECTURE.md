# CLAUDE-TODO System Architecture

## Overview
A robust, installable task management system for Claude Code with auto-archiving, configuration management, change history logging, and anti-hallucination validation mechanisms.

## Design Principles
- **Single Source of Truth**: todo.json as primary task state
- **Immutable History**: Append-only logging for auditability
- **Fail-Safe Operations**: Atomic file operations with validation
- **Schema-First**: JSON Schema validation prevents corruption
- **Idempotent Scripts**: Safe to run multiple times
- **Zero-Config Defaults**: Sensible defaults, optional customization

---

## Directory Structure

```
claude-todo/
├── README.md                      # User documentation
├── ARCHITECTURE.md                # This file
├── LICENSE                        # MIT License
├── install.sh                     # Global installation script
├── .gitignore                     # Ignore user data files
│
├── schemas/                       # JSON Schema definitions
│   ├── todo.schema.json          # Main task list schema
│   ├── todo-archive.schema.json  # Archive schema
│   ├── todo-config.schema.json   # Configuration schema
│   └── todo-log.schema.json      # Change log schema
│
├── templates/                     # Starter templates
│   ├── todo.template.json        # Empty task list with examples
│   ├── todo-config.template.json # Default configuration
│   └── todo-archive.template.json # Empty archive
│
├── scripts/                       # Operational scripts
│   ├── init.sh                   # Initialize project with todo system
│   ├── validate.sh               # Validate all JSON files
│   ├── archive.sh                # Archive completed tasks
│   ├── add-task.sh              # Add new task with validation
│   ├── complete-task.sh         # Mark task complete and log
│   ├── list-tasks.sh            # Display current tasks
│   ├── stats.sh                 # Statistics and reporting
│   ├── backup.sh                # Backup all todo files
│   └── restore.sh               # Restore from backup
│
├── lib/                          # Shared library functions
│   ├── validation.sh            # Schema validation functions
│   ├── logging.sh               # Change log functions
│   └── file-ops.sh              # Atomic file operations
│
├── docs/                         # Documentation
│   ├── installation.md          # Installation guide
│   ├── usage.md                 # Usage examples
│   ├── configuration.md         # Configuration reference
│   ├── schema-reference.md      # Schema documentation
│   └── troubleshooting.md       # Common issues
│
└── tests/                        # Test suite
    ├── test-validation.sh       # Schema validation tests
    ├── test-archive.sh          # Archive operation tests
    ├── test-add-task.sh         # Task creation tests
    └── fixtures/                # Test data
        ├── valid-todo.json
        └── invalid-todo.json
```

---

## Core Data Files

### Per-Project Files (NOT in git repo)

```
your-project/
├── .claude/
│   ├── todo.json              # Current active tasks
│   ├── todo-archive.json      # Completed/cancelled tasks
│   ├── todo-config.json       # Project-specific config
│   ├── todo-log.json          # Change history log
│   └── .backups/              # Automatic backups
│       ├── todo.json.1
│       ├── todo.json.2
│       └── ...
```

### Global Installation (~/.claude-todo/)

```
~/.claude-todo/
├── schemas/                   # Schema files
├── templates/                 # Template files
├── scripts/                   # Executable scripts
└── lib/                       # Library functions
```

---

## File Interaction Matrix

| File | Read By | Written By | Validates Against |
|------|---------|------------|-------------------|
| `todo.json` | list, stats, complete, archive | add-task, complete-task, archive | todo.schema.json |
| `todo-archive.json` | stats, list (--all) | archive | todo-archive.schema.json |
| `todo-config.json` | ALL scripts | init, user edit | todo-config.schema.json |
| `todo-log.json` | stats, troubleshooting | add-task, complete-task, archive | todo-log.schema.json |

---

## Data Flow Diagrams

### Task Lifecycle Flow

```
┌─────────────────┐
│  User Request   │
│  "Add Task"     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│   add-task.sh           │
│  1. Validate input      │
│  2. Load config         │
│  3. Load todo.json      │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│   validation.sh         │
│  - Schema validation    │
│  - Anti-hallucination   │
│    checks               │
└────────┬────────────────┘
         │
         ├─── INVALID ──► Error + Exit
         │
         ▼ VALID
┌─────────────────────────┐
│   file-ops.sh           │
│  - Atomic write         │
│  - Backup old version   │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│   logging.sh            │
│  - Append to log        │
│  - Record timestamp     │
│  - Record operation     │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│   Success Response      │
│  "Task added: ID-123"   │
└─────────────────────────┘
```

### Archive Flow

```
┌──────────────────┐
│  Auto-trigger    │◄────── Cron / Manual / On-complete
│  OR Manual call  │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────┐
│   archive.sh                │
│  1. Load config             │
│  2. Check archive policy    │
│  3. Filter completed tasks  │
└────────┬────────────────────┘
         │
         ├─── No tasks to archive ──► Exit
         │
         ▼ Has completed tasks
┌─────────────────────────────┐
│  Apply Retention Policy     │
│  - archive_after_days: 7    │
│  - max_archive_size: 1000   │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Move tasks:               │
│   todo.json → archive.json  │
│   (Atomic operation)        │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Log operation             │
│   Record archived task IDs  │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Success                   │
│   "Archived N tasks"        │
└─────────────────────────────┘
```

### Validation Flow

```
┌─────────────────┐
│  JSON Input     │
└────────┬────────┘
         │
         ▼
┌──────────────────────────────┐
│   Schema Validation          │
│   (ajv or jsonschema)        │
└────────┬─────────────────────┘
         │
         ├─── Schema Invalid ──► Error + Details
         │
         ▼ Schema Valid
┌──────────────────────────────┐
│   Anti-Hallucination Checks  │
│   1. ID uniqueness           │
│   2. Status enum validity    │
│   3. Timestamp sanity        │
│   4. Content/activeForm pair │
│   5. No duplicate content    │
└────────┬─────────────────────┘
         │
         ├─── Semantic Invalid ──► Error + Details
         │
         ▼ All Valid
┌──────────────────────────────┐
│   Configuration Validation   │
│   Apply config constraints   │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│   Success: File is Valid     │
└──────────────────────────────┘
```

---

## Installation Sequence

### Global Installation

```bash
# 1. User runs install script
./install.sh

# 2. Install script performs:
#    a. Check for ~/.claude-todo/ directory
#    b. Create directory if missing
#    c. Copy schemas/ → ~/.claude-todo/schemas/
#    d. Copy templates/ → ~/.claude-todo/templates/
#    e. Copy scripts/ → ~/.claude-todo/scripts/
#    f. Copy lib/ → ~/.claude-todo/lib/
#    g. Make all scripts executable
#    h. Add ~/.claude-todo/scripts to PATH (optional)
#    i. Validate installation with test suite

# 3. Success message with usage instructions
```

### Per-Project Initialization

```bash
# 1. User navigates to project root
cd /path/to/project

# 2. Run init script
~/.claude-todo/scripts/init.sh

# 3. Init script performs:
#    a. Check for .claude/ directory
#    b. Create .claude/ if missing
#    c. Copy templates → .claude/
#    d. Rename .template.json → .json
#    e. Initialize empty log: todo-log.json
#    f. Validate all files against schemas
#    g. Create .backups/ directory

# 4. Add to .gitignore (if not present):
echo ".claude/todo*.json" >> .gitignore
echo ".claude/.backups/" >> .gitignore

# 5. Success message
```

### Update/Upgrade Mechanism

```bash
# 1. User runs install script again
./install.sh --upgrade

# 2. Install script checks version
#    - Compare installed version with repo version
#    - Backup existing installation
#    - Update changed files only
#    - Preserve user customizations

# 3. Run migration scripts if needed
#    - Schema changes
#    - Config format updates
#    - Data migrations

# 4. Validate updated installation
```

---

## Operation Workflows

### 1. Create Task

```bash
# Command
~/.claude-todo/scripts/add-task.sh "Implement authentication" \
  --status pending \
  --activeForm "Implementing authentication"

# Workflow
1. Load todo-config.json for settings
2. Parse command arguments
3. Validate inputs (anti-hallucination)
4. Load current todo.json
5. Generate unique task ID
6. Create task object
7. Validate full todo.json with new task
8. Atomic write to todo.json (with backup)
9. Log operation to todo-log.json
10. Display success with task ID

# Anti-Hallucination Checks
- content and activeForm must both be present
- status must be: pending | in_progress | completed
- No duplicate task content
- ID must be unique
- Timestamps must be reasonable (not future)
```

### 2. Complete Task

```bash
# Command
~/.claude-todo/scripts/complete-task.sh <task-id>

# Workflow
1. Load todo-config.json
2. Load todo.json
3. Find task by ID
4. Validate task exists
5. Update status to "completed"
6. Add completion timestamp
7. Validate updated todo.json
8. Atomic write (with backup)
9. Log operation
10. Check auto-archive policy
11. Trigger archive if policy met
12. Display success

# Anti-Hallucination Checks
- Task ID must exist
- Task not already completed
- Status transition valid (pending/in_progress → completed)
```

### 3. Archive Completed Tasks

```bash
# Command
~/.claude-todo/scripts/archive.sh [--force] [--days N]

# Workflow
1. Load todo-config.json
2. Read archive policy (archive_after_days)
3. Load todo.json
4. Filter completed tasks older than threshold
5. Validate filtered tasks
6. Load todo-archive.json
7. Append filtered tasks to archive
8. Remove archived tasks from todo.json
9. Validate both files
10. Atomic write both files (synchronized)
11. Log operation with archived IDs
12. Display statistics

# Configuration Options
- archive_after_days: How long to keep completed tasks (default: 7)
- max_archive_size: Max archived tasks (default: 1000, 0=unlimited)
- auto_archive: true | false (default: false)

# Anti-Hallucination Checks
- No task loss (verify count before/after)
- Archive schema validation
- No duplicate IDs across files
- Maintain task order
```

### 4. Validate All Files

```bash
# Command
~/.claude-todo/scripts/validate.sh [--fix]

# Workflow
1. Find all todo-related JSON files
2. For each file:
   a. Determine schema type
   b. Validate against schema
   c. Run anti-hallucination checks
   d. Report errors with line numbers
3. If --fix flag:
   a. Attempt automatic repairs
   b. Backup before repairs
   c. Re-validate after repairs
4. Display validation report

# Validation Categories
✅ Schema Valid: Passes JSON Schema
✅ Semantic Valid: Passes anti-hallucination checks
⚠️  Warning: Non-critical issues
❌ Error: Critical issues requiring fix

# Exit Codes
0 = All valid
1 = Schema errors
2 = Semantic errors
3 = Both errors
```

### 5. List Tasks

```bash
# Command
~/.claude-todo/scripts/list-tasks.sh [--status STATUS] [--format FORMAT]

# Workflow
1. Load todo-config.json
2. Load todo.json
3. Filter by status (if specified)
4. Sort by configured order
5. Format output (text | json | markdown)
6. Display with colors/formatting

# Output Formats
- text: Human-readable terminal output
- json: Machine-readable JSON
- markdown: For documentation
- table: ASCII table format

# Filter Options
--status pending | in_progress | completed
--since DATE (created after DATE)
--limit N (first N tasks)
```

### 6. Statistics and Reporting

```bash
# Command
~/.claude-todo/scripts/stats.sh [--period DAYS]

# Workflow
1. Load all todo files (current + archive + log)
2. Compute statistics:
   - Total tasks (all time)
   - Active tasks by status
   - Completion rate
   - Average time to completion
   - Tasks per day/week/month
   - Busiest periods
3. Generate report with charts (ASCII art)
4. Display summary

# Statistics Categories
📊 Current State
   - Pending: N
   - In Progress: M
   - Completed: K

📈 Trends (last 30 days)
   - Tasks created: X
   - Tasks completed: Y
   - Completion rate: Z%
   - Avg time to complete: T hours

🏆 All-Time Stats
   - Total tasks: A
   - Total completed: B
   - Success rate: C%
```

### 7. Backup and Restore

```bash
# Backup Command
~/.claude-todo/scripts/backup.sh [--destination DIR]

# Workflow
1. Create timestamped backup directory
2. Copy all .claude/todo*.json files
3. Validate backup integrity
4. Display backup location

# Restore Command
~/.claude-todo/scripts/restore.sh <backup-dir>

# Workflow
1. Validate backup directory
2. Check backup file integrity
3. Backup current files (before restore)
4. Copy backup files to .claude/
5. Validate restored files
6. Display success/rollback on error

# Automatic Backups
- Before every write operation
- Keep last N backups (configurable)
- Rotate old backups automatically
```

---

## Configuration System

### Default Configuration (todo-config.json)

```json
{
  "$schema": "../schemas/todo-config.schema.json",
  "version": "1.0.0",
  "archive": {
    "enabled": true,
    "archive_after_days": 7,
    "max_archive_size": 1000,
    "auto_archive_on_complete": false
  },
  "validation": {
    "strict_mode": true,
    "allow_duplicates": false,
    "require_active_form": true
  },
  "logging": {
    "enabled": true,
    "log_level": "info",
    "max_log_entries": 10000
  },
  "backups": {
    "enabled": true,
    "max_backups": 10,
    "backup_on_write": true
  },
  "display": {
    "date_format": "iso",
    "timezone": "local",
    "colors_enabled": true
  }
}
```

### Configuration Override Hierarchy

1. **Defaults** (in template)
2. **Global** (~/.claude-todo/config.json) - optional
3. **Project** (.claude/todo-config.json)
4. **Environment** (CLAUDE_TODO_* env vars)
5. **Command-line** (--flags)

---

## Anti-Hallucination Mechanisms

### 1. Schema Validation
- JSON Schema enforces structure
- Type checking (string, number, boolean)
- Required fields validation
- Enum constraints for status values

### 2. Semantic Validation
```bash
# ID Uniqueness Check
- Extract all task IDs
- Check for duplicates within file
- Check for duplicates across todo + archive

# Status Enum Validation
- Must be: pending | in_progress | completed
- No typos, no custom statuses

# Timestamp Sanity Check
- created_at must be valid ISO 8601
- created_at must not be in future
- completed_at must be after created_at

# Content Pairing Check
- Every task must have "content" AND "activeForm"
- Neither can be empty string
- Must be different strings

# Duplicate Content Detection
- Check for identical task descriptions
- Warn on similar content (Levenshtein distance)
```

### 3. Referential Integrity
```bash
# Cross-File Validation
- Task IDs unique across todo + archive
- No orphaned references in log
- Archive only contains completed tasks

# Log Consistency
- Every logged operation references valid task ID
- Operation types match allowed values
- Timestamps chronological
```

### 4. Validation Modes

**Strict Mode** (default):
- All checks enabled
- Errors block operations
- No automatic fixes

**Lenient Mode**:
- Warnings instead of errors for non-critical issues
- Allow automatic fixes
- Useful for migrations

---

## Change Log Structure

### Log Entry Format (todo-log.json)

```json
{
  "$schema": "../schemas/todo-log.schema.json",
  "entries": [
    {
      "id": "log-1733395200-abc123",
      "timestamp": "2025-12-05T10:00:00Z",
      "operation": "create",
      "task_id": "task-1733395200-xyz789",
      "user": "system",
      "details": {
        "content": "Implement authentication",
        "status": "pending"
      },
      "before": null,
      "after": {
        "status": "pending",
        "content": "Implement authentication"
      }
    },
    {
      "id": "log-1733395300-def456",
      "timestamp": "2025-12-05T10:01:40Z",
      "operation": "update",
      "task_id": "task-1733395200-xyz789",
      "user": "system",
      "details": {
        "field": "status",
        "old_value": "pending",
        "new_value": "in_progress"
      },
      "before": {
        "status": "pending"
      },
      "after": {
        "status": "in_progress"
      }
    },
    {
      "id": "log-1733395400-ghi789",
      "timestamp": "2025-12-05T10:03:20Z",
      "operation": "complete",
      "task_id": "task-1733395200-xyz789",
      "user": "system",
      "details": {
        "completion_time": "2025-12-05T10:03:20Z"
      },
      "before": {
        "status": "in_progress"
      },
      "after": {
        "status": "completed",
        "completed_at": "2025-12-05T10:03:20Z"
      }
    },
    {
      "id": "log-1733396000-jkl012",
      "timestamp": "2025-12-05T10:13:20Z",
      "operation": "archive",
      "task_id": "task-1733395200-xyz789",
      "user": "system",
      "details": {
        "reason": "auto-archive after 7 days"
      },
      "before": {
        "location": "todo.json"
      },
      "after": {
        "location": "todo-archive.json"
      }
    }
  ]
}
```

### Operation Types
- `create`: New task added
- `update`: Task field modified
- `complete`: Task marked completed
- `archive`: Task moved to archive
- `restore`: Task restored from archive
- `delete`: Task permanently deleted (rare)
- `validate`: Validation run
- `backup`: Backup created

---

## Error Handling and Recovery

### Error Categories

**1. Schema Validation Errors**
```
Error: Invalid JSON Schema
File: .claude/todo.json
Issue: Missing required field "activeForm" in task ID: task-123
Fix: Add activeForm field to task
```

**2. Anti-Hallucination Errors**
```
Error: Duplicate task ID detected
File: .claude/todo.json
Duplicate ID: task-456
Location: Line 23 and Line 45
Fix: Regenerate unique ID for one task
```

**3. File System Errors**
```
Error: Cannot write to file
File: .claude/todo.json
Reason: Permission denied
Fix: Check file permissions (chmod 644)
```

**4. Configuration Errors**
```
Error: Invalid configuration value
File: .claude/todo-config.json
Field: archive.archive_after_days
Value: -5
Fix: Must be positive integer
```

### Recovery Procedures

**Automatic Recovery**:
1. Detect error
2. Check for backup
3. Validate backup integrity
4. Restore from most recent valid backup
5. Log recovery operation

**Manual Recovery**:
```bash
# List available backups
ls -la .claude/.backups/

# Validate backup
~/.claude-todo/scripts/validate.sh .claude/.backups/todo.json.1

# Restore specific backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

**Corruption Detection**:
- Run validation on every read operation
- Detect corruption early
- Prevent propagation to archive
- Alert user immediately

---

## Performance Considerations

### Optimization Strategies

**1. Lazy Loading**
- Only load files when needed
- Cache parsed JSON in memory (single operation)
- Invalidate cache on write

**2. Efficient Filtering**
- Use jq for JSON manipulation (faster than bash loops)
- Index-based lookups for task IDs
- Binary search for sorted data

**3. Batch Operations**
- Archive multiple tasks in single operation
- Validate once after all changes
- Single log entry for batch

**4. File Size Management**
- Archive old completed tasks
- Rotate log files at configurable threshold
- Compress old archives (optional)

### Performance Targets

- Task creation: < 100ms
- Task completion: < 100ms
- Archive operation: < 500ms for 100 tasks
- Validation: < 200ms for 100 tasks
- List operation: < 50ms for 100 tasks

---

## Security Considerations

### File Permissions
```bash
# Configuration files: readable by all, writable by owner
chmod 644 .claude/todo*.json

# Scripts: executable by owner
chmod 755 ~/.claude-todo/scripts/*.sh

# Backups: owner only
chmod 700 .claude/.backups/
chmod 600 .claude/.backups/*.json
```

### Input Validation
- Sanitize all user inputs
- Prevent command injection in task content
- Escape special characters
- Limit input length (prevent DOS)

### Data Privacy
- Tasks stored locally only
- No external network calls
- No telemetry or tracking
- User controls all data

---

## Extension Points

### 1. Custom Validators
```bash
# User can add custom validation scripts
.claude/validators/
├── no-swear-words.sh
├── project-prefix.sh
└── team-standards.sh

# Called by validate.sh after schema validation
```

### 2. Event Hooks
```bash
# Trigger custom scripts on events
.claude/hooks/
├── on-task-create.sh
├── on-task-complete.sh
└── on-archive.sh

# Example: Send notification, update external tracker
```

### 3. Custom Formatters
```bash
# Add output format plugins
~/.claude-todo/formatters/
├── html-report.sh
├── csv-export.sh
└── slack-message.sh

# Used by list-tasks.sh and stats.sh
```

### 4. Integration APIs
```bash
# Export tasks to external systems
~/.claude-todo/integrations/
├── jira-sync.sh
├── github-issues.sh
└── trello-board.sh
```

---

## Testing Strategy

### Unit Tests
- Test individual validation functions
- Test atomic file operations
- Test log entry creation
- Test configuration parsing

### Integration Tests
- Test complete workflows (create → complete → archive)
- Test error recovery
- Test concurrent operations
- Test backup/restore

### Validation Tests
- Test schema compliance
- Test anti-hallucination detection
- Test edge cases (empty files, malformed JSON)
- Test large datasets (1000+ tasks)

### Test Data Fixtures
```
tests/fixtures/
├── valid-todo.json          # Correct format
├── invalid-schema.json      # Schema violation
├── duplicate-ids.json       # Anti-hallucination violation
├── large-dataset.json       # Performance testing
└── edge-cases.json          # Boundary conditions
```

---

## Maintenance and Monitoring

### Health Checks
```bash
# Run periodic health check
~/.claude-todo/scripts/health-check.sh

# Checks:
- File integrity
- Schema compliance
- Backup freshness
- Log file size
- Archive size
- Configuration validity
```

### Monitoring Metrics
- Total active tasks
- Archive size
- Log file size
- Backup count
- Last validation time
- Error rate

### Maintenance Tasks
- **Daily**: Validate files, backup
- **Weekly**: Archive completed tasks
- **Monthly**: Rotate logs, compress old archives
- **Quarterly**: Review configuration, update schemas

---

## Migration and Versioning

### Version Compatibility
```
schemas/todo.schema.json → version: "1.0.0"

# Breaking changes: Major version bump (2.0.0)
# New fields: Minor version bump (1.1.0)
# Bug fixes: Patch version bump (1.0.1)
```

### Migration Scripts
```bash
~/.claude-todo/migrations/
├── migrate-1.0-to-1.1.sh
├── migrate-1.1-to-2.0.sh
└── rollback-2.0-to-1.1.sh

# Automatically run on upgrade
./install.sh --upgrade
```

### Backward Compatibility
- New fields optional by default
- Deprecated fields supported for 2 major versions
- Clear migration documentation
- Automatic schema version detection

---

## Summary

This architecture provides:

✅ **Robust**: Schema validation + anti-hallucination checks
✅ **Maintainable**: Clear separation of concerns, modular design
✅ **Safe**: Atomic operations, automatic backups, validation gates
✅ **Extensible**: Hooks, validators, formatters, integrations
✅ **Performant**: Optimized for 1000+ tasks
✅ **User-Friendly**: Zero-config defaults, clear error messages
✅ **Auditable**: Comprehensive logging, change history
✅ **Portable**: Single installation, per-project initialization

The system scales from simple personal task tracking to complex team workflows while maintaining data integrity and preventing hallucination-based errors.
