#!/usr/bin/env bats
# hierarchy-automation.bats - Integration tests for Hierarchy Phase 2
# Tests: T340 (auto-complete), T341 (orphan detection), T342 (tree command)

# Load test helpers
setup_file() {
    load '../test_helper/common_setup'
    common_setup_file
}

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/fixtures'
    load '../test_helper/assertions'
    common_setup_per_test

    # Create empty todo.json file for the tests
    create_empty_todo
}

teardown() {
    common_teardown_per_test
}

teardown_file() {
    common_teardown_file
}

# =============================================================================
# Parent Auto-Complete Integration Tests (T340)
# =============================================================================

@test "integration: completing all children auto-completes parent epic" {
    # Create epic with 3 children
    local epic_id=$(bash "$ADD_SCRIPT" "Feature Epic" --type epic -q)
    local t1=$(bash "$ADD_SCRIPT" "Task 1" --parent "$epic_id" -q)
    local t2=$(bash "$ADD_SCRIPT" "Task 2" --parent "$epic_id" -q)
    local t3=$(bash "$ADD_SCRIPT" "Task 3" --parent "$epic_id" -q)

    # Enable auto-complete
    jq '.hierarchy.autoCompleteParent = true | .hierarchy.autoCompleteMode = "auto"' "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"

    # Complete all children
    bash "$COMPLETE_SCRIPT" "$t1" --skip-notes
    bash "$COMPLETE_SCRIPT" "$t2" --skip-notes
    run bash "$COMPLETE_SCRIPT" "$t3" --skip-notes
    assert_success

    # Epic should be auto-completed
    local epic_status=$(jq -r --arg id "$epic_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
    [[ "$epic_status" == "done" ]]
}

@test "integration: nested hierarchy auto-completes correctly" {
    # Create: epic -> task -> subtask
    local epic=$(bash "$ADD_SCRIPT" "Epic" --type epic -q)
    local task=$(bash "$ADD_SCRIPT" "Task" --parent "$epic" -q)
    local subtask=$(bash "$ADD_SCRIPT" "Subtask" --parent "$task" --type subtask -q)

    jq '.hierarchy.autoCompleteParent = true | .hierarchy.autoCompleteMode = "auto"' "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"

    # Complete subtask - should auto-complete task, then epic
    run bash "$COMPLETE_SCRIPT" "$subtask" --skip-notes
    assert_success

    # Both task and epic should be done
    local task_status=$(jq -r --arg id "$task" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
    local epic_status=$(jq -r --arg id "$epic" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")

    [[ "$task_status" == "done" ]]
    [[ "$epic_status" == "done" ]]
}

@test "integration: auto-complete respects configuration modes" {
    # Test off mode - create fresh tasks
    local epic_off=$(bash "$ADD_SCRIPT" "Epic Off" --type epic -q)
    local task_off=$(bash "$ADD_SCRIPT" "Task Off" --parent "$epic_off" -q)

    jq '.hierarchy.autoCompleteParent = true | .hierarchy.autoCompleteMode = "off"' "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"
    bash "$COMPLETE_SCRIPT" "$task_off" --skip-notes
    
    local epic_status=$(jq -r --arg id "$epic_off" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
    [[ "$epic_status" != "done" ]]

    # Test auto mode - create fresh tasks
    local epic_auto=$(bash "$ADD_SCRIPT" "Epic Auto" --type epic -q)
    local task_auto=$(bash "$ADD_SCRIPT" "Task Auto" --parent "$epic_auto" -q)

    jq '.hierarchy.autoCompleteMode = "auto"' "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"
    run bash "$COMPLETE_SCRIPT" "$task_auto" --skip-notes
    assert_success
    
    epic_status=$(jq -r --arg id "$epic_auto" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
    [[ "$epic_status" == "done" ]]
}

# =============================================================================
# Orphan Detection Integration Tests (T341)
# =============================================================================

@test "integration: validate detects and fixes orphans" {
    # Create valid parent-child
    local parent=$(bash "$ADD_SCRIPT" "Parent" --type epic -q)
    local child=$(bash "$ADD_SCRIPT" "Child" --parent "$parent" -q)

    # Manually corrupt: set child's parentId to non-existent
    jq --arg id "$child" '.tasks |= map(if .id == $id then .parentId = "T999" else . end)' "$TODO_FILE" > tmp && mv tmp "$TODO_FILE"
    
    # Update checksum after manual modification
    local checksum=$(jq -c '.tasks' "$TODO_FILE" | sha256sum | cut -c1-16)
    jq --arg cs "$checksum" '._meta.checksum = $cs' "$TODO_FILE" > tmp && mv tmp "$TODO_FILE"

    # Validate should detect orphan
    run bash "$VALIDATE_SCRIPT" --check-orphans
    assert_output --partial "orphan"

    # Fix with unlink
    run bash "$VALIDATE_SCRIPT" --fix-orphans unlink
    assert_success

    # Child should now have null parentId
    local new_parent=$(jq -r --arg id "$child" '.tasks[] | select(.id == $id) | .parentId // "null"' "$TODO_FILE")
    [[ "$new_parent" == "null" ]]
}

@test "integration: orphan detection with delete mode" {
    local parent=$(bash "$ADD_SCRIPT" "Parent" --type epic -q)
    local child=$(bash "$ADD_SCRIPT" "Child" --parent "$parent" -q)

    # Corrupt parentId
    jq --arg id "$child" '.tasks |= map(if .id == $id then .parentId = "T999" else . end)' "$TODO_FILE" > tmp && mv tmp "$TODO_FILE"
    
    # Update checksum after manual modification
    local checksum=$(jq -c '.tasks' "$TODO_FILE" | sha256sum | cut -c1-16)
    jq --arg cs "$checksum" '._meta.checksum = $cs' "$TODO_FILE" > tmp && mv tmp "$TODO_FILE"

    # Fix with delete
    run bash "$VALIDATE_SCRIPT" --fix-orphans delete
    assert_success

    # Child should be deleted
    local child_exists=$(jq --arg id "$child" '.tasks | any(.id == $id)' "$TODO_FILE")
    [[ "$child_exists" == "false" ]]
}

# =============================================================================
# Tree Command Integration Tests (T342)
# =============================================================================

@test "integration: tree shows correct hierarchy" {
    local epic=$(bash "$ADD_SCRIPT" "Epic" --type epic -q)
    local task=$(bash "$ADD_SCRIPT" "Task" --parent "$epic" -q)
    local subtask=$(bash "$ADD_SCRIPT" "Subtask" --parent "$task" --type subtask -q)

    run bash "$LIST_SCRIPT" --tree
    assert_success
    assert_output --partial "Epic"
    assert_output --partial "Task"
    assert_output --partial "Subtask"
}

@test "integration: tree with root filter" {
    local epic1=$(bash "$ADD_SCRIPT" "Epic 1" --type epic -q)
    local epic2=$(bash "$ADD_SCRIPT" "Epic 2" --type epic -q)
    local task=$(bash "$ADD_SCRIPT" "Task" --parent "$epic1" -q)

    # Use regular list with parent filter to show children of epic1
    run bash "$LIST_SCRIPT" --parent "$epic1"
    assert_success
    assert_output --partial "Task"
    refute_output --partial "Epic 1"
    refute_output --partial "Epic 2"
}

@test "integration: tree with status filter" {
    local epic=$(bash "$ADD_SCRIPT" "Epic" --type epic -q)
    local task1=$(bash "$ADD_SCRIPT" "Task 1" --parent "$epic" -q)
    local task2=$(bash "$ADD_SCRIPT" "Task 2" --parent "$epic" -q)

    # Complete task1
    bash "$COMPLETE_SCRIPT" "$task1" --skip-notes

    run bash "$LIST_SCRIPT" --tree --status pending
    assert_success
    assert_output --partial "Epic"
    assert_output --partial "Task 2"
    refute_output --partial "Task 1"
}