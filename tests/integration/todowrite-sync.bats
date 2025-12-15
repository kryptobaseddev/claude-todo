#!/usr/bin/env bats
# =============================================================================
# todowrite-sync.bats - Integration tests for TodoWrite bidirectional sync
# =============================================================================
# Tests the sync mechanism between claude-todo (persistent) and TodoWrite
# (ephemeral session tracking).
#
# Design Reference: T227 research in Serena memory: todowrite-sync-research.md
#
# Key behaviors tested:
#   1. Injection: claude-todo tasks → TodoWrite format
#   2. Extraction: TodoWrite state → claude-todo updates
#   3. ID round-tripping via [T###] prefix
#   4. Status mapping (blocked → pending with prefix)
#   5. Conflict resolution
# =============================================================================

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    load '../test_helper/fixtures'
    common_setup

    # Additional sync-specific setup
    export SYNC_SCRIPT="${SCRIPTS_DIR}/sync-todowrite.sh"
    export INJECT_SCRIPT="${SCRIPTS_DIR}/inject-todowrite.sh"
    export EXTRACT_SCRIPT="${SCRIPTS_DIR}/extract-todowrite.sh"
    export SYNC_STATE_FILE="${TEST_TEMP_DIR}/.claude/sync/todowrite-session.json"

    # Create sync directory
    mkdir -p "${TEST_TEMP_DIR}/.claude/sync"
}

teardown() {
    common_teardown
}

# =============================================================================
# FIXTURES
# =============================================================================

create_sync_test_fixture() {
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "2.1.0",
  "project": "todowrite-sync-test",
  "_meta": {
    "version": "2.1.0",
    "checksum": "test123",
    "activeSession": "session_test_001"
  },
  "lastUpdated": "2025-12-15T14:00:00Z",
  "tasks": [
    {
      "id": "T001",
      "title": "High priority task",
      "description": "This is a high priority task for testing",
      "status": "active",
      "priority": "high",
      "phase": "core",
      "createdAt": "2025-12-15T10:00:00Z"
    },
    {
      "id": "T002",
      "title": "Blocked task",
      "description": "This task is blocked by something",
      "status": "blocked",
      "priority": "medium",
      "blockedBy": "Waiting for API access",
      "createdAt": "2025-12-15T10:00:00Z"
    },
    {
      "id": "T003",
      "title": "Pending low priority",
      "description": "Low priority pending task",
      "status": "pending",
      "priority": "low",
      "createdAt": "2025-12-15T10:00:00Z"
    },
    {
      "id": "T004",
      "title": "Already completed",
      "description": "This was already done",
      "status": "done",
      "priority": "medium",
      "createdAt": "2025-12-14T10:00:00Z",
      "completedAt": "2025-12-14T15:00:00Z"
    }
  ],
  "focus": {
    "taskId": "T001",
    "setAt": "2025-12-15T14:00:00Z"
  }
}
EOF
}

create_todowrite_state_fixture() {
    # Simulates state after Claude has used TodoWrite during session
    cat > "${TEST_TEMP_DIR}/todowrite-state.json" << 'EOF'
{
  "todos": [
    {
      "content": "[T001] [!] High priority task",
      "status": "completed",
      "activeForm": "Working on high priority task"
    },
    {
      "content": "[T002] [BLOCKED] Blocked task",
      "status": "in_progress",
      "activeForm": "Unblocking blocked task"
    },
    {
      "content": "New task created in session",
      "status": "pending",
      "activeForm": "Creating new task"
    }
  ]
}
EOF
}

# =============================================================================
# INJECTION TESTS (claude-todo → TodoWrite format)
# =============================================================================

@test "inject: generates TodoWrite JSON from focused task" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    # Should output valid JSON
    echo "$output" | jq . > /dev/null
    assert_success

    # Should contain focused task with ID prefix
    assert_output --partial '[T001]'
    assert_output --partial 'High priority task'
}

@test "inject: adds [!] prefix for high/critical priority" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    # High priority task should have [!] marker
    assert_output --partial '[T001] [!]'
}

@test "inject: maps blocked status to pending with [BLOCKED] prefix" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    # Blocked task should be pending with prefix
    local blocked_item
    blocked_item=$(echo "$output" | jq '.todos[] | select(.content | contains("T002"))')

    echo "$blocked_item" | jq -e '.status == "pending"'
    assert_success

    echo "$blocked_item" | jq -e '.content | contains("[BLOCKED]")'
    assert_success
}

@test "inject: generates activeForm from title" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    # Should have activeForm field
    echo "$output" | jq -e '.todos[0].activeForm != null'
    assert_success
}

@test "inject: respects tiered selection (max 8 tasks)" {
    # Create fixture with many tasks
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --max-tasks 8 --quiet
    assert_success

    local count
    count=$(echo "$output" | jq '.todos | length')
    [[ "$count" -le 8 ]]
}

@test "inject: excludes already-completed tasks" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT"
    assert_success

    # T004 is done, should not be injected
    refute_output --partial 'T004'
}

@test "inject: creates session state file for round-trip" {
    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    # Should create session state file
    assert_file_exists "$SYNC_STATE_FILE"

    # Should record injected task IDs
    jq -e '.injected_tasks | length > 0' "$SYNC_STATE_FILE"
    assert_success
}

# =============================================================================
# EXTRACTION TESTS (TodoWrite state → claude-todo)
# =============================================================================

@test "extract: parses [T###] prefix to recover task IDs" {
    create_sync_test_fixture
    create_todowrite_state_fixture

    # First inject to create session state
    bash "$INJECT_SCRIPT" --quiet > /dev/null

    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # Should detect T001 was completed
    assert_output --partial 'T001'
    assert_output --partial 'Completed'
}

@test "extract: marks completed tasks as done in claude-todo" {
    
    create_sync_test_fixture
    create_todowrite_state_fixture

    bash "$INJECT_SCRIPT" > /dev/null
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # T001 should now be done in todo.json
    local status
    status=$(jq -r '.tasks[] | select(.id == "T001") | .status' "$TODO_FILE")
    [[ "$status" == "done" ]]
}

@test "extract: creates new tasks for items without ID prefix" {
    
    create_sync_test_fixture
    create_todowrite_state_fixture

    bash "$INJECT_SCRIPT" > /dev/null
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # Should create new task for "New task created in session"
    jq -e '.tasks[] | select(.title | contains("New task created"))' "$TODO_FILE"
    assert_success

    # New task should have session-created label
    jq -e '.tasks[] | select(.title | contains("New task created")) | .labels | contains(["session-created"])' "$TODO_FILE"
    assert_success
}

@test "extract: updates progress for in_progress items" {
    
    create_sync_test_fixture
    create_todowrite_state_fixture

    bash "$INJECT_SCRIPT" > /dev/null
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # T002 was blocked, now in_progress - should update status
    local status
    status=$(jq -r '.tasks[] | select(.id == "T002") | .status' "$TODO_FILE")
    [[ "$status" == "active" ]]
}

@test "extract: logs removed items without deleting" {
    
    create_sync_test_fixture

    # Inject with T003 included
    bash "$INJECT_SCRIPT" > /dev/null

    # Create state without T003 (user removed from focus)
    cat > "${TEST_TEMP_DIR}/todowrite-state.json" << 'EOF'
{
  "todos": [
    {"content": "[T001] [!] High priority task", "status": "in_progress", "activeForm": "Working"}
  ]
}
EOF

    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # T003 should still exist in todo.json (not deleted)
    jq -e '.tasks[] | select(.id == "T003")' "$TODO_FILE"
    assert_success

    # Should log that T003 was removed from session
    assert_output --partial 'removed'
}

# =============================================================================
# CONFLICT RESOLUTION TESTS
# =============================================================================

@test "conflict: claude-todo authoritative for existence" {
    
    create_sync_test_fixture

    # Inject
    bash "$INJECT_SCRIPT" > /dev/null

    # Simulate T001 deleted from claude-todo during session
    jq 'del(.tasks[] | select(.id == "T001"))' "$TODO_FILE" > "${TODO_FILE}.tmp"
    mv "${TODO_FILE}.tmp" "$TODO_FILE"

    # Try to extract with T001 completed in TodoWrite
    create_todowrite_state_fixture

    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"

    # Should warn but not fail
    assert_success
    assert_output --partial 'WARN'
    assert_output --partial 'T001'
}

@test "conflict: already-done task stays done (idempotent)" {
    
    create_sync_test_fixture

    # Mark T001 as done before extraction
    jq '(.tasks[] | select(.id == "T001")).status = "done"' "$TODO_FILE" > "${TODO_FILE}.tmp"
    mv "${TODO_FILE}.tmp" "$TODO_FILE"

    bash "$INJECT_SCRIPT" > /dev/null
    create_todowrite_state_fixture  # Has T001 as completed

    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # Should be idempotent - no error
    refute_output --partial 'error'
}

# =============================================================================
# FULL WORKFLOW TESTS
# =============================================================================

@test "workflow: complete inject-session-extract cycle" {

    create_sync_test_fixture

    # 1. Inject (use --quiet to get clean JSON)
    run bash "$INJECT_SCRIPT" --quiet
    assert_success
    local injected="$output"

    # 2. Verify session state created
    assert_file_exists "$SYNC_STATE_FILE"

    # 3. Simulate session work (complete T001, add new task)
    echo "$injected" | jq '
      .todos[0].status = "completed" |
      .todos += [{"content": "Session task", "status": "pending", "activeForm": "Working"}]
    ' > "${TEST_TEMP_DIR}/todowrite-state.json"

    # 4. Extract
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # 5. Verify T001 is done
    local t001_status
    t001_status=$(jq -r '.tasks[] | select(.id == "T001") | .status' "$TODO_FILE")
    [[ "$t001_status" == "done" ]]

    # 6. Verify new task was created
    jq -e '.tasks[] | select(.title == "Session task")' "$TODO_FILE"
    assert_success
}

@test "workflow: sync command orchestrates full cycle" {
    
    create_sync_test_fixture

    # sync --inject should call inject script
    run bash "$SYNC_SCRIPT" --inject
    assert_success
    assert_file_exists "$SYNC_STATE_FILE"

    # Simulate session work
    create_todowrite_state_fixture

    # sync --extract should call extract script
    run bash "$SYNC_SCRIPT" --extract "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success
}

# =============================================================================
# STATUS MAPPING TESTS
# =============================================================================

@test "status: pending → pending" {

    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    local pending_item
    pending_item=$(echo "$output" | jq '.todos[] | select(.content | contains("T003"))')
    echo "$pending_item" | jq -e '.status == "pending"'
    assert_success
}

@test "status: active → in_progress" {

    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    local active_item
    active_item=$(echo "$output" | jq '.todos[] | select(.content | contains("T001"))')
    echo "$active_item" | jq -e '.status == "in_progress"'
    assert_success
}

@test "status: blocked → pending (with prefix)" {

    create_sync_test_fixture

    run bash "$INJECT_SCRIPT" --quiet
    assert_success

    local blocked_item
    blocked_item=$(echo "$output" | jq '.todos[] | select(.content | contains("T002"))')
    echo "$blocked_item" | jq -e '.status == "pending"'
    assert_success
    echo "$blocked_item" | jq -e '.content | contains("[BLOCKED]")'
    assert_success
}

@test "status: in_progress → active (on extract)" {
    
    create_sync_test_fixture
    create_todowrite_state_fixture

    bash "$INJECT_SCRIPT" > /dev/null
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # T002 was in_progress in TodoWrite, should become active
    local status
    status=$(jq -r '.tasks[] | select(.id == "T002") | .status' "$TODO_FILE")
    [[ "$status" == "active" ]]
}

@test "status: completed → done (on extract)" {
    
    create_sync_test_fixture
    create_todowrite_state_fixture

    bash "$INJECT_SCRIPT" > /dev/null
    run bash "$EXTRACT_SCRIPT" "${TEST_TEMP_DIR}/todowrite-state.json"
    assert_success

    # T001 was completed in TodoWrite, should become done
    local status
    status=$(jq -r '.tasks[] | select(.id == "T001") | .status' "$TODO_FILE")
    [[ "$status" == "done" ]]
}
