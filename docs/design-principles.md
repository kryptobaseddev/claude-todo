# CLAUDE-TODO Design Principles

## Core Philosophy

CLAUDE-TODO is built on three foundational pillars designed specifically for AI-assisted development:

### 1. Anti-Hallucination First
Multi-layer validation prevents AI-generated errors from corrupting task data. Every operation undergoes schema enforcement, semantic validation, and cross-file integrity checks to ensure data remains accurate and consistent.

**Why**: AI agents can generate syntactically valid but semantically incorrect data. Protection against hallucination is not optional—it's the foundation.

### 2. Atomic Operations
Every file modification uses atomic write patterns. No partial writes, no data corruption, full rollback on any failure.

**Why**: Task data is the source of truth for work sessions. Corruption destroys continuity. Atomic operations ensure all-or-nothing modifications.

### 3. Session Continuity
Complete audit trails, immutable change logs, and automatic backups enable seamless work across interrupted sessions.

**Why**: Development work is rarely linear. Session continuity means you can pick up exactly where you left off with full context preserved.

---

## Design Principles

### 1. Single Source of Truth
`todo.json` is authoritative for active tasks. All queries, updates, and reports derive from this file.

**Why**: Multiple sources of truth lead to inconsistency. One canonical file eliminates conflicts and simplifies reasoning about state.

**Implementation**:
- `todo.json`: Active tasks only
- `todo-archive.json`: Completed tasks (immutable after archiving)
- `todo-log.json`: Audit trail (append-only, never modified)
- `todo-config.json`: Behavior settings (rarely changed)

### 2. Immutable History
The change log is append-only. Operations are logged, never modified or deleted.

**Why**: Audit trails must be trustworthy. Append-only logs prevent tampering and provide complete historical context for debugging.

**Implementation**:
- Every operation logs: timestamp, operation type, task ID, before/after state
- Log entries never deleted (rotation handled by archiving old files)
- Recovery procedures rely on log integrity

### 3. Fail-Safe Operations
Every write operation follows the atomic pattern: temp file → validate → backup → rename.

**Why**: File system failures, validation errors, and interruptions happen. The atomic pattern ensures partial writes never occur.

**Pattern**:
```
1. Write to temporary file (.todo.json.tmp)
2. Validate temp file (schema + semantic)
3. IF INVALID: Delete temp → abort → error
4. IF VALID:
   a. Backup current file (.backups/todo.json.N)
   b. Atomic rename (OS-level guarantee)
   c. Rollback on rename failure
   d. Rotate old backups
```

### 4. Schema-First Validation
JSON Schema defines structure before any code validates behavior.

**Why**: Schema provides a contract. Code can change, but schema changes are explicit versioned decisions.

**Layers**:
1. **JSON Syntax**: Valid JSON structure
2. **Schema**: Types, required fields, enums, formats
3. **Semantic**: Anti-hallucination checks (ID uniqueness, timestamp sanity, field pairing)
4. **Cross-File**: Referential integrity across todo/archive/log

### 5. Idempotent Scripts
Running a script multiple times produces the same result as running it once.

**Why**: Automation and error recovery require safe retries. Idempotent operations eliminate "already processed" errors.

**Examples**:
- `init.sh`: Safe to re-run, only creates missing files
- `archive.sh`: Safe to re-run, archives same tasks once
- `validate.sh`: Safe to re-run, reports same issues

### 6. Zero-Config Defaults
Sensible defaults enable immediate use without configuration.

**Why**: Reduces friction to adoption. Users customize only what they need, not everything.

**Defaults**:
- Archive after 7 days
- Keep 10 backups
- Strict validation mode
- Backup on every write
- ISO 8601 timestamps

---

## Anti-Hallucination Mechanisms

### Layer 1: JSON Schema Enforcement

**Purpose**: Structural correctness

**Checks**:
- Required fields present (id, status, title, description, createdAt)
- Correct types (strings, booleans, timestamps)
- Enum constraints (status: pending | active | blocked | done)
- Format validation (ISO 8601 timestamps, ID format)

**Why**: AI can generate structurally invalid JSON. Schema catches this immediately.

### Layer 2: Semantic Validation

**Purpose**: Logical correctness

**Checks**:
- **ID Uniqueness**: No duplicate IDs within file or across todo + archive
- **Timestamp Sanity**: `createdAt` not in future, `completedAt` after `createdAt`
- **Field Requirements**: Both `title` AND `description` required (different values)
- **Duplicate Detection**: Warn on identical task descriptions
- **Status Transitions**: Only valid transitions (pending/active/blocked → done)

**Why**: Structurally valid JSON can still be semantically incorrect. AI can duplicate IDs, create future timestamps, or violate business rules.

### Layer 3: Cross-File Integrity

**Purpose**: Relational correctness

**Checks**:
- Log entries reference valid task IDs
- Archived tasks exist in archive file
- No task loss during archival (count before/after matches)
- Dependencies reference existing tasks

**Why**: Multi-file systems have referential integrity requirements. Orphaned references break audit trails and dependencies.

### Layer 4: Configuration Validation

**Purpose**: Policy correctness

**Checks**:
- Archive retention period is positive integer
- Max archive size is non-negative
- Related settings are compatible (e.g., auto-archive requires archive enabled)

**Why**: Invalid configuration causes runtime failures. Validation at config load prevents cascading errors.

---

## System Invariants

These properties must ALWAYS be true:

1. **ID Uniqueness**: Every task ID is globally unique (across todo.json + todo-archive.json)
2. **Status Enum**: Task status is always one of: pending | active | blocked | done
3. **Atomic Writes**: No partial writes to any JSON file
4. **Backup Exists**: Before any modification, previous version is backed up
5. **Log Append-Only**: Change log is never modified, only appended
6. **Archive Immutability**: Archive file is never modified after creation (only appended)
7. **Schema Validation**: Every file passes schema validation before being used
8. **Timestamp Monotonicity**: Task timestamps are chronological (created ≤ completed)

**Enforcement**: Validation runs on every read and write. Scripts exit with error if invariants violated.

---

## Architectural Decisions

### Why Bash Scripts?

**Decision**: Implement core system in Bash with jq for JSON manipulation

**Rationale**:
- Universal availability on Unix systems (no installation required)
- Simple, transparent operations (users can read scripts)
- Easy integration with shell workflows
- No runtime dependencies beyond jq

**Trade-offs**:
- Performance ceiling lower than compiled languages
- Acceptable for 1000+ tasks (< 500ms operations)
- Complexity threshold requires refactor to Python/Go beyond 10K tasks

### Why JSON Schema?

**Decision**: Use JSON Schema for validation instead of custom validation code

**Rationale**:
- Declarative validation (separate from implementation)
- Versioned contracts (schema version tracks data format)
- Tooling support (multiple validators available)
- Self-documenting (schema explains structure)

**Trade-offs**:
- Requires external validator (ajv or jsonschema)
- Fallback to jq-based validation if unavailable

### Why Atomic Rename?

**Decision**: Use temp file + atomic rename pattern for all writes

**Rationale**:
- OS-level atomicity guarantee (POSIX rename)
- No partial writes possible
- Crash-safe (interrupted write leaves temp file, original unchanged)
- Enables rollback on validation failure

**Trade-offs**:
- Slower than direct writes (temp → validate → rename)
- Acceptable overhead (< 50ms) for safety

### Why Append-Only Log?

**Decision**: Change log is append-only, never modified

**Rationale**:
- Tamper-evident audit trail
- Simplifies concurrent writes (append vs modify)
- Supports forensic debugging
- Enables time-travel queries

**Trade-offs**:
- Log grows indefinitely (mitigated by rotation)
- Rotation handled by archiving old log files

### Why Separate Archive File?

**Decision**: Completed tasks move to `todo-archive.json`

**Rationale**:
- Active task list stays small (fast operations)
- Archive is immutable (can optimize for read-only access)
- Separate retention policies (archive compressed long-term)
- Clearer separation of concerns (active vs historical)

**Trade-offs**:
- Cross-file queries more complex
- Requires careful handling during archival to prevent data loss

### Why Auto-Derived activeForm?

**Decision**: Generate `activeForm` from task `title` during TodoWrite export rather than storing it

**Context**: Claude Code's TodoWrite tool uses two fields:
- `content`: The imperative task description ("Fix authentication bug")
- `activeForm`: Present continuous form shown during execution ("Fixing authentication bug")

**Rationale**:
- **Single source of truth**: Users write `title` once; `activeForm` derived on export
- **Grammar transformation**: Automatic verb conjugation (Fix→Fixing, Add→Adding, Implement→Implementing)
- **No schema changes**: No modification to existing data structures
- **Bidirectional mapping**: Clean export to TodoWrite format, clean import potential

**Implementation** (`lib/grammar.sh`):
```bash
# "Fix authentication bug" → "Fixing authentication bug"
# "Add new feature" → "Adding new feature"
# "Implement search" → "Implementing search"
derive_active_form "$title"
```

**Export Integration**:
```bash
claude-todo export --format todowrite  # Generates TodoWrite-compatible JSON
```

**Trade-offs**:
- Grammar rules may not cover all edge cases (handled by fallback: "Working on X")
- Derived value computed at export time (not stored)

---

## Performance Design

### Optimization Strategies

1. **Lazy Loading**: Only load files when needed
2. **JQ Processing**: Use jq for JSON manipulation (faster than bash loops)
3. **Index Lookups**: Task IDs indexed for O(1) lookups
4. **Batch Operations**: Archive multiple tasks in single operation
5. **Cache Invalidation**: In-memory cache cleared on write

### Performance Targets (Design Goals)

> **Note**: These are design goals for user experience. No formal benchmarks exist.
> Actual performance varies by system. Targets assume SSD storage and modern hardware.

| Operation | Target | Rationale |
|-----------|--------|-----------|
| Task creation | < 100ms | Interactive responsiveness |
| Task completion | < 100ms | Interactive responsiveness |
| Archive (100 tasks) | < 500ms | Batch operation acceptable |
| Validation (100 tasks) | < 200ms | Feedback loop requirement |
| List tasks | < 50ms | Frequent query, must be fast |

### Scalability Limits

- **Design capacity**: 1000+ active tasks, 10,000+ archived tasks
- **Performance degradation**: Linear with task count (jq processing)
- **Refactor threshold**: 10,000+ tasks require database migration

---

## Security Design

### File Permissions

```bash
# Data files: owner read/write, group/other read
chmod 644 .claude/todo*.json

# Scripts: owner all, group/other read+execute
chmod 755 ~/.claude-todo/scripts/*.sh

# Backups: owner only
chmod 700 .claude/.backups/
chmod 600 .claude/.backups/*.json
```

**Why**: Protect task data privacy while allowing scripts to execute.

### Input Validation

- Sanitize all user inputs (prevent command injection)
- Escape special characters in task titles/descriptions
- Limit input length (prevent DOS via large payloads)
- Validate file paths (prevent directory traversal)

**Why**: User input cannot be trusted. Validation prevents security vulnerabilities.

### Data Privacy

- All data stored locally (no network calls)
- No telemetry or tracking
- User controls all data (backup, export, delete)

**Why**: Task data may contain sensitive information. Privacy by default.

---

## Extension Design

### Hook Points

1. **Custom Validators**: `.claude/validators/*.sh` (called after schema validation)
2. **Event Hooks**: `.claude/hooks/on-*.sh` (triggered on task lifecycle events)
3. **Custom Formatters**: `~/.claude-todo/formatters/*.sh` (output format plugins)
4. **Integrations**: `~/.claude-todo/integrations/*.sh` (external system sync)

### Plugin Pattern

```bash
# Validators: return 0 (valid) or non-zero (invalid)
validate_custom() {
    local todo_file="$1"
    # Custom validation logic
    return 0
}

# Hooks: receive context, perform side effects
on_task_complete() {
    local task_id="$1"
    local task_data="$2"
    # Send notification, update tracker, etc.
}

# Formatters: receive data, output formatted content
format_custom() {
    local todo_file="$1"
    # Transform to custom format
}
```

**Why**: Extension points enable customization without modifying core code.

---

## Future Evolution

### Versioning Strategy

- **Major**: Breaking schema changes (migration required)
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes (no schema changes)

### Migration Path

Migrations run automatically on upgrade:

```bash
~/.claude-todo/migrations/
├── migrate-1.0-to-1.1.sh
├── migrate-1.1-to-2.0.sh
└── rollback-2.0-to-1.1.sh
```

### Backward Compatibility

- New fields optional by default
- Deprecated fields supported for 2 major versions
- Clear migration documentation
- Automatic schema version detection

---

## Summary

CLAUDE-TODO design prioritizes:

1. **Correctness over performance** (validation gates, atomic operations)
2. **Safety over convenience** (backups, rollback, audit trails)
3. **Simplicity over features** (Unix philosophy, composable tools)
4. **Transparency over magic** (readable scripts, explicit operations)

These principles ensure the system remains robust, maintainable, and trustworthy for AI-assisted development workflows.
