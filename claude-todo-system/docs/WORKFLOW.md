# CLAUDE-TODO Workflow Guide

## Task Lifecycle

### 1. Creating Tasks

```json
{
  "id": "T001",
  "title": "Implement user authentication",
  "status": "pending",
  "priority": "high",
  "phase": "core",
  "description": "Add JWT-based authentication...",
  "acceptance": [
    "Login endpoint returns JWT",
    "Protected routes require valid token",
    "Token refresh works correctly"
  ],
  "depends": [],
  "files": ["src/auth/"],
  "labels": ["feature", "security"],
  "createdAt": "2025-12-05T10:00:00Z"
}
```

**Rules:**
- ID format: `T` + 3+ digits (T001, T002, T100)
- Start title with verb: "Implement", "Fix", "Add"
- Include testable acceptance criteria for high/critical tasks
- Set appropriate priority and phase

### 2. Starting Work

```bash
# Before starting, validate
validate-todo.sh

# Update todo.json
# Set status: "active"
# Set focus.currentTask: "T001"
```

**Pre-activation checks:**
- All tasks in `depends[]` must be `done`
- No other task is `active`
- Checksum is valid

### 3. During Work

- Append to `notes[]` with progress/decisions
- Update `files[]` as you modify code
- If blocked: immediately set `status: "blocked"` and `blockedBy`

```json
{
  "status": "blocked",
  "blockedBy": "Waiting for API credentials from DevOps",
  "notes": [
    "2025-12-05: Started implementation",
    "2025-12-05: Blocked - need API key"
  ]
}
```

### 4. Completing Tasks

```json
{
  "status": "done",
  "completedAt": "2025-12-05T14:00:00Z",
  "notes": [
    "2025-12-05: Started implementation",
    "2025-12-05: All acceptance criteria met"
  ]
}
```

**Also update:**
- Clear `focus.currentTask` (set to null)
- Update `focus.sessionNote` with completion summary
- Recalculate checksum

### 5. Archiving

Tasks are archived automatically when:
- `status: "done"` for longer than `config.archive.daysUntilArchive`
- OR total done tasks > `config.archive.maxCompletedTasks`

Manual archive:
```bash
archive-todo.sh --dry-run  # Preview
archive-todo.sh            # Execute
```

## Session Protocol

### Starting a Session

```
1. Read todo-config.json
2. Read todo.json
3. Verify _meta.checksum
4. Generate session ID: session_YYYYMMDD_HHMMSS_<random>
5. Set _meta.activeSession
6. Log session_start
7. Check focus.currentTask
   - If set: Resume that task
   - If null: Find highest priority actionable pending task
```

### Ending a Session

```
1. Update focus.sessionNote (describe current state)
2. Set focus.nextAction (specific next step)
3. Recalculate and update _meta.checksum
4. Check if archive needed (config.archive.archiveOnSessionEnd)
5. Log session_end
6. Set _meta.activeSession = null
```

## Dependency Management

### Simple Dependencies

```json
{
  "id": "T002",
  "title": "Build login UI",
  "depends": ["T001"],
  "status": "pending"
}
```

T002 can only become `active` when T001 is `done`.

### Dependency Validation

```bash
# Check for issues
validate-todo.sh

# Output includes:
# - Missing dependency references
# - Circular dependencies
# - Orphaned dependencies
```

### Circular Dependency Prevention

```json
// INVALID - will be rejected
{"id": "T001", "depends": ["T002"]},
{"id": "T002", "depends": ["T001"]}
```

## Focus Management

The `focus` object tracks session state:

```json
{
  "focus": {
    "currentTask": "T003",
    "blockedUntil": null,
    "sessionNote": "Implementing JWT validation, middleware complete",
    "nextAction": "Add token refresh endpoint"
  }
}
```

**Rules:**
- `currentTask` MUST match the only task with `status: "active"`
- Update `sessionNote` before ending every session
- Set `nextAction` for clear resumption

## Checksum Protocol

### Calculate

```bash
# Tasks array → JSON → SHA-256 → First 16 chars
jq -c '.tasks' todo.json | sha256sum | cut -c1-16
```

### Verify

```bash
STORED=$(jq -r '._meta.checksum' todo.json)
COMPUTED=$(jq -c '.tasks' todo.json | sha256sum | cut -c1-16)

if [[ "$STORED" != "$COMPUTED" ]]; then
  echo "CHECKSUM MISMATCH - possible corruption"
fi
```

### Update

After ANY modification to tasks array:
1. Recalculate checksum
2. Update `_meta.checksum`
3. Update `lastUpdated`

## Logging

All operations should be logged:

```bash
# Task created
log-todo.sh --action task_created --task-id T005 --after '{"title":"New task"}'

# Status change
log-todo.sh --action status_changed --task-id T001 \
  --before '{"status":"pending"}' \
  --after '{"status":"active"}'

# Session events
log-todo.sh --action session_start --session-id "session_20251205_..."
log-todo.sh --action session_end --session-id "session_20251205_..."
```

## Validation

Run validation regularly:

```bash
# Standard validation
validate-todo.sh

# Strict mode (warnings are errors)
validate-todo.sh --strict

# Auto-fix simple issues
validate-todo.sh --fix
```

**Checks performed:**
- JSON syntax
- Single active task
- Dependencies exist
- No circular dependencies
- blocked has blockedBy
- done has completedAt
- focus matches active task
- Checksum integrity
