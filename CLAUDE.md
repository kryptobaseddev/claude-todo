# CLAUDE-TODO System

Task management system for Claude Code with anti-hallucination validation, auto-archiving, and audit trails.

## Stack
- Bash scripts (primary implementation)
- JSON Schema (validation)
- jq (JSON manipulation)

## Commands
- `./install.sh`: Global installation to ~/.claude-todo/
- `~/.claude-todo/scripts/init.sh`: Initialize project (.claude/ directory)
- `~/.claude-todo/scripts/add-task.sh "Task"`: Create task
- `~/.claude-todo/scripts/complete-task.sh <id>`: Mark complete
- `~/.claude-todo/scripts/archive.sh`: Archive completed tasks
- `~/.claude-todo/scripts/validate.sh`: Validate all JSON files
- `~/.claude-todo/scripts/list-tasks.sh`: Display tasks

## Structure
```
schemas/          # JSON Schema definitions
templates/        # Starter templates for new projects
scripts/          # User-facing operational scripts
lib/              # Shared functions (validation, logging, file-ops)
tests/            # Test suite with fixtures
docs/             # Documentation
```

## Key Files
- Schema definitions: `schemas/todo.schema.json`
- Library core: `lib/validation.sh`, `lib/file-ops.sh`, `lib/logging.sh`
- Main scripts: `scripts/add-task.sh`, `scripts/complete-task.sh`

## Rules
- **CRITICAL**: All write operations MUST use atomic pattern (temp file → validate → backup → rename)
- **CRITICAL**: Every task requires both `title` AND `description` fields (anti-hallucination)
- **IMPORTANT**: Run `validate.sh` after any manual JSON edits
- Status enum is strict: `pending | active | blocked | done` only
- Task IDs must be unique across todo.json AND todo-archive.json
- All operations log to todo-log.json (append-only)

## Anti-Hallucination Checks
Before any task operation, validate:
1. ID uniqueness (no duplicates)
2. Status is valid enum value
3. Timestamps not in future
4. title/description both present and different
5. No duplicate task descriptions

## Time Estimates — PROHIBITED
**DO NOT** estimate hours, days, or duration for any task. Ever.
You cannot accurately predict time. Estimates create false precision and bad decisions.
**Instead**: Describe scope, complexity, and dependencies. Use relative sizing if pressed (small/medium/large). If a user insists on time estimates, state clearly that you cannot provide accurate predictions and redirect to scope-based planning.

## Docs
- Architecture: @ARCHITECTURE.md
- Design Summary: @SYSTEM-DESIGN-SUMMARY.md
- Installation: @docs/installation.md
- Usage: @docs/usage.md

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
