# Documentation Maintenance Workflow

## Hierarchy (Layer 1 → 4)
1. `templates/CLAUDE-INJECTION.md` → Minimal, ~10 essential commands
2. `docs/TODO_Task_Management.md` → Concise, all commands grouped
3. `docs/commands/*.md` → SOURCE OF TRUTH, comprehensive
4. `docs/INDEX.md` → Master index, links everything

## When Adding/Modifying Commands

**Required updates:**
1. `docs/commands/<cmd>.md` — Full docs (options table, examples, exit codes)
2. `docs/INDEX.md` — Add link + one-line description
3. `docs/TODO_Task_Management.md` — Add command syntax to appropriate section

**Conditional:**
4. `templates/CLAUDE-INJECTION.md` — Only if essential (used >50% sessions)

## Principles
- Single source of truth in Layer 3
- Higher layers reference, never duplicate
- LLM-optimized: Layers 1-2 scannable, not verbose
- Human-optimized: Layer 3 comprehensive

## Full Guide
See: docs/DOCUMENTATION-MAINTENANCE.md
