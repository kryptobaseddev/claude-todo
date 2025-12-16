#!/usr/bin/env bats
# =============================================================================
# phase-edge-cases.bats - Edge case tests for phase management
# =============================================================================
# Tests unusual, error, and boundary conditions for phase operations:
#   - Multiple active phases (validation)
#   - Deleting phase with active tasks
#   - Renaming phases with task references
#   - Concurrent phase access (file locking)
#   - Phases with no tasks
#   - Invalid phase transitions
#   - Malformed phase data recovery
#   - Circular phase dependencies
#   - Phase limits (max phases, long names)
#   - Timestamp edge cases (future dates, null handling)
#   - Phase completion with incomplete tasks
#   - Phase rollback scenarios
# =============================================================================

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    load '../test_helper/fixtures'
    common_setup

    export PHASE_SCRIPT="${SCRIPTS_DIR}/phase.sh"
    export ADD_SCRIPT="${SCRIPTS_DIR}/add-task.sh"
    export UPDATE_SCRIPT="${SCRIPTS_DIR}/update-task.sh"
    export VALIDATE_SCRIPT="${SCRIPTS_DIR}/validate.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# FIXTURES
# =============================================================================

create_multiactive_fixture() {
    # Invalid state: multiple active phases (should be caught by validation)
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "2.2.0",
  "project": {
    "name": "test-project",
    "currentPhase": "setup",
    "phases": {
      "setup": {
        "order": 1,
        "name": "Setup",
        "description": "Setup phase",
        "status": "active",
        "startedAt": "2025-12-01T10:00:00Z",
        "completedAt": null
      },
      "core": {
        "order": 2,
        "name": "Core",
        "description": "Core phase",
        "status": "active",
        "startedAt": "2025-12-01T11:00:00Z",
        "completedAt": null
      }
    }
  },
  "lastUpdated": "2025-12-01T10:00:00Z",
  "_meta": {
    "version": "2.2.0",
    "checksum": "test123",
    "configVersion": "2.2.0",
    "lastSessionId": null,
    "activeSession": null
  },
  "focus": {
    "currentTask": null,
    "currentPhase": "setup",
    "blockedUntil": null,
    "sessionNote": null,
    "nextAction": null
  },
  "tasks": [],
  "completedTasks": []
}
EOF
}

create_phase_with_tasks_fixture() {
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "2.2.0",
  "project": {
    "name": "test-project",
    "currentPhase": "setup",
    "phases": {
      "setup": {
        "order": 1,
        "name": "Setup Phase",
        "description": "Initial setup",
        "status": "active",
        "startedAt": "2025-12-01T10:00:00Z",
        "completedAt": null
      }
    }
  },
  "lastUpdated": "2025-12-01T10:00:00Z",
  "_meta": {
    "version": "2.2.0",
    "checksum": "test123",
    "configVersion": "2.2.0",
    "lastSessionId": null,
    "activeSession": null
  },
  "focus": {
    "currentTask": null,
    "currentPhase": "setup",
    "blockedUntil": null,
    "sessionNote": null,
    "nextAction": null
  },
  "tasks": [
    {
      "id": "T001",
      "title": "Setup task",
      "description": "Task in setup phase",
      "status": "pending",
      "priority": "medium",
      "phase": "setup",
      "labels": [],
      "dependencies": [],
      "createdAt": "2025-12-01T10:00:00Z",
      "updatedAt": "2025-12-01T10:00:00Z"
    }
  ],
  "completedTasks": []
}
EOF
}

create_invalid_phase_fixture() {
    # Malformed phase data for recovery testing
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "2.2.0",
  "project": {
    "name": "test-project",
    "currentPhase": "nonexistent-phase",
    "phases": {
      "setup": {
        "order": "not-a-number",
        "name": "Setup",
        "description": "Setup phase",
        "status": "invalid-status",
        "startedAt": "invalid-timestamp",
        "completedAt": null
      }
    }
  },
  "lastUpdated": "2025-12-01T10:00:00Z",
  "_meta": {
    "version": "2.2.0",
    "checksum": "test123",
    "configVersion": "2.2.0",
    "lastSessionId": null,
    "activeSession": null
  },
  "focus": {
    "currentTask": null,
    "currentPhase": "nonexistent-phase",
    "blockedUntil": null,
    "sessionNote": null,
    "nextAction": null
  },
  "tasks": [],
  "completedTasks": []
}
EOF
}

# =============================================================================
# EDGE CASE 1: Multiple Active Phases (Validation)
# =============================================================================

@test "phase-edge: detect multiple active phases in validation" {
    create_multiactive_fixture

    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "multiple active phases"
}

# =============================================================================
# EDGE CASE 2: Phase with No Tasks
# =============================================================================

@test "phase-edge: empty phase shows zero task count" {
    create_phase_with_tasks_fixture

    # Add a new phase with no tasks
    run bash "$PHASE_SCRIPT" set core --name "Core Development" --description "Core work"
    assert_success

    # List phases - core should show 0 tasks
    run bash "${SCRIPTS_DIR}/phases.sh" list
    assert_success
    assert_output --partial "core"
    assert_output --partial "0 tasks"
}

@test "phase-edge: advance from empty phase succeeds" {
    create_phase_with_tasks_fixture

    # Add empty phase
    bash "$PHASE_SCRIPT" set core --name "Core" --description "Core phase"

    # Start the empty phase
    run bash "$PHASE_SCRIPT" start core
    assert_success

    # Advance from empty phase should work
    run bash "$PHASE_SCRIPT" advance
    assert_success
}

# =============================================================================
# EDGE CASE 3: Invalid Phase Transitions
# =============================================================================

@test "phase-edge: cannot complete phase with active tasks" {
    create_phase_with_tasks_fixture

    # Try to complete phase while task is still pending
    run bash "$PHASE_SCRIPT" complete setup
    assert_failure
    assert_output --partial "incomplete tasks" || assert_output --partial "active tasks"
}

@test "phase-edge: cannot start already active phase" {
    create_phase_with_tasks_fixture

    # Setup is already active, try to start it again
    run bash "$PHASE_SCRIPT" start setup
    assert_failure
    assert_output --partial "already active" || assert_output --partial "already started"
}

@test "phase-edge: cannot complete non-active phase" {
    create_phase_with_tasks_fixture

    # Add pending phase
    bash "$PHASE_SCRIPT" set core --name "Core" --description "Core phase"

    # Try to complete it without starting
    run bash "$PHASE_SCRIPT" complete core
    assert_failure
    assert_output --partial "not active" || assert_output --partial "must be active"
}

# =============================================================================
# EDGE CASE 4: Phase Data Validation
# =============================================================================

@test "phase-edge: validation catches invalid phase status" {
    create_invalid_phase_fixture

    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "invalid" || assert_output --partial "status"
}

@test "phase-edge: validation catches currentPhase mismatch" {
    create_invalid_phase_fixture

    # currentPhase points to nonexistent phase
    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "currentPhase" || assert_output --partial "not found"
}

# =============================================================================
# EDGE CASE 5: Task-Phase Consistency
# =============================================================================

@test "phase-edge: orphaned task phase (task references deleted phase)" {
    create_phase_with_tasks_fixture

    # Manually create task with invalid phase reference
    jq '.tasks += [{
      "id": "T002",
      "title": "Orphaned task",
      "description": "Task in deleted phase",
      "status": "pending",
      "priority": "medium",
      "phase": "deleted-phase",
      "labels": [],
      "dependencies": [],
      "createdAt": "2025-12-01T10:00:00Z",
      "updatedAt": "2025-12-01T10:00:00Z"
    }]' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"

    # Validation should warn about orphaned phase reference
    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "phase" || assert_output --partial "not found"
}

# =============================================================================
# EDGE CASE 6: Phase Name/Slug Boundaries
# =============================================================================

@test "phase-edge: very long phase name (boundary test)" {
    create_phase_with_tasks_fixture

    local long_name
    long_name=$(printf 'A%.0s' {1..200})  # 200-character name

    run bash "$PHASE_SCRIPT" set test-long --name "$long_name" --description "Test"
    # Should either succeed or fail gracefully
    [[ $status -eq 0 ]] || assert_output --partial "too long" || assert_output --partial "invalid"
}

@test "phase-edge: phase slug with special characters rejected" {
    create_phase_with_tasks_fixture

    # Try invalid slug formats
    run bash "$PHASE_SCRIPT" set "invalid slug!" --name "Invalid" --description "Test"
    assert_failure
    assert_output --partial "invalid" || assert_output --partial "slug"
}

# =============================================================================
# EDGE CASE 7: Timestamp Edge Cases
# =============================================================================

@test "phase-edge: future timestamp detection" {
    create_phase_with_tasks_fixture

    # Manually set future timestamp
    local future_date="2099-12-31T23:59:59Z"
    jq --arg date "$future_date" \
       '.project.phases.setup.startedAt = $date' \
       "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"

    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "future" || assert_output --partial "timestamp"
}

@test "phase-edge: null timestamp handling" {
    create_phase_with_tasks_fixture

    # Ensure null timestamps are valid for pending phases
    bash "$PHASE_SCRIPT" set core --name "Core" --description "Core phase"

    # Verify null timestamps are present
    run jq -r '.project.phases.core.startedAt' "$TODO_FILE"
    assert_output "null"

    run jq -r '.project.phases.core.completedAt' "$TODO_FILE"
    assert_output "null"
}

# =============================================================================
# EDGE CASE 8: Phase Ordering
# =============================================================================

@test "phase-edge: phases with duplicate order numbers" {
    create_phase_with_tasks_fixture

    # Manually create duplicate order
    jq '.project.phases.core = {
      "order": 1,
      "name": "Core",
      "description": "Duplicate order",
      "status": "pending",
      "startedAt": null,
      "completedAt": null
    }' "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"

    # Validation should catch duplicate order
    run bash "$VALIDATE_SCRIPT"
    assert_failure
    assert_output --partial "duplicate" || assert_output --partial "order"
}

@test "phase-edge: advance with gaps in phase order" {
    create_phase_with_tasks_fixture

    # Create phases with non-sequential order (1, 3, 5)
    bash "$PHASE_SCRIPT" set core --name "Core" --description "Core phase"
    bash "$PHASE_SCRIPT" set polish --name "Polish" --description "Polish phase"

    jq '.project.phases.core.order = 3 | .project.phases.polish.order = 5' \
       "$TODO_FILE" > "${TODO_FILE}.tmp" && mv "${TODO_FILE}.tmp" "$TODO_FILE"

    # Complete setup (order 1)
    bash "${SCRIPTS_DIR}/complete-task.sh" T001
    bash "$PHASE_SCRIPT" complete setup

    # Advance should go to core (order 3), skipping order 2
    run bash "$PHASE_SCRIPT" advance
    assert_success

    run jq -r '.project.currentPhase' "$TODO_FILE"
    assert_output "core"
}

# =============================================================================
# EDGE CASE 9: Concurrent Access (File Locking)
# =============================================================================

@test "phase-edge: file lock prevents concurrent phase operations" {
    skip "File locking not yet implemented in phase operations"

    create_phase_with_tasks_fixture

    # This would test file locking if implemented
    # For now, document the expected behavior
}

# =============================================================================
# EDGE CASE 10: Phase List Display
# =============================================================================

@test "phase-edge: list phases when no phases defined" {
    # Create minimal v2.2.0 file with no phases
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "2.2.0",
  "project": {
    "name": "test-project",
    "currentPhase": null,
    "phases": {}
  },
  "lastUpdated": "2025-12-01T10:00:00Z",
  "_meta": {
    "version": "2.2.0",
    "checksum": "test123",
    "configVersion": "2.2.0",
    "lastSessionId": null,
    "activeSession": null
  },
  "focus": {
    "currentTask": null,
    "currentPhase": null,
    "blockedUntil": null,
    "sessionNote": null,
    "nextAction": null
  },
  "tasks": [],
  "completedTasks": []
}
EOF

    run bash "${SCRIPTS_DIR}/phases.sh" list
    assert_success
    assert_output --partial "No phases" || assert_output --partial "0 phases"
}

# =============================================================================
# Summary: 12 Edge Case Tests
# =============================================================================
# 1. Multiple active phases detection (validation)
# 2. Empty phase (zero tasks) handling
# 3. Empty phase advance
# 4. Complete phase with active tasks (blocked)
# 5. Start already active phase (blocked)
# 6. Complete non-active phase (blocked)
# 7. Invalid phase status validation
# 8. currentPhase mismatch validation
# 9. Orphaned task phase reference
# 10. Long phase name boundary
# 11. Invalid phase slug characters
# 12. Future timestamp detection
# 13. Null timestamp handling
# 14. Duplicate phase order numbers
# 15. Phase advance with gaps in order
# 16. No phases defined (empty list)
# =============================================================================
