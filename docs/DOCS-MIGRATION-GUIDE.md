# Documentation Migration Guide

> **⚠️ INTERNAL DOCUMENT**: This is a temporary tracking document for the documentation restructuring effort. It is not part of the user-facing documentation and may be removed once migration is complete.

**Version**: 2.2.0
**Date**: 2025-12-12
**Status**: Internal/Temporary

## Overview

The CLAUDE-TODO documentation is being reorganized for better discoverability, reduced duplication, and maintainability. This guide tracks the migration progress.

---

## Current Structure (v2.2.0)

```
docs/
├── architecture/                    # System design (LLM-focused)
│   ├── ARCHITECTURE.md             # Core architecture + design principles
│   ├── DATA-FLOWS.md               # Visual data flow diagrams
│   └── SCHEMAS.md                  # JSON schema documentation
│
├── getting-started/                 # Onboarding
│   └── quick-start.md              # First steps guide
│
├── guides/                          # How-to guides
│   └── filtering-guide.md          # Advanced filtering & queries
│
├── integration/                     # Claude Code specific
│   ├── CLAUDE-CODE.md              # LLM-optimized integration guide
│   └── WORKFLOWS.md                # Session workflows & patterns
│
├── reference/                       # Technical reference
│   ├── command-reference.md        # Complete CLI reference
│   ├── configuration.md            # Configuration options
│   ├── installation.md             # Installation guide
│   ├── migration-guide.md          # Schema migration guide
│   └── troubleshooting.md          # Common issues & solutions
│
├── INDEX.md                        # Comprehensive navigation
├── QUICK-REFERENCE.md              # Cheatsheet
├── README.md                       # Documentation hub
├── PLUGINS.md                      # Plugin development guide
├── TODO_Task_Management.md         # CLI reference (installed to ~/.claude-todo/)
├── usage.md                        # Main usage guide
└── DOCS-MIGRATION-GUIDE.md         # This file
```

**Total Files**: 19

---

## Completed Migrations (T087-T093)

### Files Merged/Deleted

| Original File | Action | Destination |
|---------------|--------|-------------|
| `design-principles.md` | Merged | `architecture/ARCHITECTURE.md` (Core Philosophy, System Invariants, Architectural Decisions sections) |
| `WORKFLOW.md` | Merged | `integration/CLAUDE-CODE.md` (Session Protocol section) |
| `ENHANCEMENT-todowrite-integration.md` | Merged | `integration/CLAUDE-CODE.md` (TodoWrite Integration section) |
| `MIGRATION-SYSTEM-SUMMARY.md` | Deleted | Redundant with `migration-guide.md` |
| `SYSTEM-DESIGN-SUMMARY.md` | Merged | `architecture/ARCHITECTURE.md` (Executive Summary) |

### Files Moved

| Original Location | New Location |
|-------------------|--------------|
| `docs/ARCHITECTURE.md` | `docs/architecture/ARCHITECTURE.md` |
| `docs/DATA-FLOW-DIAGRAMS.md` | `docs/architecture/DATA-FLOWS.md` |
| `docs/migration-guide.md` | `docs/reference/migration-guide.md` |

### Files Created

| File | Purpose | Lines |
|------|---------|-------|
| `integration/CLAUDE-CODE.md` | LLM-optimized Claude Code integration guide | 382 |

---

## Remaining Work (Future Session)

### Potential Consolidations

| Current Files | Consideration | Priority |
|---------------|---------------|----------|
| `INDEX.md` + `README.md` | Both serve as navigation - consolidate to single entry point | Medium |
| ~~`migration-guide.md`~~ | ~~Consider moving to `reference/`~~ | ✅ Done |
| `integration/WORKFLOWS.md` | Consider merging into `CLAUDE-CODE.md` if overlapping | Low |

### Structure Notes

Current structure organizes documentation by audience:
- **architecture/** - System internals (developers, LLMs)
- **integration/** - Claude Code specific (AI agents)
- **getting-started/** - New users
- **guides/** - Users wanting to learn features
- **reference/** - Users looking up specifics

### Target Metrics

| Metric | Original Target | Current | Status |
|--------|-----------------|---------|--------|
| Total files | ~13 | 19 | Review needed |
| usage.md lines | ~500 | 599 | Close |
| Duplication | <5% | ~5% | Achieved |

---

## Key Files Reference

### Essential (Keep)

- `README.md` - Documentation entry point
- `QUICK-REFERENCE.md` - Developer cheatsheet
- `INDEX.md` - Comprehensive navigation
- `PLUGINS.md` - Plugin system documentation
- `TODO_Task_Management.md` - Installed to ~/.claude-todo/docs/
- `usage.md` - Main usage guide
- `migration-guide.md` - Schema migration for users

### Architecture (LLM-Focused)

- `architecture/ARCHITECTURE.md` - Complete system design
- `architecture/DATA-FLOWS.md` - Visual diagrams
- `integration/CLAUDE-CODE.md` - Claude Code integration

### User Guides

- `getting-started/quick-start.md` - First steps
- `guides/filtering-guide.md` - Query guide
- `integration/WORKFLOWS.md` - Session workflows & patterns

### Reference

- `reference/installation.md` - Setup guide
- `reference/command-reference.md` - CLI commands
- `reference/configuration.md` - Config options
- `reference/troubleshooting.md` - Problem solving
- `architecture/SCHEMAS.md` - JSON schemas

---

## Path Update Reference

For scripts/links referencing old paths:

```bash
# Architecture files
docs/ARCHITECTURE.md → docs/architecture/ARCHITECTURE.md
docs/DATA-FLOW-DIAGRAMS.md → docs/architecture/DATA-FLOWS.md

# Deleted files (use new locations)
docs/design-principles.md → docs/architecture/ARCHITECTURE.md#design-principles
docs/WORKFLOW.md → docs/integration/CLAUDE-CODE.md
docs/ENHANCEMENT-todowrite-integration.md → docs/integration/CLAUDE-CODE.md
docs/MIGRATION-SYSTEM-SUMMARY.md → docs/migration-guide.md
docs/SYSTEM-DESIGN-SUMMARY.md → docs/architecture/ARCHITECTURE.md
```

---

## Migration History

| Date | Tasks | Changes |
|------|-------|---------|
| 2025-12-12 | T079-T086 | Initial restructure: created guides/, getting-started/, reference/ |
| 2025-12-12 | T087-T093 | Consolidated architecture docs, created integration/, merged redundant files |

---

**Next Session**: Review file count, consider additional consolidations, update install.sh if needed.

**Last Updated**: 2025-12-12
