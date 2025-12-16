# Session Handoff - 2025-12-16 (Updated)
**Version**: v0.13.3
**Status**: Session Complete - Repair Command Needed

## Critical Issue: This Project Has Wrong Phase Structure
- `.claude/todo.json` has 4 phases: setup, core, polish, release
- SHOULD have 5 phases: setup, core, testing, polish, maintenance
- **CANNOT be fixed manually** - MUST use `migrate repair` command (T302)
- Proof: `claude-todo add --phase testing` fails

## Bugs Fixed This Session

| Version | Bug | Fix |
|---------|-----|-----|
| v0.13.1 | IFS bug in migration | Added `IFS=' '` to read statements |
| v0.13.1 | Argument list too long | Changed to stdin piping/temp files |
| v0.13.2 | Wrong 4-phase structure | Fixed migration to 5-phase |
| v0.13.3 | Hardcoded phases | Migration reads from template |

## Tasks Created

| ID | Title | Priority |
|----|-------|----------|
| T302 | Implement 'migrate repair' command | critical |
| T303 | T302.1: Add repair subcommand to scripts/migrate.sh | high |
| T304 | T302.2: Implement schema comparison logic | high |
| T305 | T302.3: Implement repair execution functions | high |
| T306 | T302.5: Document migrate repair command | medium |
| T307 | T302.4: Add comprehensive tests | high |
| T308 | Repair this project's phases | critical |
| T309 | Regenerate golden test fixtures | medium |

## What 'migrate repair' Must Do

1. **Phase Structure**: Ensure canonical 5-phase (setup→core→testing→polish→maintenance)
2. **Preserve Data**: Keep existing phase status/timestamps where valid
3. **Schema Fields**: Add missing _meta, focus, project fields
4. **Remove Obsolete**: Delete invalid fields (like 'release' phase)
5. **Idempotent**: Safe to run multiple times
6. **Backup First**: Always create backup before changes
7. **Log Changes**: Record all modifications

## Test Status
- Unit/Integration: 1015 passing
- Golden: 6 failing (need regeneration)

## Canonical 5-Phase Structure
```
setup (1) → core (2) → testing (3) → polish (4) → maintenance (5)
    ↓           ↓           ↓            ↓            ↓
foundation  features   validation   refinement    support
```

## Next Session Actions
1. Implement T302 'migrate repair' command
2. Use it to fix T308 (this project's phases)
3. Regenerate golden tests (T309)
4. Verify all tests pass
5. Release v0.14.0

## Data Integrity Rules
- NEVER lose task data
- NEVER manually edit .claude/*.json
- ALWAYS use CLI commands
- ALWAYS backup before modification
