# CLAUDE-TODO: Project Manifesto

> **The contract between you and your AI coding agent.**

---

## The Problem We Solve

Traditional task management assumes human users. But when your primary "user" is an LLM agent, everything breaks:

| What Humans Need | What Agents Need |
|------------------|------------------|
| Natural language | Structured JSON |
| Descriptive errors | Exit codes |
| Flexibility | Constraints |
| Trust | Validation |
| Memory | Persistence |

**Agents hallucinate.** They invent task IDs that don't exist, claim progress on work never started, and lose track of what's actually done.

**Agents lose context.** Every session starts fresh. Yesterday's progress vanishes. Multi-step workflows fragment across conversations.

**Agents need structure.** Free-form text leads to ambiguity. JSON schemas, exit codes, and strict validation prevent the chaos.

---

## Our Answer: LLM-Agent-First Design

Claude-TODO is built for agents first. Humans second.

### Core Philosophy

```
JSON by default. Text is opt-in.
Exit codes for branching. Not strings.
Validate everything. Trust nothing.
Persist everything. Assume amnesia.
```

The `--human` flag exists for developers reviewing what their agent sees—not as the primary interface.

### The Three Pillars

#### 1. Agent-First, Human-Accessible

- **JSON output by default** when piped (TTY auto-detection)
- **17 documented exit codes** for programmatic branching
- **Structured error responses** with error codes, suggestions, and recoverability flags
- **Native filters** (`--status`, `--label`, `--phase`) reduce token usage vs. jq parsing
- **Context-efficient commands** (`find` returns 1KB vs. 355KB for `list`)

#### 2. Validate Everything

LLMs hallucinate. Every operation validates before execution:

| Layer | Purpose | What It Catches |
|-------|---------|-----------------|
| **Schema** | JSON Schema enforcement | Missing fields, wrong types, invalid enums |
| **Semantic** | Business logic validation | Duplicate IDs, future timestamps, invalid transitions |
| **Cross-File** | Referential integrity | Orphaned references, archive inconsistencies |
| **State Machine** | Transition rules | Invalid status changes, constraint violations |

Before any write:
- ✓ ID exists (prevent hallucinated references)
- ✓ ID unique (across todo.json AND archive)
- ✓ Status valid (pending|active|blocked|done)
- ✓ Timestamps sane (not future, completedAt > createdAt)
- ✓ Dependencies acyclic (no circular references)
- ✓ Parent exists (hierarchy integrity)

#### 3. Persist Everything

Agents lose context. We persist obsessively:

- **Immutable audit trails** in todo-log.json (append-only)
- **Automatic backups** before every write (10-version rotation)
- **Session checkpoints** with focus state and progress notes
- **Archive preservation** of completed work with full history

Pick up exactly where you left off. Every time.

---

## What Claude-TODO Is

### A Task Management Protocol

Not just a CLI—a **protocol** for structured human-agent collaboration:

- **34 commands** across 4 categories (Write, Read, Sync, Maintenance)
- **Single source of truth** in `.claude/todo.json`
- **Bidirectional sync** with Claude Code's ephemeral TodoWrite system
- **Research integration** with web search, library docs, and URL extraction

### A Contract

The system enforces a contract between developer and agent:

| Developer Agrees To | Agent Agrees To |
|---------------------|-----------------|
| Use CLI for all operations | Verify before operating |
| Maintain session discipline | Parse JSON, not text |
| Trust the validation | Use exit codes for branching |
| Review agent decisions | Never hallucinate task IDs |

### A Constraint System

Constraints prevent chaos:

- **One active task** at a time (focus enforcement)
- **Flat, eternal IDs** (T001, T042, T999—never hierarchical)
- **Three-level hierarchy max** (Epic → Task → Subtask)
- **Status state machine** (pending → active → done, with blocked)
- **No time estimates** (scope and complexity only)

---

## Core Features

### Task Hierarchy (v0.17.0+)

```
Epic (strategic initiative)
  └── Task (primary work unit)
        └── Subtask (atomic operation)
```

- Max depth: 3 levels
- Max siblings: 20 per parent (8 active)
- Flat IDs with `parentId` references (identity ≠ structure)

### Session Protocol

```bash
session start → focus set → work → complete → session end
```

- Session notes persist progress across context windows
- Focus enforcement prevents scope creep
- Audit log captures every operation

### Phase Tracking

```
planning → development → testing → deployment
```

- Project-level workflow stages
- One active phase at a time
- Progress tracking per phase

### TodoWrite Integration

Bidirectional sync with Claude Code's ephemeral todo system:

```bash
sync --inject    # Push to TodoWrite (session start)
sync --extract   # Pull from TodoWrite (session end)
```

### Research Aggregation (v0.23.0+)

Multi-source research with citation tracking:

- Web search via Tavily
- Library docs via Context7
- Reddit discussions
- Direct URL extraction

---

## Stable Task IDs: The Foundation

```
T001, T002, T042, T999, T1000...
```

IDs are **flat, sequential, and eternal**:

- No hierarchical IDs like `T001.2.3` that break on restructure
- Hierarchy stored in `parentId` field—identity and structure decoupled
- Every external reference stays valid forever:
  - Git commits: `"Fixes T042"` → always resolves
  - Documentation: `See [T042]` → never orphaned
  - Scripts: `grep T042` → always finds it

---

## Design Principles

### Atomic Operations

Every file modification follows:

```
1. Write to temp file (.todo.json.tmp)
2. Validate temp (schema + anti-hallucination)
3. IF INVALID: Delete temp → Abort → Exit with error
4. IF VALID: Backup original → Atomic rename → Rotate backups
```

No partial writes. No corruption. OS guarantees atomic rename.

### Schema-First Development

- JSON Schema validation prevents corruption
- Error schemas define structured error responses
- Output schemas ensure consistent envelopes
- Config schemas validate settings

### Idempotent Scripts

Safe to run multiple times:

- `update` with identical values returns `EXIT_NO_CHANGE` (102)
- `complete` on already-done task returns `EXIT_NO_CHANGE` (102)
- `archive` skips already-archived tasks

### Zero-Config Defaults

Sensible defaults with optional customization:

```
Defaults → Global config → Project config → Environment → CLI flags
```

Works out of the box. Customize when needed.

---

## Target Users

### Primary: AI Coding Agents

- Claude Code as the canonical consumer
- Any LLM-based coding assistant
- Automated workflows and CI/CD pipelines

### Secondary: Solo Developers

- Developers working with AI agents
- Teams needing consistent task tracking
- Projects requiring audit trails

### The Relationship

```
Developer defines intent → Agent executes tasks → System validates everything
```

The developer is the architect. The agent is the builder. Claude-TODO is the building code.

---

## Success Metrics

### For Agents

- Zero hallucinated task references
- 100% structured output parsing
- Predictable exit codes for branching
- Minimal context usage (find vs. list)

### For Developers

- Complete audit trail of agent actions
- Recovery from any failure state
- Confidence in agent task execution
- Visibility into agent progress

### For the System

- Sub-100ms task operations
- Zero data loss on failure
- Schema validation on every write
- Backward-compatible migrations

---

## The Manifesto Summary

**One developer. One agent. One source of truth.**

Claude-TODO exists because:

1. **Agents need constraints** to produce reliable output
2. **Agents need validation** because they hallucinate
3. **Agents need persistence** because they forget
4. **Agents need structure** because ambiguity breeds errors

We build for the agent first, because that's who does the work. We make it human-accessible, because that's who reviews the work.

The CLI is the contract. The schema is the law. The audit log is the record.

**Trust but verify. Persist everything. Ship working software.**

---

## Technical Reference

### Installation Model

```
~/.claude-todo/           # Global installation
├── scripts/              # 35 command implementations
├── lib/                  # Shared libraries (validation, file-ops, logging)
├── schemas/              # JSON Schema definitions (7 schemas)
└── docs/                 # Documentation

project/.claude/          # Per-project instance
├── todo.json            # Active tasks (source of truth)
├── todo-archive.json    # Completed tasks (immutable)
├── todo-log.json        # Audit trail (append-only)
├── todo-config.json     # Project configuration
└── .backups/            # Automatic versioned backups
```

### Command Categories

| Category | Count | Purpose |
|----------|:-----:|---------|
| Write | 7 | Modify task state (add, update, complete, focus, session, phase, archive) |
| Read | 17 | Query and analyze (list, show, find, analyze, next, dash, deps, blockers, etc.) |
| Sync | 3 | TodoWrite integration (sync, inject, extract) |
| Maintenance | 7 | System administration (init, validate, backup, restore, migrate, config) |

### Exit Code Ranges

| Range | Purpose |
|-------|---------|
| 0 | Success |
| 1-9 | General errors (invalid input, file error, not found, validation) |
| 10-19 | Hierarchy errors (parent not found, depth exceeded, sibling limit) |
| 20-29 | Concurrency errors (checksum mismatch, lock timeout) |
| 100+ | Special conditions (no data, already exists, no change) |

### LLM-Agent-First Compliance

- 33/33 commands with full envelope compliance
- All outputs include `$schema`, `_meta`, `success` fields
- All errors use structured `output_error()` function
- All commands support `--format` and `--quiet` flags
- TTY auto-detection via `resolve_format()`

---

*Version: 2.0 | Updated: 2025-12-20 | Aligned with: v0.24.0*
