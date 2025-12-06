# Usage Guide

Complete guide to using the claude-todo task management system.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Basic Workflow](#basic-workflow)
3. [Task Lifecycle](#task-lifecycle)
4. [Command Reference](#command-reference)
5. [Advanced Operations](#advanced-operations)
6. [CLAUDE.md Integration](#claudemd-integration)
7. [Filtering and Searching](#filtering-and-searching)
8. [Configuration](#configuration)
9. [Examples and Recipes](#examples-and-recipes)

---

## Quick Start

### First-Time Setup

```bash
# 1. Install globally
./install.sh

# 2. Navigate to your project
cd /path/to/your/project

# 3. Initialize todo system
~/.claude-todo/scripts/init.sh

# 4. Create your first task
~/.claude-todo/scripts/add-task.sh "Implement user authentication" \
  --status pending \
  --priority high \
  --description "Add JWT-based authentication with email/password login"
```

### Daily Workflow

```bash
# List current tasks
~/.claude-todo/scripts/list-tasks.sh

# Mark task complete
~/.claude-todo/scripts/complete-task.sh <task-id>

# View statistics
~/.claude-todo/scripts/stats.sh
```

---

## Basic Workflow

### 1. Creating Tasks

#### Simple Task Creation

```bash
# Minimal task (title only)
~/.claude-todo/scripts/add-task.sh "Fix login bug"

# Task with status and priority
~/.claude-todo/scripts/add-task.sh "Add user dashboard" \
  --status pending \
  --priority high

# Complete task with all fields
~/.claude-todo/scripts/add-task.sh "Implement payment processing" \
  --status pending \
  --priority critical \
  --description "Integrate Stripe API for subscription payments" \
  --files "src/payments/stripe.ts,src/api/checkout.ts" \
  --acceptance "Successful test payment,Error handling verified" \
  --labels "backend,payment,api"
```

#### Task Field Details

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Brief task summary (imperative form) |
| `status` | enum | Yes | One of: `pending`, `active`, `blocked`, `done` |
| `priority` | enum | No | One of: `low`, `medium`, `high`, `critical` |
| `description` | string | No | Detailed task explanation |
| `files` | array | No | Comma-separated file paths affected by task |
| `acceptance` | array | No | Comma-separated acceptance criteria |
| `depends` | array | No | Comma-separated task IDs this task depends on |
| `blockedBy` | array | No | Comma-separated task IDs blocking this task |
| `notes` | string | No | Additional notes or context |
| `labels` | array | No | Comma-separated tags for categorization |

### 2. Listing Tasks

#### Basic Listing

```bash
# List all active tasks (default)
~/.claude-todo/scripts/list-tasks.sh

# List tasks with specific status
~/.claude-todo/scripts/list-tasks.sh --status pending
~/.claude-todo/scripts/list-tasks.sh --status active
~/.claude-todo/scripts/list-tasks.sh --status blocked
~/.claude-todo/scripts/list-tasks.sh --status done

# List all tasks including archived
~/.claude-todo/scripts/list-tasks.sh --all
```

#### Output Formats

```bash
# Human-readable terminal output (default)
~/.claude-todo/scripts/list-tasks.sh --format text

# JSON output for scripting
~/.claude-todo/scripts/list-tasks.sh --format json

# Markdown format for documentation
~/.claude-todo/scripts/list-tasks.sh --format markdown

# ASCII table format
~/.claude-todo/scripts/list-tasks.sh --format table
```

#### Filtering Options

```bash
# Filter by priority
~/.claude-todo/scripts/list-tasks.sh --priority high

# Filter by label
~/.claude-todo/scripts/list-tasks.sh --label backend

# Tasks created after specific date
~/.claude-todo/scripts/list-tasks.sh --since 2025-12-01

# Limit number of results
~/.claude-todo/scripts/list-tasks.sh --limit 10
```

### 3. Completing Tasks

#### Basic Completion

```bash
# Complete a task by ID
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789

# Complete with completion notes
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789 \
  --notes "Implemented JWT tokens with refresh mechanism"

# Complete and auto-archive immediately
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789 --archive
```

#### What Happens on Completion

1. Task status changes from `pending`/`active` → `done`
2. `completedAt` timestamp added automatically
3. Operation logged to `todo-log.json`
4. Auto-archive triggered if enabled in config
5. Success message displays task ID and completion time

### 4. Archiving Tasks

#### Manual Archive

```bash
# Archive completed tasks older than configured days
~/.claude-todo/scripts/archive.sh

# Force archive all completed tasks regardless of age
~/.claude-todo/scripts/archive.sh --force

# Archive completed tasks older than specific days
~/.claude-todo/scripts/archive.sh --days 14

# Archive with verbose output
~/.claude-todo/scripts/archive.sh --verbose
```

#### Automatic Archive

Configure in `.claude/todo-config.json`:

```json
{
  "archive": {
    "enabled": true,
    "archive_after_days": 7,
    "auto_archive_on_complete": true
  }
}
```

When enabled, tasks are automatically archived after completion when they exceed `archive_after_days` threshold.

---

## Task Lifecycle

### Status Flow

```
┌──────────┐
│ pending  │ ◄───── Initial creation
└────┬─────┘
     │
     ▼
┌──────────┐
│  active  │ ◄───── Work begins
└────┬─────┘
     │
     ├───► ┌──────────┐
     │     │ blocked  │ ◄───── Impediment identified
     │     └────┬─────┘
     │          │
     │          └────► Resume when unblocked
     │
     ▼
┌──────────┐
│   done   │ ◄───── Task completed
└────┬─────┘
     │
     ▼
┌──────────┐
│ archived │ ◄───── Moved to archive after retention period
└──────────┘
```

### Status Transitions

| From | To | Trigger | Command |
|------|-----|---------|---------|
| `pending` | `active` | Work starts | Update status manually |
| `active` | `done` | Task complete | `complete-task.sh` |
| `active` | `blocked` | Impediment found | Update status manually |
| `blocked` | `active` | Blocker resolved | Update status manually |
| `done` | `archived` | After retention period | `archive.sh` |

### Archive Policies

**Default Policy**:
- Completed tasks older than 7 days → archived
- Max archive size: 1000 tasks
- Manual archive available anytime

**Custom Retention**:
```json
{
  "archive": {
    "archive_after_days": 30,    // Keep completed tasks 30 days
    "max_archive_size": 5000,    // Store up to 5000 archived tasks
    "auto_archive_on_complete": false  // Manual archive only
  }
}
```

---

## Command Reference

### init.sh

Initialize todo system in a project.

```bash
~/.claude-todo/scripts/init.sh [OPTIONS]
```

**Options**:
- `--force`: Overwrite existing todo files
- `--template <path>`: Use custom template instead of default

**Examples**:
```bash
# Standard initialization
~/.claude-todo/scripts/init.sh

# Force re-initialization
~/.claude-todo/scripts/init.sh --force

# Initialize with custom template
~/.claude-todo/scripts/init.sh --template ~/my-todo-template.json
```

**Output**:
- Creates `.claude/` directory
- Copies template files
- Initializes empty log file
- Validates all files
- Updates `.gitignore`

---

### add-task.sh

Create a new task with validation.

```bash
~/.claude-todo/scripts/add-task.sh "TASK_TITLE" [OPTIONS]
```

**Required Arguments**:
- `TASK_TITLE`: Task description (quoted if contains spaces)

**Options**:
- `--status <status>`: Task status (default: `pending`)
- `--priority <priority>`: Task priority (default: `medium`)
- `--description <text>`: Detailed description
- `--files <paths>`: Comma-separated file paths
- `--acceptance <criteria>`: Comma-separated acceptance criteria
- `--depends <ids>`: Comma-separated task IDs this depends on
- `--blocked-by <ids>`: Comma-separated blocking task IDs
- `--notes <text>`: Additional notes
- `--labels <tags>`: Comma-separated labels

**Examples**:
```bash
# Simple task
~/.claude-todo/scripts/add-task.sh "Fix navigation bug"

# Task with priority
~/.claude-todo/scripts/add-task.sh "Security audit" --priority critical

# Complex task with all fields
~/.claude-todo/scripts/add-task.sh "Implement user authentication" \
  --status pending \
  --priority high \
  --description "Add JWT-based auth with email/password" \
  --files "src/auth/jwt.ts,src/middleware/auth.ts" \
  --acceptance "Login endpoint works,Token refresh implemented,Error handling complete" \
  --labels "backend,security,authentication" \
  --notes "Reference: https://jwt.io/introduction"

# Dependent task
~/.claude-todo/scripts/add-task.sh "Add logout endpoint" \
  --depends task-1733395200-xyz789 \
  --description "Implement logout with token invalidation"

# Blocked task
~/.claude-todo/scripts/add-task.sh "Deploy to production" \
  --blocked-by task-1733395200-abc123 \
  --status blocked \
  --notes "Blocked until security review completes"
```

**Validation**:
- Title must not be empty
- Status must be valid enum value
- Duplicate titles trigger warning
- Dependencies/blockers validated against existing tasks
- All fields validated against schema

---

### list-tasks.sh

Display current tasks with filtering.

```bash
~/.claude-todo/scripts/list-tasks.sh [OPTIONS]
```

**Options**:
- `--status <status>`: Filter by status (`pending`, `active`, `blocked`, `done`)
- `--priority <priority>`: Filter by priority (`low`, `medium`, `high`, `critical`)
- `--label <label>`: Filter by label
- `--since <date>`: Show tasks created after date (ISO 8601)
- `--limit <n>`: Limit results to N tasks
- `--all`: Include archived tasks
- `--format <format>`: Output format (`text`, `json`, `markdown`, `table`)
- `--sort <field>`: Sort by field (`status`, `priority`, `createdAt`)
- `--reverse`: Reverse sort order

**Examples**:
```bash
# All active tasks (default)
~/.claude-todo/scripts/list-tasks.sh

# Only pending tasks
~/.claude-todo/scripts/list-tasks.sh --status pending

# High priority tasks
~/.claude-todo/scripts/list-tasks.sh --priority high

# Backend tasks only
~/.claude-todo/scripts/list-tasks.sh --label backend

# Recent tasks (last 7 days)
~/.claude-todo/scripts/list-tasks.sh --since 2025-11-28

# Top 5 tasks
~/.claude-todo/scripts/list-tasks.sh --limit 5

# JSON output for scripting
~/.claude-todo/scripts/list-tasks.sh --format json

# Markdown checklist
~/.claude-todo/scripts/list-tasks.sh --format markdown

# All tasks including archived
~/.claude-todo/scripts/list-tasks.sh --all

# Sort by priority, highest first
~/.claude-todo/scripts/list-tasks.sh --sort priority --reverse
```

**Output Formats**:

**Text (default)**:
```
📋 Active Tasks (3)

[pending] Fix navigation bug
  ID: task-1733395200-abc123
  Priority: medium
  Created: 2025-12-05T10:00:00Z

[active] Implement authentication
  ID: task-1733395200-xyz789
  Priority: high
  Files: src/auth/jwt.ts, src/middleware/auth.ts
  Created: 2025-12-05T09:30:00Z
```

**JSON**:
```json
{
  "tasks": [
    {
      "id": "task-1733395200-xyz789",
      "title": "Implement authentication",
      "status": "active",
      "priority": "high",
      "files": ["src/auth/jwt.ts", "src/middleware/auth.ts"],
      "createdAt": "2025-12-05T09:30:00Z"
    }
  ],
  "total": 3
}
```

**Markdown**:
```markdown
## Active Tasks

- [ ] Fix navigation bug (pending)
- [x] Implement authentication (active)
- [ ] Add user dashboard (pending)
```

---

### complete-task.sh

Mark a task as complete.

```bash
~/.claude-todo/scripts/complete-task.sh <TASK_ID> [OPTIONS]
```

**Required Arguments**:
- `TASK_ID`: Task identifier

**Options**:
- `--notes <text>`: Completion notes
- `--archive`: Immediately archive after completion
- `--no-log`: Skip logging (not recommended)

**Examples**:
```bash
# Simple completion
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789

# Complete with notes
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789 \
  --notes "Implemented JWT tokens with 7-day refresh"

# Complete and archive immediately
~/.claude-todo/scripts/complete-task.sh task-1733395200-xyz789 --archive
```

**Validation**:
- Task must exist
- Task must not already be completed
- Valid status transition required (`pending`/`active`/`blocked` → `done`)

**Side Effects**:
- Updates task status to `done`
- Adds `completedAt` timestamp
- Logs completion to `todo-log.json`
- Triggers auto-archive if enabled
- Creates backup before modification

---

### archive.sh

Archive completed tasks.

```bash
~/.claude-todo/scripts/archive.sh [OPTIONS]
```

**Options**:
- `--force`: Archive all completed tasks regardless of age
- `--days <n>`: Archive tasks completed N days ago (overrides config)
- `--verbose`: Show detailed operation output
- `--dry-run`: Show what would be archived without making changes

**Examples**:
```bash
# Archive based on config (default: 7 days)
~/.claude-todo/scripts/archive.sh

# Force archive all completed tasks
~/.claude-todo/scripts/archive.sh --force

# Archive tasks older than 30 days
~/.claude-todo/scripts/archive.sh --days 30

# Preview what would be archived
~/.claude-todo/scripts/archive.sh --dry-run

# Verbose archive with details
~/.claude-todo/scripts/archive.sh --verbose
```

**Output**:
```
📦 Archiving completed tasks...

Candidates: 15 tasks
Age threshold: 7 days
Archive policy: enabled

Archiving:
  ✓ task-1733388000-abc123 (completed 8 days ago)
  ✓ task-1733390000-def456 (completed 10 days ago)
  ✓ task-1733392000-ghi789 (completed 14 days ago)

Summary:
  Archived: 3 tasks
  Remaining active: 12 tasks
  Archive size: 48 tasks

Archive location: .claude/todo-archive.json
```

**Validation**:
- Only `done` tasks archived
- Age threshold enforced unless `--force`
- Archive size limits respected
- Referential integrity maintained

---

### validate.sh

Validate all todo JSON files.

```bash
~/.claude-todo/scripts/validate.sh [OPTIONS]
```

**Options**:
- `--fix`: Attempt automatic repairs
- `--strict`: Enable strict validation mode
- `--file <path>`: Validate specific file only
- `--verbose`: Show detailed validation output

**Examples**:
```bash
# Validate all files
~/.claude-todo/scripts/validate.sh

# Validate with automatic fixes
~/.claude-todo/scripts/validate.sh --fix

# Strict mode (no warnings ignored)
~/.claude-todo/scripts/validate.sh --strict

# Validate specific file
~/.claude-todo/scripts/validate.sh --file .claude/todo.json

# Verbose validation
~/.claude-todo/scripts/validate.sh --verbose
```

**Validation Checks**:

1. **Schema Validation**:
   - JSON syntax correctness
   - Required fields present
   - Field types match schema
   - Enum values valid

2. **Anti-Hallucination Checks**:
   - ID uniqueness within file
   - ID uniqueness across todo + archive
   - Status values from allowed enum
   - Timestamp sanity (not future dates)
   - `completedAt` after `createdAt`
   - No duplicate task titles

3. **Referential Integrity**:
   - Dependencies reference valid tasks
   - Blockers reference valid tasks
   - Archive contains only `done` tasks
   - Log entries reference valid tasks

**Output**:
```
🔍 Validating todo system files...

✅ .claude/todo.json
   Schema: VALID
   Tasks: 12
   Issues: None

⚠️  .claude/todo-archive.json
   Schema: VALID
   Tasks: 48
   Warnings:
     - Task task-1733388000-old123 has no completedAt timestamp
     - Recommend: Add completion timestamp

✅ .claude/todo-config.json
   Schema: VALID
   Configuration: Valid

✅ .claude/todo-log.json
   Schema: VALID
   Entries: 156

Summary:
  Files validated: 4
  Errors: 0
  Warnings: 1

Exit code: 0 (success)
```

**Exit Codes**:
- `0`: All valid
- `1`: Schema errors
- `2`: Semantic errors
- `3`: Both schema and semantic errors

---

### stats.sh

Display task statistics and reports.

```bash
~/.claude-todo/scripts/stats.sh [OPTIONS]
```

**Options**:
- `--period <days>`: Analysis period in days (default: 30)
- `--format <format>`: Output format (`text`, `json`, `csv`)
- `--chart`: Include ASCII charts
- `--detailed`: Show detailed breakdown

**Examples**:
```bash
# Default stats (30-day period)
~/.claude-todo/scripts/stats.sh

# Last 7 days
~/.claude-todo/scripts/stats.sh --period 7

# Last 90 days with charts
~/.claude-todo/scripts/stats.sh --period 90 --chart

# Detailed statistics
~/.claude-todo/scripts/stats.sh --detailed

# JSON output for dashboards
~/.claude-todo/scripts/stats.sh --format json

# CSV export for spreadsheets
~/.claude-todo/scripts/stats.sh --format csv
```

**Output**:
```
📊 Task Statistics

Current State:
  Pending:    8 tasks
  Active:     4 tasks
  Blocked:    1 task
  Done:       12 tasks
  ───────────────────
  Total:      25 tasks

Last 30 Days:
  Created:    18 tasks
  Completed:  12 tasks
  Completion Rate: 66.7%
  Avg Time to Complete: 3.2 days

Priority Distribution:
  Critical:   2 tasks (8%)
  High:       6 tasks (24%)
  Medium:     12 tasks (48%)
  Low:        5 tasks (20%)

Label Distribution:
  backend:    10 tasks
  frontend:   8 tasks
  security:   3 tasks
  docs:       2 tasks

Archived:
  Total:      48 tasks
  Oldest:     2025-09-15
  Newest:     2025-11-28

Productivity Trends:
  Week 1:     █████████░ 9 tasks
  Week 2:     ███████░░░ 7 tasks
  Week 3:     ████████░░ 8 tasks
  Week 4:     ██████████ 10 tasks

Top Blockers:
  1. Security review pending (blocks 3 tasks)
  2. API design incomplete (blocks 2 tasks)
```

---

### backup.sh

Create backup of todo files.

```bash
~/.claude-todo/scripts/backup.sh [OPTIONS]
```

**Options**:
- `--destination <dir>`: Backup destination (default: `.claude/.backups/`)
- `--compress`: Compress backup with gzip
- `--name <name>`: Custom backup name

**Examples**:
```bash
# Default backup
~/.claude-todo/scripts/backup.sh

# Backup to custom location
~/.claude-todo/scripts/backup.sh --destination ~/backups/todo-backup

# Compressed backup
~/.claude-todo/scripts/backup.sh --compress

# Named backup
~/.claude-todo/scripts/backup.sh --name "before-major-refactor"
```

**Output**:
```
💾 Creating backup...

Backing up:
  ✓ .claude/todo.json
  ✓ .claude/todo-archive.json
  ✓ .claude/todo-config.json
  ✓ .claude/todo-log.json

Backup created:
  Location: .claude/.backups/backup-2025-12-05-100000/
  Size: 48 KB
  Files: 4

Validation: ✅ Backup integrity verified
```

---

### restore.sh

Restore todo files from backup.

```bash
~/.claude-todo/scripts/restore.sh <BACKUP_DIR> [OPTIONS]
```

**Required Arguments**:
- `BACKUP_DIR`: Path to backup directory

**Options**:
- `--force`: Skip confirmation prompt
- `--verify`: Verify backup before restore
- `--no-backup`: Don't backup current files before restore

**Examples**:
```bash
# List available backups
ls -la .claude/.backups/

# Restore from specific backup
~/.claude-todo/scripts/restore.sh .claude/.backups/backup-2025-12-05-100000/

# Verify backup before restore
~/.claude-todo/scripts/restore.sh .claude/.backups/backup-2025-12-05-100000/ --verify

# Force restore without confirmation
~/.claude-todo/scripts/restore.sh .claude/.backups/backup-2025-12-05-100000/ --force
```

**Workflow**:
1. Validates backup directory exists
2. Verifies backup file integrity
3. Backs up current files (unless `--no-backup`)
4. Copies backup files to `.claude/`
5. Validates restored files
6. Confirms success or rolls back on error

**Output**:
```
🔄 Restoring from backup...

Backup: .claude/.backups/backup-2025-12-05-100000/
Date: 2025-12-05 10:00:00

Validation: ✅ Backup files valid

Creating safety backup of current files...
  ✓ Current files backed up to: .claude/.backups/pre-restore-2025-12-05-103000/

Restoring files:
  ✓ todo.json (15 tasks)
  ✓ todo-archive.json (48 tasks)
  ✓ todo-config.json
  ✓ todo-log.json (156 entries)

Post-restore validation: ✅ All files valid

✅ Restore completed successfully
```

---

## Advanced Operations

### Batch Task Creation

Create multiple tasks from a script or file:

```bash
#!/bin/bash
# create-sprint-tasks.sh

TASKS=(
  "Design authentication UI|high|frontend,ui"
  "Implement JWT middleware|high|backend,security"
  "Add login endpoint|high|backend,api"
  "Add logout endpoint|medium|backend,api"
  "Write auth tests|medium|testing"
  "Update API documentation|low|docs"
)

for task_spec in "${TASKS[@]}"; do
  IFS='|' read -r title priority labels <<< "$task_spec"
  ~/.claude-todo/scripts/add-task.sh "$title" \
    --status pending \
    --priority "$priority" \
    --labels "$labels"
done
```

### Task Dependencies

Manage task dependencies and blockers:

```bash
# Create base task
BASE_TASK=$(~/.claude-todo/scripts/add-task.sh "Design API schema" \
  --priority high --format json | jq -r '.id')

# Create dependent task
~/.claude-todo/scripts/add-task.sh "Implement API endpoints" \
  --depends "$BASE_TASK" \
  --status pending \
  --notes "Blocked until API schema is finalized"

# Create blocker-aware task
~/.claude-todo/scripts/add-task.sh "Deploy to staging" \
  --blocked-by "$BASE_TASK" \
  --status blocked
```

### Bulk Status Updates

Update multiple task statuses:

```bash
#!/bin/bash
# start-sprint.sh - Mark all pending tasks as active

PENDING_TASKS=$(~/.claude-todo/scripts/list-tasks.sh --status pending --format json | \
  jq -r '.tasks[].id')

for task_id in $PENDING_TASKS; do
  # Update status to active
  # Note: Would need update-task.sh script (extension point)
  echo "Activating: $task_id"
done
```

### Export Tasks

Export tasks to external formats:

```bash
# Export to CSV
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq -r '.tasks[] | [.id, .title, .status, .priority] | @csv' > tasks.csv

# Export to GitHub Issues format
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq '.tasks[] | "## \(.title)\n\n\(.description // "")\n\nPriority: \(.priority)\nLabels: \(.labels | join(", "))"'

# Export pending tasks to Markdown checklist
~/.claude-todo/scripts/list-tasks.sh --status pending --format markdown > TODO.md
```

### Archive Management

Manage archive file size:

```bash
# Check archive size
wc -l .claude/todo-archive.json

# Archive old tasks more aggressively
~/.claude-todo/scripts/archive.sh --days 3 --force

# Extract specific archived task
cat .claude/todo-archive.json | jq '.tasks[] | select(.id == "task-1733388000-abc123")'

# List all archived tasks from specific date
cat .claude/todo-archive.json | \
  jq '.tasks[] | select(.completedAt | startswith("2025-11"))'
```

### Log Analysis

Analyze change log for insights:

```bash
# Count operations by type
cat .claude/todo-log.json | jq '[.entries[] | .operation] | group_by(.) | map({key: .[0], count: length}) | from_entries'

# Find tasks with most changes
cat .claude/todo-log.json | jq '[.entries[] | .task_id] | group_by(.) | map({task: .[0], changes: length}) | sort_by(.changes) | reverse | .[0:5]'

# Tasks completed in last 7 days
SEVEN_DAYS_AGO=$(date -d '7 days ago' -Iseconds)
cat .claude/todo-log.json | \
  jq --arg since "$SEVEN_DAYS_AGO" '.entries[] | select(.operation == "complete" and .timestamp > $since)'
```

---

## CLAUDE.md Integration

### Overview

The claude-todo system integrates with Claude Code through `.claude/CLAUDE.md` for automated task management during development sessions.

### Session Workflow

#### 1. Session Initialization

```markdown
<!-- .claude/CLAUDE.md -->

# Project Instructions for Claude Code

## Current Tasks

<!-- CLAUDE-TODO-START -->
Run: ~/.claude-todo/scripts/list-tasks.sh --status pending --format markdown
<!-- CLAUDE-TODO-END -->

## Active Sprint

Priority tasks for this session:
- Implement authentication
- Add user dashboard
- Fix navigation bug
```

#### 2. During Development

Claude Code can:
- Create tasks: `~/.claude-todo/scripts/add-task.sh "New task"`
- Complete tasks: `~/.claude-todo/scripts/complete-task.sh <id>`
- List tasks: `~/.claude-todo/scripts/list-tasks.sh`
- Check stats: `~/.claude-todo/scripts/stats.sh`

#### 3. Session End

```bash
# Archive completed tasks
~/.claude-todo/scripts/archive.sh

# Create session backup
~/.claude-todo/scripts/backup.sh --name "session-2025-12-05"

# Review statistics
~/.claude-todo/scripts/stats.sh --period 1
```

### Automated Task Tracking

#### TodoWrite Integration

When Claude Code uses `TodoWrite` tool:

```typescript
// Claude Code creates internal todos
TodoWrite([
  { content: "Implement JWT middleware", status: "pending", activeForm: "Implementing JWT middleware" },
  { content: "Add login endpoint", status: "pending", activeForm: "Adding login endpoint" }
])

// Automatically sync to claude-todo system
~/.claude-todo/scripts/add-task.sh "Implement JWT middleware" --status pending
~/.claude-todo/scripts/add-task.sh "Add login endpoint" --status pending
```

#### Task Completion Automation

```bash
# When Claude Code marks internal todo complete
# Trigger: TodoWrite status change to "completed"

~/.claude-todo/scripts/complete-task.sh <task-id> \
  --notes "Completed by Claude Code in session xyz"
```

### Best Practices

1. **Session Start**:
   - List active tasks: `~/.claude-todo/scripts/list-tasks.sh`
   - Review high-priority items
   - Understand dependencies

2. **During Session**:
   - Create tasks for new work discovered
   - Complete tasks as work finishes
   - Add notes for context

3. **Session End**:
   - Archive completed tasks
   - Update blocked tasks
   - Create backup

4. **Cross-Session**:
   - Reference task IDs in commits
   - Link tasks to PRs
   - Maintain audit trail

---

## Filtering and Searching

### Status-Based Filtering

```bash
# All pending work
~/.claude-todo/scripts/list-tasks.sh --status pending

# Currently active tasks
~/.claude-todo/scripts/list-tasks.sh --status active

# Blocked tasks requiring attention
~/.claude-todo/scripts/list-tasks.sh --status blocked

# Recently completed
~/.claude-todo/scripts/list-tasks.sh --status done --limit 10
```

### Priority Filtering

```bash
# Critical tasks only
~/.claude-todo/scripts/list-tasks.sh --priority critical

# High + Critical
~/.claude-todo/scripts/list-tasks.sh --priority high,critical

# Non-urgent work
~/.claude-todo/scripts/list-tasks.sh --priority low,medium
```

### Label-Based Filtering

```bash
# All backend tasks
~/.claude-todo/scripts/list-tasks.sh --label backend

# Security-related work
~/.claude-todo/scripts/list-tasks.sh --label security

# Frontend UI tasks
~/.claude-todo/scripts/list-tasks.sh --label frontend --label ui
```

### Date-Based Filtering

```bash
# Tasks from last week
~/.claude-todo/scripts/list-tasks.sh --since 2025-11-28

# Tasks from specific date range
~/.claude-todo/scripts/list-tasks.sh \
  --since 2025-11-01 \
  --until 2025-11-30

# Today's tasks
~/.claude-todo/scripts/list-tasks.sh --since $(date -Idate)
```

### Complex Queries

```bash
# High-priority backend tasks
~/.claude-todo/scripts/list-tasks.sh \
  --priority high \
  --label backend \
  --status pending

# Blocked critical tasks
~/.claude-todo/scripts/list-tasks.sh \
  --status blocked \
  --priority critical \
  --format json

# Recent active work
~/.claude-todo/scripts/list-tasks.sh \
  --status active \
  --since 2025-12-01 \
  --sort createdAt \
  --reverse
```

### Using jq for Advanced Filtering

```bash
# Tasks with specific files
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq '.tasks[] | select(.files | map(contains("auth")) | any)'

# Tasks with acceptance criteria
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq '.tasks[] | select(.acceptance | length > 0)'

# Tasks with dependencies
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq '.tasks[] | select(.depends | length > 0)'

# Long-running active tasks (>7 days)
~/.claude-todo/scripts/list-tasks.sh --status active --format json | \
  jq --arg date "$(date -d '7 days ago' -Iseconds)" \
    '.tasks[] | select(.createdAt < $date)'
```

---

## Configuration

### Configuration File Location

`.claude/todo-config.json` (per-project)

### Configuration Options

```json
{
  "$schema": "../schemas/config.schema.json",
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

### Configuration Fields

#### Archive Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable archive functionality |
| `archive_after_days` | number | `7` | Days before archiving completed tasks |
| `max_archive_size` | number | `1000` | Max tasks in archive (0 = unlimited) |
| `auto_archive_on_complete` | boolean | `false` | Auto-archive on task completion |

#### Validation Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `strict_mode` | boolean | `true` | Enable strict validation |
| `allow_duplicates` | boolean | `false` | Allow duplicate task titles |
| `require_active_form` | boolean | `true` | Require activeForm field (legacy) |

#### Logging Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable change logging |
| `log_level` | string | `"info"` | Log verbosity (`debug`, `info`, `warn`, `error`) |
| `max_log_entries` | number | `10000` | Max log entries before rotation |

#### Backup Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable automatic backups |
| `max_backups` | number | `10` | Max backup files to retain |
| `backup_on_write` | boolean | `true` | Backup before every write |

#### Display Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `date_format` | string | `"iso"` | Date format (`iso`, `relative`, `short`) |
| `timezone` | string | `"local"` | Timezone for display |
| `colors_enabled` | boolean | `true` | Enable colored output |

### Environment Variables

Override config with environment variables:

```bash
# Archive settings
export CLAUDE_TODO_ARCHIVE_DAYS=14
export CLAUDE_TODO_MAX_ARCHIVE_SIZE=5000

# Validation
export CLAUDE_TODO_STRICT_MODE=false
export CLAUDE_TODO_ALLOW_DUPLICATES=true

# Display
export CLAUDE_TODO_COLORS=false
export CLAUDE_TODO_DATE_FORMAT=relative

# Run command with overrides
~/.claude-todo/scripts/list-tasks.sh
```

---

## Examples and Recipes

### Example 1: Sprint Planning

```bash
#!/bin/bash
# sprint-setup.sh - Initialize new sprint tasks

SPRINT_LABEL="sprint-12"

# Authentication tasks
~/.claude-todo/scripts/add-task.sh "Design authentication UI" \
  --priority high \
  --labels "frontend,ui,$SPRINT_LABEL" \
  --acceptance "Mockups approved,Responsive design,Accessibility compliant"

AUTH_API=$(~/.claude-todo/scripts/add-task.sh "Implement auth API" \
  --priority high \
  --labels "backend,api,$SPRINT_LABEL" \
  --format json | jq -r '.id')

~/.claude-todo/scripts/add-task.sh "Integrate auth UI with API" \
  --depends "$AUTH_API" \
  --priority high \
  --labels "frontend,integration,$SPRINT_LABEL"

~/.claude-todo/scripts/add-task.sh "Write auth tests" \
  --priority medium \
  --labels "testing,$SPRINT_LABEL" \
  --description "Unit tests for API + E2E tests for UI flow"

# List sprint tasks
~/.claude-todo/scripts/list-tasks.sh --label "$SPRINT_LABEL" --format markdown > SPRINT.md
```

### Example 2: Bug Triage Workflow

```bash
#!/bin/bash
# triage-bugs.sh - Process bug reports

# Create bug tracking tasks
for bug_id in BUG-101 BUG-102 BUG-103; do
  ~/.claude-todo/scripts/add-task.sh "Investigate $bug_id" \
    --status pending \
    --priority high \
    --labels "bug,investigation" \
    --description "Root cause analysis for $bug_id" \
    --notes "Reported by QA team on 2025-12-05"
done

# List all bugs
~/.claude-todo/scripts/list-tasks.sh --label bug --format table
```

### Example 3: Daily Standup Report

```bash
#!/bin/bash
# standup-report.sh - Generate daily standup summary

echo "# Daily Standup - $(date -Idate)"
echo ""

echo "## Yesterday (Completed)"
~/.claude-todo/scripts/list-tasks.sh \
  --status done \
  --since $(date -d '1 day ago' -Idate) \
  --format markdown

echo ""
echo "## Today (In Progress)"
~/.claude-todo/scripts/list-tasks.sh \
  --status active \
  --format markdown

echo ""
echo "## Blockers"
~/.claude-todo/scripts/list-tasks.sh \
  --status blocked \
  --format markdown

echo ""
echo "## Statistics"
~/.claude-todo/scripts/stats.sh --period 7
```

### Example 4: Release Preparation

```bash
#!/bin/bash
# prepare-release.sh - Pre-release checklist

RELEASE_VERSION="v2.0.0"

# Create release tasks
TASKS=(
  "Update version numbers|critical|release"
  "Run full test suite|critical|testing,release"
  "Update CHANGELOG.md|high|docs,release"
  "Create release notes|high|docs,release"
  "Tag release in git|high|release"
  "Build production artifacts|critical|build,release"
  "Deploy to staging|high|deployment,release"
  "QA approval|critical|qa,release"
  "Deploy to production|critical|deployment,release"
  "Post-release monitoring|medium|ops,release"
)

echo "Creating release tasks for $RELEASE_VERSION..."

for task_spec in "${TASKS[@]}"; do
  IFS='|' read -r title priority labels <<< "$task_spec"
  ~/.claude-todo/scripts/add-task.sh "$title" \
    --status pending \
    --priority "$priority" \
    --labels "$labels,$RELEASE_VERSION"
done

# Generate release checklist
~/.claude-todo/scripts/list-tasks.sh \
  --label "$RELEASE_VERSION" \
  --sort priority \
  --reverse \
  --format markdown > "RELEASE-$RELEASE_VERSION.md"

echo "Release checklist created: RELEASE-$RELEASE_VERSION.md"
```

### Example 5: End-of-Sprint Cleanup

```bash
#!/bin/bash
# sprint-cleanup.sh - Clean up after sprint completion

SPRINT_LABEL="sprint-12"

echo "Sprint $SPRINT_LABEL Cleanup"
echo "=============================="

# Archive completed tasks
echo "Archiving completed tasks..."
~/.claude-todo/scripts/archive.sh --force

# Report incomplete tasks
echo ""
echo "Incomplete Sprint Tasks:"
~/.claude-todo/scripts/list-tasks.sh \
  --label "$SPRINT_LABEL" \
  --status pending,active,blocked \
  --format markdown

# Generate sprint statistics
echo ""
echo "Sprint Statistics:"
~/.claude-todo/scripts/stats.sh --period 14

# Create sprint backup
echo ""
echo "Creating backup..."
~/.claude-todo/scripts/backup.sh --name "sprint-$SPRINT_LABEL-end"

echo ""
echo "Cleanup complete!"
```

### Example 6: Task Dependency Graph

```bash
#!/bin/bash
# dependency-graph.sh - Visualize task dependencies

# Extract tasks with dependencies
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq -r '.tasks[] | select(.depends | length > 0) |
         "\(.title) depends on: \(.depends | join(", "))"'

# Generate DOT graph format
echo "digraph tasks {"
~/.claude-todo/scripts/list-tasks.sh --format json | \
  jq -r '.tasks[] | select(.depends | length > 0) |
         .depends[] as $dep | "  \"\($dep)\" -> \"\(.id)\";"'
echo "}"
```

---

## Troubleshooting

### Common Issues

**Issue**: Validation errors after manual JSON edits

**Solution**:
```bash
# Validate and attempt automatic fixes
~/.claude-todo/scripts/validate.sh --fix

# If automatic fix fails, restore from backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

**Issue**: Task not found by ID

**Solution**:
```bash
# Check if task was archived
~/.claude-todo/scripts/list-tasks.sh --all | grep <task-id>

# Search in archive file directly
cat .claude/todo-archive.json | jq '.tasks[] | select(.id == "<task-id>")'
```

**Issue**: Archive not working

**Solution**:
```bash
# Check archive configuration
cat .claude/todo-config.json | jq '.archive'

# Force archive with verbose output
~/.claude-todo/scripts/archive.sh --force --verbose
```

**Issue**: Backup restoration failed

**Solution**:
```bash
# Verify backup integrity first
~/.claude-todo/scripts/validate.sh --file .claude/.backups/todo.json.1

# List all available backups
ls -lah .claude/.backups/

# Restore from specific backup
~/.claude-todo/scripts/restore.sh .claude/.backups/backup-2025-12-05-100000/
```

---

## Next Steps

- **Configuration**: See [configuration.md](configuration.md) for detailed config options
- **Schema Reference**: See [schema-reference.md](schema-reference.md) for complete data structure
- **Troubleshooting**: See [troubleshooting.md](troubleshooting.md) for common issues
- **Installation**: See [installation.md](installation.md) for setup details

---

## Quick Reference Card

```
# Essential Commands
init.sh              # Initialize project
add-task.sh "title"  # Create task
list-tasks.sh        # Show tasks
complete-task.sh ID  # Mark complete
archive.sh           # Archive old tasks
validate.sh          # Check integrity
stats.sh             # View statistics
backup.sh            # Create backup
restore.sh DIR       # Restore backup

# Common Filters
--status pending     # Pending tasks only
--priority high      # High priority
--label backend      # Backend tasks
--since 2025-12-01   # Recent tasks
--format json        # JSON output

# Status Values
pending, active, blocked, done

# Priority Values
low, medium, high, critical
```
