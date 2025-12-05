# Project Purpose

## CLAUDE-TODO System

A robust, installable task management system specifically designed for Claude Code with the following core features:

### Primary Goals
1. **Task Management**: Comprehensive TODO tracking for Claude Code operations
2. **Auto-Archiving**: Automatic archival of completed tasks based on configurable policies
3. **Configuration Management**: Flexible per-project and global configuration system
4. **Change History**: Complete audit trail of all task operations
5. **Anti-Hallucination**: Built-in validation mechanisms to prevent AI-generated errors
6. **Data Integrity**: Schema validation and atomic file operations

### Key Design Principles
- **Single Source of Truth**: todo.json as primary task state
- **Immutable History**: Append-only logging for auditability
- **Fail-Safe Operations**: Atomic file operations with validation
- **Schema-First**: JSON Schema validation prevents corruption
- **Idempotent Scripts**: Safe to run multiple times
- **Zero-Config Defaults**: Sensible defaults with optional customization

### Target Users
- Claude Code developers needing reliable task tracking
- Projects requiring audit trails and task history
- Teams needing consistent task management across projects
- Users requiring validation against hallucination-based errors

### Installation Model
- **Global Installation**: ~/.claude-todo/ contains schemas, templates, scripts, libraries
- **Per-Project Initialization**: Each project gets .claude/ directory with task files
- **Version Control**: Task files excluded from git, system files tracked in repository
