# Phase-Aware TodoWrite Extract - Executive Summary

**Full Analysis**: [phase-aware-todowrite-extract.md](./phase-aware-todowrite-extract.md)

## Problem Statement

TodoWrite extract currently:
- Creates new tasks with NO phase assignment
- Preserves existing task phases (read-only)
- Provides no phase completion detection
- Has no phase statistics in output
- No workflow progression automation

## Proposed Solution

### 1. New Task Phase Assignment

**Algorithm**:
```
get_session_phase():
  1. If focus.currentTask exists → use focused task's phase
  2. Else use phase with most active/pending tasks
  3. Else null (no phase context)
```

**Example**:
```bash
# Session with focused task T001 (phase: core)
TodoWrite creates: "Add validation"
Extract result: T010 created with phase=core
```

### 2. Phase Completion Detection

**Algorithm**:
```
After applying completions:
  For each completed task:
    Check if ALL tasks in task's phase are now done
    If yes → log phase completion milestone
```

**Example**:
```bash
# Complete last task in 'setup' phase
Extract output:
  ✓ Phase 'setup' completed (all 10 tasks done)
```

### 3. Auto-Advance (Opt-In)

**Flag**: `--auto-advance` (disabled by default)

**Behavior**:
```
If phase complete AND auto-advance enabled:
  Find next phase by order
  Update project phase context (future: schema field)
  Log transition
```

**Example**:
```bash
ct sync --extract --auto-advance
# Phase 'setup' complete. Auto-advanced to 'core'.
```

### 4. Phase Statistics in Output

**Enhanced Summary**:
```
Changes detected: 3 completed, 1 progressed, 2 new

Completions by phase:
  2 tasks in phase: core
  1 task in phase: setup

Phase milestones:
  ✓ Phase 'setup' completed (all tasks done)
```

### 5. Audit Logging

**New Events**:
- `phase_inherited` - New task got phase from context
- `phase_completed` - All tasks in phase done
- `phase_auto_advanced` - Workflow progression triggered

## Architecture Decisions

### No Schema Change (v1)

**Decision**: Infer "current phase" from heuristics, not explicit field.

**Rationale**:
- No migration required
- Backward compatible
- Sufficient for 90% of use cases

**Future**: Add `.project.currentPhase` in v2.0 for explicit phase tracking.

### Conservative Auto-Advance

**Decision**: Opt-in flag, not default behavior.

**Rationale**:
- Phase transitions are milestones (should be intentional)
- Risk of premature progression
- User may want to add more tasks to "complete" phase
- Easy to enable for aggressive workflows

### Phase Inheritance Priority

**Decision**: Focus task phase > Most active phase > null

**Rationale**:
- Focus task is more intentional (user explicitly chose it)
- Most active is good fallback when no focus
- Null preserves current behavior when no context

## Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| No focused task | Use most active phase heuristic |
| Focus has null phase | Fallback to most active phase |
| Multiple phases complete | Report all completions |
| Last phase complete | No error, suggest archiving |
| Phase deleted during session | Allow orphaned phase, warn |
| Circular phase orders | Alphabetical tie-breaker |

## Implementation Phases

### Phase 1: Foundation (v0.15.0) - RECOMMENDED

- New task phase assignment
- Phase statistics in summary
- Basic audit logging
- **NO auto-advance** (too risky without testing)

**Effort**: 2-3 days

### Phase 2: Completion Detection (v0.15.0)

- Phase completion check
- Milestone reporting
- Enhanced audit events

**Effort**: 1-2 days

### Phase 3: Auto-Advance (v0.16.0)

- `--auto-advance` flag
- Config option
- Next phase detection

**Effort**: 2 days

### Phase 4: Enhanced Reporting (v0.16.0)

- JSON output format
- Dashboard integration

**Effort**: 1 day

### Phase 5: Schema Extension (v2.0.0)

- Add `.project.currentPhase`
- Migration tooling
- Explicit phase commands

**Effort**: 3-4 days

## Performance Impact

| Operation | Overhead | Mitigation |
|-----------|----------|------------|
| Extract completion | +10ms (100 tasks) | Batch jq queries |
| New task creation | +5ms per task | Single heuristic call |
| Phase statistics | +10ms per extract | Cached phase data |

**Total**: <50ms typical session (negligible)

## Test Coverage

**Unit Tests**:
- `get_session_phase()` with focus/no focus/no phases
- `check_phase_completion()` single/multiple/none
- Phase inheritance logic
- Auto-advance next phase detection

**Integration Tests**:
- End-to-end extract with phase assignment
- Phase completion detection in real workflow
- Auto-advance flag behavior
- Multi-phase session handling

**Golden Files**:
- Extract output with phase stats
- Phase completion messages
- Auto-advance transitions

## Configuration Defaults

```json
{
  "sync": {
    "phaseAssignment": {
      "enabled": true,
      "strategy": "focus_task",
      "fallback": "most_active"
    },
    "phaseCompletion": {
      "detection": true,
      "reporting": "verbose",
      "autoAdvance": false  // Conservative
    },
    "phaseAuditLog": {
      "logInheritance": true,
      "logCompletion": true,
      "logAutoAdvance": true
    }
  }
}
```

## Success Criteria

- New tasks get appropriate phase ≥90% of time
- Phase completion detection: 100% accuracy
- Extract performance overhead: <10%
- Zero regressions in existing tests
- User satisfaction: ≥50% reduction in manual phase assignment

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Heuristic assigns wrong phase | Medium | Fallback to null, user can override |
| Auto-advance premature | High | Disabled by default, opt-in only |
| Performance regression | Low | Batch queries, <50ms overhead |
| Schema conflict (future) | Low | Phase 5 only, explicit migration |

## Backward Compatibility

**Guaranteed**:
- Existing tasks without phases work unchanged
- Extract without flags behaves identically
- No schema changes in v0.15-0.16

**Optional**:
- All new features are opt-in or config-controlled
- Safe defaults for all settings

## Recommendations

### Immediate (v0.15.0)

**Implement Phase 1 + 2**:
- New task phase assignment (heuristic-based)
- Phase completion detection and reporting
- Enhanced audit logging
- NO auto-advance (defer to v0.16.0)

**Rationale**: Provides 80% of value with minimal risk.

### Near-Term (v0.16.0)

**Add Phase 3 + 4**:
- Auto-advance as opt-in feature
- JSON output for scripting
- Dashboard integration

### Future (v2.0.0)

**Schema Extension (Phase 5)**:
- Explicit `.project.currentPhase` field
- Phase history tracking
- Phase lifecycle commands

## Next Steps

1. **Review**: Stakeholder approval of design
2. **Plan**: Create implementation tasks (T239-T243)
3. **Develop**: Begin Phase 1 implementation
4. **Test**: Integration testing with real workflows
5. **Document**: Update user-facing docs
6. **Release**: v0.15.0 with phase-aware extract

---

**Full Details**: See [phase-aware-todowrite-extract.md](./phase-aware-todowrite-extract.md)
**Status**: Ready for Implementation
**Target**: v0.15.0 (January 2026)
