# Project-Level Phase Enhancement: Edge Case & Risk Analysis

**Date**: 2025-12-15
**Purpose**: Comprehensive risk analysis for project-level phase enhancement (no implementation)
**Scope**: Identify edge cases, risks, and mitigation strategies for adding project-level phase tracking

---

## Executive Summary

Current state: claude-todo has **task-level** phases (99/143 tasks use phases) but no **project-level** phase tracking. This analysis examines 10 critical scenarios that could arise when adding project-level phase management.

**Key Findings**:
- **Current Usage**: 69% of tasks have phases (setup: 14, core: 63, polish: 22), 31% have no phase
- **Existing Infrastructure**: Phases defined in `todo.json`, validated on add/update, used in filtering
- **Config Default**: `defaults.phase: "core"` exists but tasks without phases aren't auto-assigned
- **No Project Phase**: System currently has no concept of "current project phase"

---

## Scenario 1: User Never Sets a Project Phase

### Risk Level: **LOW** (Graceful degradation required)

### Current Behavior
- Tasks can have phases, but no global "current project phase" exists
- `ct phases` shows all phases with progress bars
- `ct dash` displays phase distribution but no active phase indicator

### Edge Cases
1. **Zero-state UX**: What happens on `ct init`?
   - Currently: No phases defined, users must manually add phase definitions
   - Risk: Users might not discover phase features

2. **Mixed phase usage**: Some tasks with phases, some without
   - Currently: 44/143 tasks have no phase (31%)
   - Risk: Ambiguous "what phase am I in?" state

3. **Inference attempts**: Should system infer project phase from focused task?
   - Current focus: No phase (focus.currentTask is null)
   - Risk: Automatic inference could be wrong

### Mitigation Strategies
```
OPTION A: Make project phase optional (recommended)
- Commands work without project phase
- "ct phases" shows all phases, highlights suggested current (most active tasks)
- Warning if >50% of tasks span multiple phases

OPTION B: Default to first phase in order
- On init, set project.currentPhase to phase with order: 1
- Auto-create "setup" phase if none defined
- Risk: Assumes sequential workflow

OPTION C: Require explicit phase selection
- Block certain operations until project phase set
- Too rigid for flexible workflows
```

**Recommendation**: Option A with smart defaults. System works without project phase; suggests phase based on focused task or highest activity.

---

## Scenario 2: Task Phase Doesn't Match Project Phase

### Risk Level: **MEDIUM** (Common legitimate scenario)

### Context
In real development:
- Tasks span multiple phases (tech debt from early phases)
- Planning ahead (creating future phase tasks)
- Backtracking (fixing setup issues while in core phase)

### Edge Cases
1. **Active task in different phase than project**
   ```
   project.currentPhase: "core"
   focus.currentTask: "T045" (phase: "polish")
   ```
   - Is this an error or legitimate work?
   - Should system warn or silently allow?

2. **Dependency chains across phases**
   ```
   T001 (setup, done) ← T050 (core, active) ← T099 (polish, pending)
   project.currentPhase: "core"
   ```
   - Dependencies naturally span phases
   - Risk: Blocking polish tasks too aggressively

3. **Bulk operations across phases**
   ```
   ct list --status pending  # Returns tasks from all phases
   ```
   - Should phase-agnostic commands filter by project phase?
   - Risk: Hiding relevant tasks

### Mitigation Strategies
```
STRICT MODE (opt-in via config)
- validation.enforcePhaseOrder: true
- Warn when activating task outside project phase
- Prevent phase advancement if current phase incomplete

PERMISSIVE MODE (default)
- No restrictions on task phase vs project phase
- Visual indicator in dash/list when task phase != project phase
- Allow cross-phase work explicitly

PHASE CONTEXT (middle ground)
- ct focus set T045  # If T045.phase != project.currentPhase
  → Prompt: "T045 is in 'polish' phase, but project is in 'core'. Continue? [y/N]"
- --force flag to skip prompts
```

**Recommendation**: Permissive mode by default with optional warnings. Add `validation.warnPhaseContext: true` config option.

---

## Scenario 3: Tasks with No Phase Assigned

### Risk Level: **LOW-MEDIUM** (Already exists, needs handling)

### Current State
- **44 tasks** (31%) have no phase
- Tasks created before phases were used
- Quick tasks that don't fit workflow

### Edge Cases
1. **Filtering with project phase active**
   ```
   project.currentPhase: "core"
   ct list  # Should this show phaseless tasks?
   ```
   - Include phaseless tasks in all contexts?
   - Treat as "inbox" or "backlog"?

2. **Next task suggestion logic**
   ```
   ct next  # Suggests next task to work on
   ```
   - Current logic: priority + dependencies
   - Should project phase influence selection?
   - What priority for phaseless tasks?

3. **Phase advancement checks**
   ```
   project.currentPhase: "core"
   ct phase advance  # Move to next phase
   ```
   - Are phaseless tasks blockers for advancement?
   - Should they be auto-assigned to current phase?

### Mitigation Strategies
```
OPTION A: Phaseless tasks are phase-agnostic
- Always visible in lists
- Never block phase advancement
- Virtual "backlog" or "inbox" phase

OPTION B: Auto-assign on creation
- Use defaults.phase from config
- Backfill existing phaseless tasks on upgrade
- Risk: Incorrect assumptions about task intent

OPTION C: Treat as legacy/temporary
- Warn when creating phaseless tasks
- Require explicit --no-phase flag
- Risk: Too restrictive
```

**Recommendation**: Option A. Treat phaseless tasks as universal/cross-cutting. Show in all phase views with visual indicator `[no-phase]`.

---

## Scenario 4: Phase Advance with Incomplete Tasks

### Risk Level: **MEDIUM-HIGH** (Critical workflow decision)

### Context
Real projects often have:
- Technical debt carried forward
- Lower priority tasks deferred
- Blocked tasks awaiting external dependencies

### Edge Cases
1. **Strict phase completion**
   ```
   project.currentPhase: "core"
   Tasks in core: 63 total, 55 done, 8 pending (2 blocked, 6 low priority)
   ct phase advance → Allow or block?
   ```
   - Should ALL tasks be complete?
   - What about blocked tasks?

2. **Critical vs non-critical tasks**
   ```
   Pending in core: T050 (critical), T051 (low)
   ```
   - Should only critical/high tasks block advancement?
   - Who defines "phase-blocking" tasks?

3. **Dependency violations**
   ```
   T100 (polish, pending) depends on T050 (core, pending)
   ct phase advance → core to polish
   ```
   - Risk: Advancing to phase with unmet dependencies
   - Cross-phase dependency checking

### Mitigation Strategies
```
STRICT ENFORCEMENT
- Block advancement if ANY pending/active tasks in current phase
- Exception: Blocked tasks with explicit blockedBy reason
- Exception: Tasks marked --non-blocking flag
- Pro: Ensures phase completion
- Con: Rigid, slows progress

SOFT WARNINGS
- Allow advancement, warn about incomplete tasks
- Interactive prompt: "8 tasks remain in 'core'. Continue? [y/N]"
- Log phase advancement decision
- Pro: Flexible
- Con: Easy to ignore warnings

TASK-BASED GATING
- Add task.phaseBlocking field (boolean)
- Only high/critical tasks are phase-blocking by default
- ct task update T050 --phase-blocking
- Pro: Fine-grained control
- Con: Added complexity

PERCENTAGE THRESHOLD
- validation.phaseAdvanceThreshold: 90  # 90% completion required
- Ignores low priority tasks in calculation
- Pro: Pragmatic
- Con: Percentage can be misleading
```

**Recommendation**: Hybrid approach
1. Default: Warn on advancement with pending tasks, require `--force`
2. Config: `validation.phaseAdvanceThreshold: 90` (percentage)
3. Config: `validation.blockOnCriticalTasks: true` (critical tasks always block)
4. Interactive prompt shows what's incomplete

---

## Scenario 5: Multiple Phases Active Simultaneously

### Risk Level: **HIGH** (Data integrity violation)

### Context
Project-level phase should be singular: one active phase at a time. Multiple active phases indicate error state.

### Edge Cases
1. **Concurrent modifications**
   ```
   Session A: ct phase set core
   Session B: ct phase set polish  # Race condition
   Result: project.currentPhase corrupted or inconsistent
   ```

2. **Phase history tracking**
   ```
   project.currentPhase: "core"
   project.phaseHistory: [
     {"phase": "setup", "startedAt": "...", "completedAt": "..."},
     {"phase": "core", "startedAt": "...", "completedAt": null}
   ]
   ```
   - What if phase history shows multiple phases with `completedAt: null`?
   - Recovery: Auto-close older phases?

3. **TodoWrite sync conflicts**
   ```
   Before sync: project.currentPhase = "core"
   After sync: New tasks added with phase="polish"
   Should sync change project phase?
   ```

### Mitigation Strategies
```
PREVENTION
- File locking on phase change operations (same as task operations)
- Atomic updates with checksum verification
- Schema validation: Only one phase can have completedAt: null in history

DETECTION
- ct validate checks for multiple active phases
- Exit code 2 for project-level errors
- validate --fix: Auto-close all but most recent phase

RECOVERY
- Prompt user: "Multiple active phases detected: [core, polish]. Select current:"
- Log recovery action
- Backup before auto-fix
```

**Recommendation**: Prevention via locking + validation detection + interactive recovery.

---

## Scenario 6: Phase Rollback (Going Backwards)

### Risk Level: **MEDIUM** (Legitimate but complex)

### Context
Sometimes projects need to rollback:
- Major bug found in earlier phase
- Requirements change, need to revisit setup
- Iterative workflows (setup → core → setup → core)

### Edge Cases
1. **Simple rollback**
   ```
   Current: project.currentPhase = "polish"
   Command: ct phase set core
   ```
   - Mark polish as incomplete in history?
   - What happens to polish tasks?

2. **Task status implications**
   ```
   T099 (polish, done) completed before rollback
   After rollback to core:
   - Should T099 stay done?
   - Should T099 be reset to pending?
   ```

3. **Multiple rollbacks**
   ```
   setup → core → polish → core → polish → core
   ```
   - Phase history becomes complex
   - How to represent iterative development?

### Mitigation Strategies
```
DISALLOW ROLLBACK (safest)
- Phases are monotonically increasing
- Only advance, never retreat
- Pro: Simple
- Con: Doesn't match real workflows

ALLOW WITH WARNING
- ct phase set setup --rollback
- Interactive prompt: "This will rollback from 'core' to 'setup'. Continue?"
- Mark current phase as incomplete in history
- Pro: Flexible
- Con: Phase history becomes messy

BRANCHING PHASES
- Allow non-linear phase progression
- Track phase transitions as directed graph
- Pro: Handles complex workflows
- Con: Significant complexity

VERSION-BASED PHASES
- setup-v1, core-v1, polish-v1
- setup-v2, core-v2, polish-v2
- Each iteration is new phase set
- Pro: Clear versioning
- Con: Phase explosion
```

**Recommendation**: Allow rollback with explicit `--rollback` flag and warning. Mark intermediate phases as incomplete. Log reason in phase history.

---

## Scenario 7: Deleting or Renaming Phases with Tasks

### Risk Level: **HIGH** (Data integrity + orphan risks)

### Context
Phase definitions can change:
- Typos in phase names
- Workflow evolution (rename "core" to "development")
- Removing deprecated phases

### Edge Cases
1. **Delete phase with active tasks**
   ```
   Phases: {setup, core, polish}
   Tasks: T001-T063 have phase="core"
   Command: ct phase delete core
   ```
   - Orphan 63 tasks?
   - Prevent deletion?
   - Force reassignment?

2. **Rename phase**
   ```
   Rename: "core" → "development"
   ```
   - Update all 63 task.phase references?
   - Update phase history?
   - Atomic operation required

3. **Case sensitivity**
   ```
   Existing: phase="core"
   New: phase="Core"
   ```
   - Schema uses pattern ^[a-z][a-z0-9-]*$ (lowercase only)
   - Prevents case issues
   - But rename could create duplicates if not careful

### Mitigation Strategies
```
DELETE PROTECTION
- Block deletion if tasks reference phase
- Require --force flag + task reassignment
  ct phase delete core --reassign-to development
- Interactive workflow:
  1. Show tasks affected
  2. Prompt for reassignment phase
  3. Update all tasks atomically
  4. Remove phase definition

RENAME OPERATION
- ct phase rename core development
- Atomic multi-step:
  1. Create new phase definition
  2. Update all task.phase references
  3. Update phase history
  4. Remove old phase definition
  5. Checksum verification
- Rollback if any step fails

PHASE DEPRECATION
- Add phase.deprecated: true flag
- Deprecated phases hidden from new task assignment
- Existing tasks keep deprecated phase
- Warning when working on deprecated phase tasks
- Prevents accidental usage without data loss
```

**Recommendation**: Implement rename command with atomic updates. Block deletion if tasks exist unless `--force --reassign-to <phase>` provided.

---

## Scenario 8: TodoWrite Sync with Phase Mismatches

### Risk Level: **MEDIUM** (Sync integrity)

### Context
TodoWrite sync injects tasks at session start, extracts changes at session end. Phase information must round-trip correctly.

### Edge Cases
1. **Injection phase filtering**
   ```
   Before injection:
     project.currentPhase: "core"
     Tasks: T001(setup), T050(core, focused), T099(polish)

   Current behavior:
     Tier 3: "Other high-priority tasks in same phase"
     → Injects only core + focused tasks

   Question: Should project.currentPhase influence injection?
   ```

2. **Extraction with new tasks**
   ```
   TodoWrite session creates: "Add user authentication"
   No [T###] prefix → new task
   What phase to assign?
     A) project.currentPhase (core)
     B) defaults.phase from config (core)
     C) focused task's phase
     D) null (no phase)
   ```

3. **Phase change during session**
   ```
   Session start: project.currentPhase = "core"
   User manually: ct phase set polish  # Outside TodoWrite session
   Session end: Extract tasks

   Risk: Injected tasks were core-phase, now project is polish
   ```

### Mitigation Strategies
```
INJECTION
- Current: Uses focused task's phase for tier 3
- No change needed: Project phase doesn't exist yet
- Future: If project phase exists, document in injection header
  {
    "_meta": {
      "injectedPhase": "core",
      "injectedAt": "..."
    }
  }

EXTRACTION
- New tasks without prefix get:
  1. defaults.phase from config (current: "core")
  2. Warning if different from focused task phase
  3. User can override with --default-phase flag
     ct sync --extract --default-phase polish

PHASE CHANGE DETECTION
- Save project.currentPhase in injection state file
- On extraction, compare:
  - If changed: Warn user
  - Option to update extracted task phases
- Interactive: "Project phase changed from 'core' to 'polish'. Update extracted tasks? [y/N]"
```

**Recommendation**:
1. Injection: Save project phase in state file for reference
2. Extraction: New tasks use `defaults.phase`, warn if project phase changed
3. Add `sync --extract --default-phase <phase>` override

---

## Scenario 9: Archive Interaction with Phase History

### Risk Level: **LOW-MEDIUM** (Audit trail integrity)

### Context
Archiving moves completed tasks to `todo-archive.json`. Phase information must be preserved for historical analysis.

### Edge Cases
1. **Phase completion metrics**
   ```
   Question: When did we complete the "setup" phase?
   Data needed:
     - Last task in setup phase completion date
     - All setup tasks archived

   Current: Archive preserves task.phase, but no phase timeline
   ```

2. **Orphaned phase definitions**
   ```
   All tasks in "setup" phase archived
   phases.setup still defined in todo.json

   Should setup be removed?
   Should it be marked "completed"?
   ```

3. **Phase analytics across archive boundary**
   ```
   Query: How many tasks were in core phase total?
   Current: Must check both todo.json AND todo-archive.json

   Risk: Incomplete analytics if archive not checked
   ```

### Mitigation Strategies
```
PRESERVE PHASE HISTORY IN ARCHIVE
- Archive structure includes phase summary:
  {
    "archivedTasks": [...],
    "phaseSummary": {
      "setup": {
        "totalTasks": 14,
        "archivedCount": 14,
        "firstCompleted": "2025-12-01T...",
        "lastCompleted": "2025-12-05T..."
      }
    }
  }

PHASE LIFECYCLE TRACKING
- Add to project.phaseHistory:
  {
    "phase": "setup",
    "startedAt": "2025-12-01T10:00:00Z",
    "completedAt": "2025-12-05T18:30:00Z",
    "taskCount": 14,
    "archived": true  // Set when all tasks archived
  }

ANALYTICS COMMANDS
- ct stats --include-archive
- ct phases --historical
  Shows completed phases from history
- ct show setup --archived
  Retrieves archived tasks from specific phase
```

**Recommendation**: Add `project.phaseHistory` array to track phase lifecycle. Archive command updates phase completion metadata. Stats commands support `--include-archive` flag.

---

## Scenario 10: Multi-User/Concurrent Access

### Risk Level: **HIGH** (If supported), **N/A** (Current design)

### Context
Current claude-todo design: Single-user, local filesystem. BUT edge cases exist:
- Multiple terminal sessions
- Synced folders (Dropbox, Google Drive)
- Future: Team features

### Edge Cases
1. **Race condition on phase change**
   ```
   User A: ct phase set core
   User B: ct phase set polish
   Both execute simultaneously

   Result: Last write wins, no conflict detection
   ```

2. **Checksum conflicts**
   ```
   User A: Reads tasks, checksum = abc123
   User B: Updates project phase, checksum = def456
   User A: Writes task update with checksum = abc123

   Result: Checksum mismatch, operation fails (GOOD)
   ```

3. **Focus conflicts**
   ```
   User A: ct focus set T050 (core phase)
   User B: ct focus set T099 (polish phase)
   project.currentPhase: core

   Result: Only one focus allowed, but which user wins?
   ```

### Mitigation Strategies
```
CURRENT PROTECTION (file locking)
- Scripts use flock for atomic operations
- Prevents corruption from concurrent writes
- BUT: Last write wins, no merge logic

PHASE-SPECIFIC LOCKING
- Separate lock file for project-level changes
- .claude/.phase.lock
- Hold during phase advancement operations
- Timeout after 5 seconds

CONFLICT DETECTION
- Checksum verification catches most conflicts
- Add project._meta.phaseVersion counter
- Increment on phase changes
- Compare before write

MULTI-USER DESIGN (future)
- Operation log instead of direct file edits
- Conflict resolution strategy (OT, CRDT)
- Out of scope for current implementation
```

**Recommendation**: Current locking + checksum is sufficient for single-user. Document multi-user as unsupported. If needed later, implement operation log with conflict resolution.

---

## Summary of Recommendations

| Scenario | Risk | Recommended Approach |
|----------|------|---------------------|
| 1. No project phase set | LOW | Optional project phase, smart defaults from activity |
| 2. Task phase ≠ project phase | MEDIUM | Permissive mode with optional warnings |
| 3. Tasks with no phase | LOW-MED | Treat as phase-agnostic, show in all views |
| 4. Phase advance incomplete | MED-HIGH | Hybrid: threshold + critical task blocking + prompt |
| 5. Multiple active phases | HIGH | Prevention via locking + validation detection |
| 6. Phase rollback | MEDIUM | Allow with explicit flag + warning + history log |
| 7. Delete/rename phases | HIGH | Atomic rename command, protected deletion |
| 8. TodoWrite sync mismatches | MEDIUM | Save phase in state, warn on change, override flag |
| 9. Archive + phase history | LOW-MED | Track phase lifecycle in project.phaseHistory |
| 10. Concurrent access | HIGH/N/A | Current locking sufficient for single-user |

---

## Implementation Priority (If Proceeding)

### Phase 1: Core Infrastructure (Required)
- [ ] Schema: Add `project.currentPhase` field
- [ ] Schema: Add `project.phaseHistory` array
- [ ] Validation: Single active phase check
- [ ] Commands: `ct phase set <phase>`, `ct phase show`

### Phase 2: Safety & Validation (Critical)
- [ ] Phase advance warnings (incomplete tasks)
- [ ] Phase deletion protection
- [ ] Rename command with atomic updates
- [ ] Checksum + locking for phase operations

### Phase 3: UX & Integration (Important)
- [ ] TodoWrite sync phase preservation
- [ ] Archive phase history tracking
- [ ] Dashboard phase context display
- [ ] Phaseless task handling

### Phase 4: Advanced Features (Optional)
- [ ] Phase rollback support
- [ ] Phase analytics (completion times, task distribution)
- [ ] Configurable enforcement modes (strict/permissive)
- [ ] Phase-based task filtering in list/next commands

---

## Open Questions for User

1. **Primary use case**: What problem does project-level phase solve?
   - Progress tracking/visualization?
   - Context management (what phase am I in)?
   - Workflow enforcement (can't skip phases)?
   - Reporting/analytics?

2. **Workflow model**: Linear (setup→core→polish) or non-linear?
   - Allow rollback?
   - Allow skipping phases?
   - Support parallel phases?

3. **Enforcement level**: Strict or permissive?
   - Block operations outside current phase?
   - Warn but allow?
   - Purely informational?

4. **Migration**: How to handle existing 143 tasks?
   - Auto-assign project phase based on most common task phase (core)?
   - Leave project phase unset?
   - Interactive phase selection on first `ct dash`?

---

## Test Coverage Needed

If implementing, these test scenarios are critical:

```bash
# Scenario 1: No phase set
ct init
ct dash  # Should work without error

# Scenario 2: Phase mismatch
ct phase set core
ct add "Task" --phase polish
ct focus set T001  # Should work, maybe warn

# Scenario 3: Phaseless tasks
ct add "Quick fix" --no-phase
ct list  # Should show phaseless tasks

# Scenario 4: Advance with incomplete
ct phase advance  # Should prompt about 8 pending tasks

# Scenario 5: Multi-active detection
# (Manual corruption test)
ct validate  # Should detect and report

# Scenario 6: Rollback
ct phase set setup --rollback
# Should update history, warn user

# Scenario 7: Rename
ct phase rename core development
ct list --phase development  # All 63 tasks should appear

# Scenario 8: Sync
ct sync --inject
# (Create new task in TodoWrite without [T###])
ct sync --extract
# New task should get defaults.phase

# Scenario 9: Archive history
ct archive --all
# Check project.phaseHistory updated

# Scenario 10: Concurrent access
# (Spawn parallel ct phase set commands)
ct validate  # Should verify integrity
```

---

## Conclusion

Project-level phase enhancement is **feasible but requires careful design** to avoid:
1. Breaking existing workflows (143 tasks, 69% with phases)
2. Creating rigid phase enforcement that frustrates users
3. Orphaning phaseless tasks or creating sync issues
4. Data integrity violations from concurrent access

**Recommended approach**: Incremental rollout
1. Start with optional, informational project phase
2. Add validation and warnings
3. Enhance with enforcement options (configurable)
4. Integrate with TodoWrite sync, archive, analytics

**Estimated scope**: Medium complexity
- Schema changes: 2 fields + validation logic
- Commands: 3-5 new commands + modifications to existing
- Tests: 20+ new test cases across scenarios
- Documentation: Update 8+ doc files

**Biggest risks**: Scenarios 4 (phase advance logic), 5 (multi-active detection), 7 (rename atomicity), 8 (sync integration)

---

**Next Steps**: Review scenarios with user, prioritize use cases, decide on enforcement model before implementation.
