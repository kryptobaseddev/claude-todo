<!-- CLAUDE-TODO:START -->
## Task Management System

Tasks tracked in `.claude/todo.json` with auto-archive to `.claude/todo-archive.json`, config in `.claude/todo-config.json`, and history in `.claude/todo-log.json`.

### Session Protocol

**START** (MANDATORY):
1. Read `.claude/todo-config.json` for settings
2. Read `.claude/todo.json` - verify `_meta.checksum` matches
3. If checksum fails: **STOP** - report corruption
4. Generate session ID: `session_YYYYMMDD_HHMMSS_<6hex>`
5. Log `session_start` to `.claude/todo-log.json`
6. Set `_meta.activeSession` = session ID
7. Check `focus.currentTask` → resume or find next actionable

**WORK**:
- **ONE active task only** - set `status: "active"` + `focus.currentTask`
- Append to `notes[]` (NEVER delete)
- Update `files[]` as you modify code
- If blocked: `status: "blocked"` + `blockedBy` reason immediately
- Log all status changes to `.claude/todo-log.json`

**END** (MANDATORY):
1. Update `focus.sessionNote` with current state
2. Set `focus.nextAction` with specific next step
3. If task done: `status: "done"` + `completedAt` + clear `focus.currentTask`
4. Recalculate and update `_meta.checksum`
5. Run archive check if `config.archive.archiveOnSessionEnd`
6. Log `session_end` to `.claude/todo-log.json`
7. Set `_meta.activeSession` = null

### Anti-Hallucination Rules

**CRITICAL - NEVER VIOLATE:**
- **ALWAYS** read before write - verify checksum
- **NEVER** assume task state - verify in file
- **NEVER** have 2+ active tasks
- **NEVER** modify archived tasks (immutable)
- **NEVER** skip checksum update after changes
- **ALWAYS** log changes to `.claude/todo-log.json`

**CHECKSUM PROTOCOL:**
```
1. Read .claude/todo.json
2. Extract _meta.checksum
3. Calculate SHA-256 of tasks array (truncate to 16 chars)
4. If mismatch: STOP → Report "Checksum mismatch" → Await fix
5. Only proceed if checksums match
```

**FOCUS ENFORCEMENT:**
- `focus.currentTask` MUST equal the only task with `status="active"`
- Before activating: verify NO other tasks are active
- If mismatch detected: reconcile (prefer focus as truth)

### Dependency Rules

Before setting `status: "active"`:
1. Check `depends[]` array
2. ALL referenced tasks must have `status: "done"`
3. If ANY dependency incomplete: **BLOCK** activation
4. Circular dependencies: **ERROR** - show cycle path

### Status Lifecycle
```
pending → active → done → (archived)
           ↓
        blocked → pending
```

**Valid transitions:**
- `pending` → `active` (if deps met, no other active)
- `pending` → `blocked`
- `active` → `done`
- `active` → `blocked`
- `blocked` → `pending` (when resolved)

**Invalid (ERROR):**
- `done` → anything (immutable)
- `pending` → `done` (must pass through active)

### Error Recovery

| Error | Action |
|-------|--------|
| Checksum mismatch | Re-read file, DO NOT overwrite |
| Multiple active | Run `validate.sh --fix` (from project root) |
| Invalid focus | Reconcile to active task |
| Missing blockedBy | Add reason or change status |
| Orphaned deps | Remove invalid references |

### Quick Commands
```bash
validate.sh           # Validate .claude/todo.json
validate.sh --fix     # Auto-fix simple issues
archive.sh            # Run archive check
archive.sh --dry-run  # Preview archive
log.sh --action X     # Add log entry
```

### File Summary
| File | Purpose | Modify? |
|------|---------|---------|
| `.claude/todo.json` | Active tasks | Yes |
| `.claude/todo-archive.json` | Completed tasks | Append only |
| `.claude/todo-config.json` | Settings | Rarely |
| `.claude/todo-log.json` | Change history | Append only |
<!-- CLAUDE-TODO:END -->
