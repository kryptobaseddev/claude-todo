# CLAUDE-TODO Quick Reference Card

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────┐
│ Global: ~/.claude-todo/                             │
│ ├── schemas/ (JSON Schema validation)              │
│ ├── scripts/ (user-facing operations)              │
│ ├── lib/ (shared functions)                        │
│ └── templates/ (starter files)                     │
└─────────────────────────────────────────────────────┘
                      │
                      │ Provides to
                      ▼
┌─────────────────────────────────────────────────────┐
│ Project: .claude/                                   │
│ ├── todo.json (active tasks)                       │
│ ├── todo-archive.json (completed)                  │
│ ├── todo-config.json (settings)                    │
│ ├── todo-log.json (audit trail)                    │
│ └── .backups/ (versioned backups)                  │
└─────────────────────────────────────────────────────┘
```

## Essential Commands

```bash
# SETUP
./install.sh                          # Install globally
~/.claude-todo/scripts/init.sh        # Initialize project

# TASKS
add-task.sh "Task description"        # Create task
complete-task.sh <task-id>            # Complete task
list-tasks.sh                         # List all tasks
list-tasks.sh --status pending        # Filter by status

# MAINTENANCE
archive.sh                            # Archive completed tasks
validate.sh                           # Validate all files
backup.sh                             # Manual backup
stats.sh                              # Show statistics
```

## Data Flow Patterns

### Task Lifecycle
```
CREATE → VALIDATE → WRITE → BACKUP → LOG
  ↓
PENDING → ACTIVE → DONE
            ↓
         BLOCKED (optional)
            ↓
         ARCHIVE (after N days)
```

### Validation Pipeline
```
JSON → Schema Check → Anti-Hallucination → Cross-File → ✅ Valid
        ↓               ↓                    ↓
     Structure      Semantics           Integrity
```

### Atomic Write Pattern
```
1. Write to .tmp
2. Validate .tmp
3. Backup original
4. Atomic rename .tmp → .json
5. Rollback on error
```

## Anti-Hallucination Checks

| Check | Purpose | Example Error |
|-------|---------|---------------|
| **ID Uniqueness** | No duplicate IDs | "Duplicate ID: task-123" |
| **Status Enum** | Valid status only | "Invalid status: 'completed'" |
| **Timestamp Sanity** | Not in future | "created_at in future" |
| **Content Pairing** | Both title & description | "Missing description" |
| **Duplicate Content** | No identical tasks | "Duplicate: 'Fix bug'" |

## File Interaction Matrix

| Operation | todo.json | archive.json | config.json | log.json |
|-----------|-----------|--------------|-------------|----------|
| **add-task** | R+W | - | R | W |
| **complete-task** | R+W | - | R | W |
| **archive** | R+W | R+W | R | W |
| **list-tasks** | R | R* | R | - |
| **stats** | R | R | R | R |
| **validate** | R | R | R | R |

*R* = Read, *W* = Write, *R+W* = Read then Write (atomic update)

## Configuration Hierarchy

```
Defaults → Global → Project → Environment → CLI
           (~/.c-t)  (.claude)  (CLAUDE_TODO_*) (--flags)
                                                    │
                                              Final Value
```

## Schema Files

| File | Purpose | Key Validations |
|------|---------|-----------------|
| **todo.schema.json** | Active tasks | Status enum, required fields |
| **archive.schema.json** | Completed tasks | Same as todo.schema.json |
| **config.schema.json** | Configuration | Value ranges, types |
| **log.schema.json** | Change log | Operation types, timestamps |

## Library Functions

### validation.sh
```bash
validate_schema "$file"              # JSON Schema validation
validate_anti_hallucination "$file"  # Semantic checks
check_duplicate_ids "$file1" "$file2" # Cross-file uniqueness
```

### file-ops.sh
```bash
atomic_write "$file" "$content"      # Safe file writing
backup_file "$file"                  # Create versioned backup
restore_backup "$backup_file"        # Restore from backup
```

### logging.sh
```bash
log_operation "create" "$task_id"    # Log to todo-log.json
create_log_entry "$operation" "$id"  # Generate log entry
```

### config.sh
**Note**: Not implemented. Configuration is loaded directly in scripts using jq.

## Task Object Structure

```json
{
  "id": "task-1733395200-abc123",
  "status": "pending|active|blocked|done",
  "title": "Task description (imperative)",
  "description": "Task description (continuous)",
  "createdAt": "2025-12-05T10:00:00Z",
  "completedAt": "2025-12-05T10:30:00Z"
}
```

## Log Entry Structure

```json
{
  "id": "log-1733395200-xyz789",
  "timestamp": "2025-12-05T10:00:00Z",
  "operation": "create|update|complete|archive",
  "task_id": "task-1733395200-abc123",
  "before": {"status": "pending"},
  "after": {"status": "in_progress"}
}
```

## Backup Rotation

```
.backups/
├── todo.json.1  ← Most recent (current backup)
├── todo.json.2
├── ...
└── todo.json.10 ← Oldest (will be rotated out)

On next operation:
├── todo.json.1  ← NEW backup
├── todo.json.2  ← Was .1
└── [old .10 deleted]
```

## Error Codes

| Code | Meaning |
|------|---------|
| **0** | Success |
| **1** | Schema validation error |
| **2** | Semantic validation error (anti-hallucination) |
| **3** | File operation error |
| **4** | Configuration error |

## Common Patterns

### Adding Custom Validation
```bash
# .claude/validators/my-validator.sh
validate_custom() {
    local todo_file="$1"
    # Custom validation logic
    return 0  # Success
}
```

### Event Hook
```bash
# .claude/hooks/on-task-create.sh
#!/usr/bin/env bash
task_id="$1"
# Custom action (notify, log, sync)
```

### Custom Formatter
```bash
# ~/.claude-todo/formatters/csv-export.sh
format_csv() {
    local todo_file="$1"
    jq -r '.todos[] | [.id, .status, .title] | @csv' "$todo_file"
}
```

## Testing Quick Reference

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test
./tests/test-validation.sh

# Test with fixtures
./tests/test-validation.sh fixtures/valid-todo.json
```

## Debugging

```bash
# Verbose mode
CLAUDE_TODO_LOG_LEVEL=debug ./scripts/add-task.sh "Test"

# Trace execution
bash -x ./scripts/archive.sh

# Validate specific file
jq -e . .claude/todo.json && echo "Valid JSON"
```

## Performance Targets

| Operation | Target | Note |
|-----------|--------|------|
| Task creation | < 100ms | Single task |
| Task completion | < 100ms | Single task |
| Archive | < 500ms | 100 tasks |
| Validation | < 200ms | 100 tasks |
| List | < 50ms | 100 tasks |

## Best Practices

1. **Always validate** before committing changes
2. **Use atomic writes** for all file operations
3. **Backup before modify** - automatic with atomic_write()
4. **Log all operations** - audit trail is critical
5. **Check return codes** - handle errors gracefully
6. **Quote variables** - `"$var"` not `$var`
7. **Use readonly** for constants
8. **Document functions** - purpose, args, returns

## Common Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| "Duplicate ID: task-123" | Same ID exists | Regenerate ID |
| "Missing description" | Task incomplete | Add description field |
| "Invalid status: 'completed'" | Wrong enum value | Use: pending, active, blocked, or done |
| "Timestamp in future" | Clock skew | Check system time |
| "Schema validation failed" | Structure wrong | Check against schema |

## Recommended Aliases

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

## Directory Permissions

```bash
# Data files
chmod 644 .claude/todo*.json

# Scripts
chmod 755 ~/.claude-todo/scripts/*.sh

# Backups (owner only)
chmod 700 .claude/.backups/
chmod 600 .claude/.backups/*.json
```

## Key Design Principles

1. **Single Source of Truth**: todo.json is authoritative
2. **Immutable History**: Append-only log
3. **Fail-Safe Operations**: Atomic writes with rollback
4. **Schema-First**: Validation prevents corruption
5. **Zero-Config Defaults**: Works out of the box

## Extension Points

| Type | Location | Purpose |
|------|----------|---------|
| **Validators** | `.claude/validators/` | Custom validation rules |
| **Hooks** | `.claude/hooks/` | Event-triggered actions |
| **Formatters** | `~/.claude-todo/formatters/` | Output formats |
| **Integrations** | `~/.claude-todo/integrations/` | External system sync |

## Documentation Links

| Document | Purpose |
|----------|---------|
| **ARCHITECTURE.md** | Complete system design |
| **DATA-FLOW-DIAGRAMS.md** | Visual workflows |
| **SYSTEM-DESIGN-SUMMARY.md** | Executive overview |
| **docs/usage.md** | Detailed usage guide |
| **docs/configuration.md** | Config reference |

## Upgrade Path

```bash
# Check current version
cat ~/.claude-todo/VERSION

# Upgrade to latest
cd claude-todo
git pull
./install.sh --upgrade

# Migrations run automatically
```

## Health Check

```bash
# Run system health check

Checks:
✅ File integrity
✅ Schema compliance
✅ Backup freshness
✅ Log file size
✅ Archive size
✅ Configuration validity
```

## When Things Go Wrong

```bash
# 1. Validate files
~/.claude-todo/scripts/validate.sh

# 2. Check backups
ls -lh .claude/.backups/

# 3. Restore if needed
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1

# 4. Check logs
jq '.entries[-10:]' .claude/todo-log.json
```

## Installation Checklist

- [ ] Clone repository
- [ ] Run `./install.sh`
- [ ] Verify `~/.claude-todo/` created
- [ ] Add to PATH (optional)
- [ ] Navigate to project
- [ ] Run `init.sh`
- [ ] Verify `.claude/` created
- [ ] Check `.gitignore` updated
- [ ] Run `validate.sh` to confirm
- [ ] Add first task to test

## Quick Troubleshooting

**Problem**: "Permission denied"
**Solution**: `chmod 755 ~/.claude-todo/scripts/*.sh`

**Problem**: "Invalid JSON"
**Solution**: `validate.sh --fix` or restore backup

**Problem**: "Duplicate ID"
**Solution**: Edit JSON manually or restore backup

**Problem**: "Missing schema"
**Solution**: Re-run `./install.sh`

---

**For detailed information, always refer to ARCHITECTURE.md**
