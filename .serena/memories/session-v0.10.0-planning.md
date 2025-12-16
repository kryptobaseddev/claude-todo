# Session Summary: Next Release Planning

**Last Updated**: 2025-12-13
**Current Version**: 0.10.1
**Next Patch**: v0.10.2

## Project Status

| Metric | Value |
|--------|-------|
| Total Active | 85 tasks |
| Archived | 35 tasks |
| Completed | 81 (95%) |
| Pending | 5 |
| Core Phase | 100% complete |
| Polish Phase | 73% complete |

## Recently Completed

### v0.10.1 (Current)
- Backup system improvements
- Documentation updates

### v0.9.9
- init.sh source directory fallback for CI
- Checksum calculation fix
- JSON output parsing documentation

### v0.9.8
- T175: Title validation character count
- T176: Complete command --notes/--skip-notes docs
- T177: Phase validation + --add-phase flag

---

## v0.10.2 Roadmap - Visibility & History Features

### High Priority
| ID | Task | Labels |
|----|------|--------|
| **T178** | Add `list --archived` flag to view archived tasks | feature, list-command, ux |
| **T179** | Add `log show/list` subcommands for viewing log entries | feature, log-command, ux |

### Medium Priority
| ID | Task | Labels |
|----|------|--------|
| **T180** | Fix log entry schema inconsistency (action vs operation) | bug, schema |
| **T181** | Add `history`/`report` command for completion timeline | feature, reporting |
| **T182** | Enhance dashboard with archived + completion history | feature, dash-command |

### Key Findings (from investigation)
- Archive has **35 tasks** in `.archivedTasks[]`
- Log has **153 entries** but inconsistent schema (44 use `operation`, 109 use `action`)
- No way to VIEW archived tasks (only archive command)
- No log reader (only writer)
- Dashboard shows counts but no completion details

---

## Suggested Work Order

1. **T180** (bug fix) → Standardize log schema before building viewers
2. **T178** (`list --archived`) → Quick win, reuses existing list code
3. **T179** (`log show`) → Similar pattern to list command
4. **T182** (dashboard) → Enhance with archive/completion sections
5. **T181** (`history`) → Builds on all above

## Dependencies
```
T180 (schema fix) ← Should do first
    ↓
T178, T179, T182 (can parallelize)
    ↓
T181 (history - uses all above)
```

## Notes for Next Session

- Start with T180 to fix log schema consistency
- T178 is quick win - just add --archived flag to list
- Dashboard enhancement (T182) ties everything together
- All tasks are in `polish` phase