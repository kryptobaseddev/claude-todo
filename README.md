# CLAUDE-TODO System

> A production-grade task management system for Claude Code with automatic archiving, comprehensive validation, and anti-hallucination protection.

## Overview

CLAUDE-TODO is a robust, schema-validated task management system specifically designed for Claude Code. It provides comprehensive anti-hallucination mechanisms, automatic archiving, complete audit trails, and atomic file operations to ensure data integrity.

### Key Features

- **Anti-Hallucination Protection**: Multi-layer validation prevents AI-generated errors
- **Automatic Archiving**: Configurable policies for completed task archiving
- **Complete Audit Trail**: Immutable change log tracks every operation
- **Atomic Operations**: Safe file handling with automatic backups and rollback
- **Schema Validation**: JSON Schema enforcement ensures data integrity
- **Zero-Config Defaults**: Works out of the box with sensible defaults
- **Extensible Design**: Custom validators, hooks, formatters, and integrations

## Quick Start

### Installation

```bash
# 1. Clone the repository
git clone <repository-url> claude-todo
cd claude-todo

# 2. Install globally
./install.sh

# 3. Initialize in your project
cd /path/to/your/project
~/.claude-todo/scripts/init.sh
```

### Basic Usage

```bash
# Add a task
~/.claude-todo/scripts/add-task.sh "Implement authentication"

# List all tasks
~/.claude-todo/scripts/list-tasks.sh

# Complete a task
~/.claude-todo/scripts/complete-task.sh task-1733395200-abc123

# Show statistics
~/.claude-todo/scripts/stats.sh

# Archive completed tasks
~/.claude-todo/scripts/archive.sh
```

### Recommended Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
alias ct-add='~/.claude-todo/scripts/add-task.sh'
alias ct-list='~/.claude-todo/scripts/list-tasks.sh'
alias ct-complete='~/.claude-todo/scripts/complete-task.sh'
alias ct-stats='~/.claude-todo/scripts/stats.sh'
alias ct-archive='~/.claude-todo/scripts/archive.sh'
```

## Architecture

### System Structure

```
Global Installation (~/.claude-todo/)
├── schemas/           JSON Schema validation definitions
├── scripts/           User-facing operational scripts
├── lib/               Shared library functions
└── templates/         Starter templates

Per-Project Instance (.claude/)
├── todo.json          Active tasks
├── todo-archive.json  Completed tasks
├── todo-config.json   Project configuration
├── todo-log.json      Complete audit trail
└── .backups/          Automatic versioned backups
```

### Core Components

1. **Task Storage**: Active tasks in `todo.json`, completed in `todo-archive.json`
2. **Configuration**: Flexible per-project and global settings
3. **Audit Trail**: Complete change history in `todo-log.json`
4. **Validation**: Schema + semantic anti-hallucination checks
5. **Backups**: Automatic versioned backups before every modification

## Anti-Hallucination Protection

CLAUDE-TODO implements multiple layers of protection against AI-generated errors:

### Layer 1: JSON Schema Enforcement
- Structure validation (required fields, types)
- Enum constraints (status must be: pending, in_progress, completed)
- Format validation (ISO 8601 timestamps, proper IDs)

### Layer 2: Semantic Validation
- **ID Uniqueness**: No duplicate IDs within or across files
- **Timestamp Sanity**: created_at not in future, completed_at after created_at
- **Content Pairing**: Every task must have both `content` AND `activeForm`
- **Duplicate Detection**: Warning on identical task descriptions
- **Status Transitions**: Only valid state transitions allowed

### Layer 3: Cross-File Integrity
- Referential integrity (log entries reference valid task IDs)
- Archive consistency (archived tasks match completion criteria)
- No data loss verification (task count before/after operations)
- Synchronized multi-file updates

### Layer 4: Configuration Validation
- Policy enforcement (archive policies applied consistently)
- Constraint checking (config values within valid ranges)
- Dependency resolution (related options validated together)

## Data Integrity

### Atomic Write Pattern

All file modifications follow this pattern:

```
1. Generate temp file (.todo.json.tmp)
2. Write data to temp file
3. Validate temp file (schema + anti-hallucination)
4. Backup original file
5. Atomic rename (OS-level guarantee, no partial writes)
6. Rollback on any failure
```

### Backup System

- Automatic backup before every write operation
- Versioned backups (.backups/todo.json.1 through .10)
- Automatic rotation (oldest deleted when limit reached)
- Manual backup and restore capabilities

### Change Log

Every operation logged with:
- Timestamp
- Operation type (create, update, complete, archive)
- Task ID reference
- Before/after state
- User and context

## Configuration

### Configuration Hierarchy

Values resolved in this order (later overrides earlier):

```
Defaults → Global → Project → Environment → CLI Flags
           (~/.c-t)  (.claude)  (CLAUDE_TODO_*)  (--options)
```

### Key Configuration Options

```json
{
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
  "backups": {
    "enabled": true,
    "max_backups": 10,
    "backup_on_write": true
  }
}
```

## Available Scripts

### Core Operations
- `init.sh` - Initialize project with todo system
- `add-task.sh` - Create new task with validation
- `complete-task.sh` - Mark task as completed
- `archive.sh` - Archive completed tasks

### Query Operations
- `list-tasks.sh` - Display tasks with filtering
- `stats.sh` - Generate statistics and reports

### Maintenance Operations
- `validate.sh` - Validate all JSON files
- `backup.sh` - Create manual backup
- `restore.sh` - Restore from backup
- `health-check.sh` - System health verification

## Extension Points

### Custom Validators
Place custom validation scripts in `.claude/validators/`:

```bash
# .claude/validators/team-standards.sh
validate_team_standards() {
    # Custom validation logic
    return 0
}
```

### Event Hooks
Place event hooks in `.claude/hooks/`:

```bash
# .claude/hooks/on-task-complete.sh
#!/usr/bin/env bash
task_id="$1"
# Send notification, update external tracker, etc.
```

### Custom Formatters
Add output formatters in `~/.claude-todo/formatters/`:

```bash
# ~/.claude-todo/formatters/csv-export.sh
format_csv() {
    local todo_file="$1"
    jq -r '.todos[] | [.id, .status, .content] | @csv' "$todo_file"
}
```

### Integrations
Create integration scripts in `~/.claude-todo/integrations/`:

```bash
# ~/.claude-todo/integrations/jira-sync.sh
# Sync tasks with JIRA
```

## Documentation

| Document | Purpose |
|----------|---------|
| **README.md** | This file - Quick start and overview |
| **ARCHITECTURE.md** | Complete system architecture and design |
| **DATA-FLOW-DIAGRAMS.md** | Visual workflows and data relationships |
| **SYSTEM-DESIGN-SUMMARY.md** | Executive overview of the system |
| **QUICK-REFERENCE.md** | Quick reference card for developers |
| **docs/installation.md** | Detailed installation guide |
| **docs/usage.md** | Comprehensive usage examples |
| **docs/configuration.md** | Configuration reference |
| **docs/schema-reference.md** | Schema documentation |
| **docs/troubleshooting.md** | Common issues and solutions |

## Testing

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test suite
./tests/test-validation.sh
./tests/test-archive.sh

# Test with verbose output
CLAUDE_TODO_LOG_LEVEL=debug ./tests/run-all-tests.sh
```

## Performance

Target performance metrics:

| Operation | Target Time |
|-----------|-------------|
| Task creation | < 100ms |
| Task completion | < 100ms |
| Archive (100 tasks) | < 500ms |
| Validation (100 tasks) | < 200ms |
| List tasks | < 50ms |

## Security

- **Local Storage**: All data stored locally, no external calls
- **File Permissions**: Proper permissions enforced (644 for data, 755 for scripts)
- **Input Validation**: All user inputs sanitized
- **No Telemetry**: Complete user control over data

## Requirements

### Required
- Bash 4.0+
- jq (JSON processor)
- One JSON Schema validator (ajv, jsonschema, or jq-based fallback)

### Optional
- git (for version control integration)
- cron (for automatic archival scheduling)

## Troubleshooting

### Common Issues

**"Permission denied" error**
```bash
chmod 755 ~/.claude-todo/scripts/*.sh
```

**"Invalid JSON" error**
```bash
# Try automatic fix
~/.claude-todo/scripts/validate.sh --fix

# Or restore from backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

**"Duplicate ID" error**
```bash
# Manually edit to regenerate ID or restore backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

### Health Check

```bash
~/.claude-todo/scripts/health-check.sh
```

Checks:
- File integrity
- Schema compliance
- Backup freshness
- Log file size
- Configuration validity

## Upgrading

```bash
cd claude-todo
git pull
./install.sh --upgrade
```

Migrations run automatically when needed.

## Contributing

Contributions welcome! Please:

1. Follow the existing code style (see code_style_conventions.md memory)
2. Add tests for new features
3. Update documentation
4. Run validation before submitting

## Design Principles

1. **Single Source of Truth**: todo.json is authoritative
2. **Immutable History**: Append-only change log
3. **Fail-Safe Operations**: Atomic writes with rollback
4. **Schema-First**: Validation prevents corruption
5. **Idempotent Scripts**: Safe to run multiple times
6. **Zero-Config Defaults**: Sensible defaults, optional customization

## Success Criteria

CLAUDE-TODO provides:

✅ **Robust**: Schema validation + anti-hallucination checks
✅ **Maintainable**: Clear separation of concerns, modular design
✅ **Safe**: Atomic operations, automatic backups, validation gates
✅ **Extensible**: Hooks, validators, formatters, integrations
✅ **Performant**: Optimized for 1000+ tasks
✅ **User-Friendly**: Zero-config defaults, clear error messages
✅ **Auditable**: Comprehensive logging, complete change history
✅ **Portable**: Single installation, per-project initialization

## License

MIT License - See LICENSE file for details

## Support

For detailed information, see:
- **ARCHITECTURE.md** - Complete system design
- **QUICK-REFERENCE.md** - Quick reference card
- **docs/** directory - Comprehensive guides

---

**Ready to get started?** Run `./install.sh` to begin!
