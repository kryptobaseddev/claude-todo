# Log Viewing Commands

The `claude-todo log` command provides subcommands for viewing and analyzing log entries.

## Commands

### `log list` - List Log Entries

List log entries with filtering and formatting options.

```bash
claude-todo log list [OPTIONS]
```

**Options:**

- `--limit N` - Show last N entries (default: 20, 0 = all)
- `--action ACTION` - Filter by action type
- `--task-id ID` - Filter by task ID
- `--actor ACTOR` - Filter by actor (human|claude|system)
- `--since DATE` - Show entries since date (YYYY-MM-DD)
- `--format FORMAT` - Output format: text|json (default: text)

**Examples:**

```bash
# Last 20 entries (default)
claude-todo log list

# Last 50 entries
claude-todo log list --limit 50

# All entries
claude-todo log list --limit 0

# Filter by action type
claude-todo log list --action task_created
claude-todo log list --action status_changed

# Filter by task
claude-todo log list --task-id T001

# Filter by actor
claude-todo log list --actor system
claude-todo log list --actor claude

# Filter by date
claude-todo log list --since "2025-12-13"

# JSON output
claude-todo log list --format json

# Combined filters
claude-todo log list --action task_created --since "2025-12-13" --limit 10
```

**Text Output Format:**

```
[2025-12-14 00:27:34] session_end - (no task) by system
[2025-12-14 00:34:51] task_created - T182 by system
  title: "Enhance dashboard to show archived tasks"
  details: {"title":"Enhance dashboard...","status":"pending","priority":"medium"}
```

**JSON Output Format:**

```json
[
  {
    "id": "log_abc123",
    "timestamp": "2025-12-14T00:27:34Z",
    "sessionId": "session_20251213_162436_1e8640",
    "action": "session_end",
    "actor": "system",
    "taskId": null,
    "before": null,
    "after": null,
    "details": null
  }
]
```

### `log show` - Show Log Entry Details

Display detailed information about a specific log entry.

```bash
claude-todo log show <log-id>
```

**Examples:**

```bash
# Show specific log entry
claude-todo log show log_abc123

# Find and show recent task creation
LOG_ID=$(claude-todo log list --action task_created --format json | jq -r '.[0].id')
claude-todo log show $LOG_ID
```

**Output Format:**

```
Log Entry: log_0522c2e2b2a9
Timestamp:  2025-12-13 08:08:21
Action:     status_changed
Actor:      system
Task ID:    T058

Before:
{"status":"pending","completedAt":null}

After:
{"status":"done","completedAt":"2025-12-13T08:08:21Z"}

Details:
{"field":"status","operation":"complete"}
```

## Action Types

Valid action types for filtering:

- `session_start` - Session initiated
- `session_end` - Session terminated
- `task_created` - New task added
- `task_updated` - Task modified
- `status_changed` - Task status changed
- `task_archived` - Task moved to archive
- `focus_changed` - Focus changed to different task
- `config_changed` - Configuration modified
- `validation_run` - Validation executed
- `checksum_updated` - Checksum recalculated
- `error_occurred` - Error logged
- `system_initialized` - System initialized for project

## Common Workflows

### Audit Task History

View all changes to a specific task:

```bash
claude-todo log list --task-id T001 --limit 0
```

### Session Review

View all actions in a specific session:

```bash
# Get session ID from todo.json
SESSION_ID=$(jq -r '._meta.activeSession // ._meta.lastSession' .claude/todo.json)

# Filter log by session (requires jq)
claude-todo log list --format json | jq --arg sid "$SESSION_ID" '.[] | select(.sessionId == $sid)'
```

### Daily Activity Report

View all activity for a specific day:

```bash
claude-todo log list --since "2025-12-13" --limit 0
```

### Task Creation Timeline

View when tasks were created:

```bash
claude-todo log list --action task_created --limit 0
```

### Debug Status Changes

Find status change entries with before/after state:

```bash
claude-todo log list --action status_changed --format json | \
  jq '.[] | select(.before != null and .after != null)'
```

## Integration with Other Commands

### Export to CSV

```bash
claude-todo log list --format json | \
  jq -r '.[] | [.timestamp, .action, .taskId // "", .actor] | @csv' > log.csv
```

### Count Actions by Type

```bash
claude-todo log list --limit 0 --format json | \
  jq -r '.[].action' | sort | uniq -c | sort -rn
```

### Find Recent Errors

```bash
claude-todo log list --action error_occurred --limit 10
```

## See Also

- [Task Management](../usage.md)
- [Session Management](./session.md)
- [Log Schema](../architecture/log-schema.md)
