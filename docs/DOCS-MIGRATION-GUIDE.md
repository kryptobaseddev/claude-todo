# Documentation Migration Guide

**Version**: 2.2.0
**Date**: 2025-12-12
**Status**: In Progress

## Overview

The CLAUDE-TODO documentation is being reorganized for better discoverability, reduced duplication, and maintainability. This guide tracks the migration progress.

---

## Current Structure (v2.2.0)

```
docs/
├── architecture/                    # System design (LLM-focused)
│   ├── ARCHITECTURE.md             # Core architecture + design principles
│   └── DATA-FLOWS.md               # Visual data flow diagrams
│
├── getting-started/                 # Onboarding
│   ├── installation.md             # Installation guide
│   └── quick-start.md              # First steps
│
├── guides/                          # How-to guides
│   ├── command-reference.md        # Complete CLI reference
│   ├── configuration.md            # Configuration options
│   ├── filtering-guide.md          # Advanced filtering
│   └── workflow-patterns.md        # Usage patterns & recipes
│
├── integration/                     # Claude Code specific
│   └── CLAUDE-CODE.md              # LLM-optimized integration guide
│
├── reference/                       # Technical reference
│   ├── schema-reference.md         # JSON schema documentation
│   └── troubleshooting.md          # Common issues & solutions
│
├── INDEX.md                        # Comprehensive navigation
├── QUICK-REFERENCE.md              # Cheatsheet
├── README.md                       # Documentation hub
├── PLUGINS.md                      # Plugin development guide
├── TODO_Task_Management.md         # CLI reference (installed to ~/.claude-todo/)
├── migration-guide.md              # Schema migration guide
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

### Files Created

| File | Purpose | Lines |
|------|---------|-------|
| `integration/CLAUDE-CODE.md` | LLM-optimized Claude Code integration guide | 382 |

---

## Remaining Work (Future Session)

### Potential Consolidations

| Current Files | Consideration | Priority |
|---------------|---------------|----------|
| `INDEX.md` + `README.md` | May have overlap - review and consolidate | Medium |
| `schema-reference.md` | Consider moving to `architecture/SCHEMAS.md` | Low |
| `migration-guide.md` | Consider moving to `reference/` | Low |

### Structure Refinements

The original plan suggested a `reference/` directory with:
- usage.md
- command-reference.md
- configuration.md
- troubleshooting.md
- installation.md

Current structure uses `getting-started/`, `guides/`, `reference/` which provides better progressive disclosure for users. This is a valid alternative structure.

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

- `getting-started/installation.md` - Setup
- `getting-started/quick-start.md` - First steps
- `guides/command-reference.md` - CLI commands
- `guides/configuration.md` - Config options
- `guides/filtering-guide.md` - Query guide
- `guides/workflow-patterns.md` - Recipes

### Reference

- `reference/schema-reference.md` - JSON schemas
- `reference/troubleshooting.md` - Problem solving

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
