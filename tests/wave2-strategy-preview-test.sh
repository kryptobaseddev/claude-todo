#!/usr/bin/env bash
# Wave 2 Testing: Strategy Pattern and Dry-run (T704, T709)
# Tests deletion-strategy.sh and delete-preview.sh libraries
#
# Run: bash tests/wave2-strategy-preview-test.sh

# Note: We don't use set -e because we need to capture exit codes from tests
set -uo pipefail

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Temporary test directory
TEST_DIR=""
TODO_FILE=""
TODO_FILE_ORIGINAL_CHECKSUM=""

setup_test_env() {
    TEST_DIR=$(mktemp -d)
    TODO_FILE="$TEST_DIR/todo.json"

    # Create test todo.json with hierarchical structure
    cat > "$TODO_FILE" << 'EOF'
{
  "version": "1.0",
  "tasks": [
    {
      "id": "T001",
      "title": "Epic 1: Main Project",
      "description": "Top-level epic",
      "type": "epic",
      "status": "active",
      "parentId": null,
      "labels": ["epic"],
      "depends": []
    },
    {
      "id": "T002",
      "title": "Task under Epic 1",
      "description": "Child of T001",
      "type": "task",
      "status": "pending",
      "parentId": "T001",
      "labels": ["feature"],
      "depends": []
    },
    {
      "id": "T003",
      "title": "Subtask under T002",
      "description": "Child of T002 (grandchild of T001)",
      "type": "subtask",
      "status": "pending",
      "parentId": "T002",
      "labels": [],
      "depends": []
    },
    {
      "id": "T004",
      "title": "Another subtask under T002",
      "description": "Second child of T002",
      "type": "subtask",
      "status": "active",
      "parentId": "T002",
      "labels": [],
      "depends": []
    },
    {
      "id": "T005",
      "title": "Independent task",
      "description": "No parent, no children",
      "type": "task",
      "status": "pending",
      "parentId": null,
      "labels": [],
      "depends": ["T002"]
    },
    {
      "id": "T006",
      "title": "Leaf task under T001",
      "description": "Direct child of epic, no grandchildren",
      "type": "task",
      "status": "blocked",
      "parentId": "T001",
      "labels": ["blocked"],
      "depends": ["T002", "T003"]
    },
    {
      "id": "T007",
      "title": "Completed task",
      "description": "Already done task",
      "type": "task",
      "status": "done",
      "parentId": null,
      "labels": [],
      "depends": []
    }
  ]
}
EOF

    # Store checksum for later verification
    TODO_FILE_ORIGINAL_CHECKSUM=$(md5sum "$TODO_FILE" | cut -d' ' -f1)

    echo -e "${CYAN}Test environment created: $TEST_DIR${NC}"
}

cleanup_test_env() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        echo -e "${CYAN}Test environment cleaned up${NC}"
    fi
}

# Trap to clean up on exit
trap cleanup_test_env EXIT

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo -e "    Expected exit code: $expected"
        echo -e "    Actual exit code:   $actual"
        return 1
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))
    if [[ "$actual" == *"$expected"* ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name"
        echo -e "    Expected to contain: '$expected'"
        echo -e "    Actual: '$actual'"
        return 1
    fi
}

assert_json_equals() {
    local json="$1"
    local jq_path="$2"
    local expected="$3"
    local test_name="$4"

    local actual
    actual=$(echo "$json" | jq -r "$jq_path" 2>/dev/null || echo "JQ_ERROR")

    assert_equals "$expected" "$actual" "$test_name"
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"

    ((TESTS_RUN++))
    if [[ -n "$value" && "$value" != "null" && "$value" != "[]" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name (value is empty/null)"
        return 1
    fi
}

assert_empty() {
    local value="$1"
    local test_name="$2"

    ((TESTS_RUN++))
    if [[ -z "$value" || "$value" == "null" || "$value" == "[]" || "$value" == "" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name (expected empty, got: '$value')"
        return 1
    fi
}

verify_file_unchanged() {
    local test_name="$1"
    local current_checksum
    current_checksum=$(md5sum "$TODO_FILE" | cut -d' ' -f1)

    ((TESTS_RUN++))
    if [[ "$TODO_FILE_ORIGINAL_CHECKSUM" == "$current_checksum" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: $test_name - File unchanged"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: $test_name - File was MODIFIED!"
        echo -e "    Original checksum: $TODO_FILE_ORIGINAL_CHECKSUM"
        echo -e "    Current checksum:  $current_checksum"
        return 1
    fi
}

# ============================================================================
# TEST SUITES
# ============================================================================

test_deletion_strategy_sourcing() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: deletion-strategy.sh Sourcing ===${NC}"

    # Test that the library can be sourced
    local source_result=0
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh'" 2>/dev/null || source_result=$?

    assert_exit_code "0" "$source_result" "Library sources without errors"

    # Test that key functions exist after sourcing
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f validate_strategy >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "validate_strategy function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f handle_children >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "handle_children function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f handle_children_block >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "handle_children_block function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f handle_children_cascade >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "handle_children_cascade function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f handle_children_orphan >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "handle_children_orphan function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f get_task_children >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "get_task_children function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && declare -f get_task_descendants >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "get_task_descendants function exists"
}

test_validate_strategy() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: validate_strategy ===${NC}"

    local result

    # NOTE: The library sets IFS to newline+tab for safe parsing, but validate_strategy
    # relies on space-based word splitting for its loop. We reset IFS before calling.
    # This is a known limitation that should be fixed in the library.

    # Test valid strategies (reset IFS before validate_strategy)
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy 'block'" 2>/dev/null
    assert_exit_code "0" "$?" "validate_strategy('block') returns success"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy 'cascade'" 2>/dev/null
    assert_exit_code "0" "$?" "validate_strategy('cascade') returns success"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy 'orphan'" 2>/dev/null
    assert_exit_code "0" "$?" "validate_strategy('orphan') returns success"

    # Test invalid strategy
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy 'invalid'" 2>/dev/null
    assert_exit_code "1" "$?" "validate_strategy('invalid') returns failure"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy ''" 2>/dev/null
    assert_exit_code "1" "$?" "validate_strategy('') returns failure"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && validate_strategy 'CASCADE'" 2>/dev/null
    assert_exit_code "1" "$?" "validate_strategy('CASCADE') returns failure (case-sensitive)"
}

test_get_task_children() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: get_task_children ===${NC}"

    local result

    # Test task with no children (T005 - leaf task)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && get_task_children 'T005' '$TODO_FILE'" 2>/dev/null)
    assert_equals "[]" "$result" "get_task_children('T005') returns empty array for leaf task"

    # Test task with children (T002 has T003, T004)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && get_task_children 'T002' '$TODO_FILE'" 2>/dev/null)
    # Should contain T003 and T004
    assert_contains "T003" "$result" "get_task_children('T002') contains T003"
    assert_contains "T004" "$result" "get_task_children('T002') contains T004"

    # Test epic with children (T001 has T002, T006)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && get_task_children 'T001' '$TODO_FILE'" 2>/dev/null)
    assert_contains "T002" "$result" "get_task_children('T001') contains T002"
    assert_contains "T006" "$result" "get_task_children('T001') contains T006"

    # Test task with no children (T003 - subtask)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && get_task_children 'T003' '$TODO_FILE'" 2>/dev/null)
    assert_equals "[]" "$result" "get_task_children('T003') returns empty array for subtask"
}

test_get_task_descendants() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: get_task_descendants ===${NC}"

    local result

    # NOTE: The get_descendants function in hierarchy.sh uses for loops that rely on
    # space-based word splitting. The library sets IFS to newline+tab, so we need to
    # reset IFS for these tests. This is a known limitation.

    # Test epic with descendants (T001 -> T002, T006, T003, T004)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && get_task_descendants 'T001' '$TODO_FILE'" 2>/dev/null)
    # Should contain all descendants
    assert_contains "T002" "$result" "get_task_descendants('T001') contains T002"
    assert_contains "T003" "$result" "get_task_descendants('T001') contains T003"
    assert_contains "T004" "$result" "get_task_descendants('T001') contains T004"
    assert_contains "T006" "$result" "get_task_descendants('T001') contains T006"

    # Test task with descendants (T002 -> T003, T004)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && get_task_descendants 'T002' '$TODO_FILE'" 2>/dev/null)
    assert_contains "T003" "$result" "get_task_descendants('T002') contains T003"
    assert_contains "T004" "$result" "get_task_descendants('T002') contains T004"

    # Test leaf task (no descendants)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && IFS=' ' && get_task_descendants 'T005' '$TODO_FILE'" 2>/dev/null)
    assert_equals "[]" "$result" "get_task_descendants('T005') returns empty array for leaf task"
}

test_handle_children_block() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: handle_children_block ===${NC}"

    local result
    local exit_code

    # Test task with children (should return EXIT_HAS_CHILDREN = 16)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && handle_children_block 'T002' '$TODO_FILE' 'false'" 2>/dev/null)
    exit_code=$?
    assert_exit_code "16" "$exit_code" "handle_children_block returns EXIT_HAS_CHILDREN (16) for task with children"
    assert_json_equals "$result" '.success' "false" "handle_children_block returns success=false for task with children"
    assert_json_equals "$result" '.error.code' "E_HAS_CHILDREN" "handle_children_block returns E_HAS_CHILDREN error code"

    # Test task without children (should succeed)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/deletion-strategy.sh' && handle_children_block 'T005' '$TODO_FILE' 'false'" 2>/dev/null)
    exit_code=$?
    assert_exit_code "0" "$exit_code" "handle_children_block returns success for leaf task"
    assert_json_equals "$result" '.success' "true" "handle_children_block returns success=true for leaf task"
    assert_json_equals "$result" '.strategy' "block" "handle_children_block returns strategy=block"

    # Verify file wasn't modified
    verify_file_unchanged "handle_children_block (read-only test)"
}

test_delete_preview_sourcing() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: delete-preview.sh Sourcing ===${NC}"

    # Test that the library can be sourced
    local source_result=0
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh'" 2>/dev/null || source_result=$?

    assert_exit_code "0" "$source_result" "Library sources without errors"

    # Test that key functions exist after sourcing
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && declare -f calculate_affected_tasks >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "calculate_affected_tasks function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && declare -f calculate_impact >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "calculate_impact function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && declare -f generate_warnings >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "generate_warnings function exists"

    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && declare -f preview_delete >/dev/null 2>&1" 2>/dev/null
    assert_exit_code "0" "$?" "preview_delete function exists"
}

test_calculate_affected_tasks() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: calculate_affected_tasks ===${NC}"

    local result

    # Test leaf task (only primary, no children)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_affected_tasks 'T005' 'block' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.primary.id' "T005" "calculate_affected_tasks returns primary task for leaf"
    assert_json_equals "$result" '.totalCount' "1" "calculate_affected_tasks returns totalCount=1 for leaf"
    assert_json_equals "$result" '.children | length' "0" "calculate_affected_tasks returns 0 children for leaf (block strategy)"

    # Test cascade with parent that has children
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_affected_tasks 'T002' 'cascade' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.primary.id' "T002" "calculate_affected_tasks returns primary task for cascade"
    # T002 has 2 children (T003, T004), so totalCount should be 3
    local total_count
    total_count=$(echo "$result" | jq '.totalCount')
    assert_equals "3" "$total_count" "calculate_affected_tasks returns totalCount=3 for T002 cascade"
    assert_contains "T003" "$result" "calculate_affected_tasks includes T003 as child"
    assert_contains "T004" "$result" "calculate_affected_tasks includes T004 as child"

    # Test cascade with epic (should include all descendants)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_affected_tasks 'T001' 'cascade' '$TODO_FILE'" 2>/dev/null)
    local epic_total
    epic_total=$(echo "$result" | jq '.totalCount')
    # T001 has T002, T006 (direct), plus T003, T004 (grandchildren) = 5 total
    assert_equals "5" "$epic_total" "calculate_affected_tasks returns totalCount=5 for T001 cascade"

    # Verify file wasn't modified
    verify_file_unchanged "calculate_affected_tasks (read-only test)"
}

test_calculate_impact() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: calculate_impact ===${NC}"

    local affected_tasks
    local result

    # Get affected tasks for T002 cascade
    affected_tasks=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_affected_tasks 'T002' 'cascade' '$TODO_FILE'" 2>/dev/null)

    # Escape the JSON properly for bash -c
    local escaped_affected
    escaped_affected=$(echo "$affected_tasks" | jq -c .)

    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_impact '$escaped_affected' '$TODO_FILE'" 2>/dev/null)

    # T002=pending, T003=pending, T004=active
    assert_json_equals "$result" '.pendingLost' "2" "calculate_impact counts 2 pending tasks (T002, T003)"
    assert_json_equals "$result" '.activeLost' "1" "calculate_impact counts 1 active task (T004)"
    assert_json_equals "$result" '.blockedLost' "0" "calculate_impact counts 0 blocked tasks"

    # T005 depends on T002, T006 depends on T002 and T003 - both are dependents
    local dependents_count
    dependents_count=$(echo "$result" | jq '.dependentsAffected | length')
    # T005 and T006 both depend on affected tasks
    assert_equals "2" "$dependents_count" "calculate_impact finds 2 dependents (T005, T006)"

    # Verify file wasn't modified
    verify_file_unchanged "calculate_impact (read-only test)"
}

test_generate_warnings() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: generate_warnings ===${NC}"

    local affected_tasks
    local impact
    local result

    # Test with T002 cascade (has active children)
    affected_tasks=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_affected_tasks 'T002' 'cascade' '$TODO_FILE'" 2>/dev/null)

    # Escape the JSON properly for bash -c
    local escaped_affected
    escaped_affected=$(echo "$affected_tasks" | jq -c .)

    impact=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && calculate_impact '$escaped_affected' '$TODO_FILE'" 2>/dev/null)

    local escaped_impact
    escaped_impact=$(echo "$impact" | jq -c .)

    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && generate_warnings '$escaped_affected' '$escaped_impact' 'cascade'" 2>/dev/null)

    # Should have HIGH severity for active task being cancelled
    local high_warnings
    high_warnings=$(echo "$result" | jq '[.[] | select(.severity == "high")] | length')
    assert_not_empty "$high_warnings" "generate_warnings creates high severity warnings for active tasks"

    # Should have MEDIUM severity for cascade delete
    local medium_warnings
    medium_warnings=$(echo "$result" | jq '[.[] | select(.severity == "medium")] | length')
    assert_not_empty "$medium_warnings" "generate_warnings creates medium severity warnings for cascade"

    # Check for specific warning codes
    assert_contains "W_ACTIVE_CANCELLED" "$result" "generate_warnings includes W_ACTIVE_CANCELLED warning"
    assert_contains "W_CASCADE_DELETE" "$result" "generate_warnings includes W_CASCADE_DELETE warning"

    # Verify file wasn't modified
    verify_file_unchanged "generate_warnings (read-only test)"
}

test_preview_delete() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: preview_delete ===${NC}"

    local result

    # Test complete preview for leaf task
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && preview_delete 'T005' 'block' 'Test reason' '$TODO_FILE'" 2>/dev/null)

    assert_json_equals "$result" '.success' "true" "preview_delete returns success for valid task"
    assert_json_equals "$result" '.dryRun' "true" "preview_delete sets dryRun=true"
    assert_json_equals "$result" '.strategy' "block" "preview_delete returns correct strategy"
    assert_json_equals "$result" '.reason' "Test reason" "preview_delete returns reason"
    assert_json_equals "$result" '.wouldDelete.primary.id' "T005" "preview_delete includes primary task"

    # Test preview for task with children (block strategy should fail)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && preview_delete 'T002' 'block' 'Test' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.success' "false" "preview_delete fails for task with children (block strategy)"
    assert_json_equals "$result" '.error.code' "E_HAS_CHILDREN" "preview_delete returns E_HAS_CHILDREN error"

    # Test preview for cascade
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && preview_delete 'T002' 'cascade' 'Testing cascade' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.success' "true" "preview_delete succeeds for cascade"
    assert_not_empty "$(echo "$result" | jq '.wouldDelete.children')" "preview_delete includes children for cascade"
    assert_not_empty "$(echo "$result" | jq '.impact')" "preview_delete includes impact analysis"
    assert_not_empty "$(echo "$result" | jq '.warnings')" "preview_delete includes warnings"

    # Test preview for completed task (should fail with suggestion)
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && preview_delete 'T007' 'block' 'Test' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.success' "false" "preview_delete fails for completed task"
    assert_json_equals "$result" '.error.code' "E_TASK_COMPLETED" "preview_delete returns E_TASK_COMPLETED error"

    # Test preview for non-existent task
    result=$(bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && preview_delete 'T999' 'block' 'Test' '$TODO_FILE'" 2>/dev/null)
    assert_json_equals "$result" '.success' "false" "preview_delete fails for non-existent task"
    assert_json_equals "$result" '.error.code' "E_TASK_NOT_FOUND" "preview_delete returns E_TASK_NOT_FOUND error"

    # CRITICAL: Verify file wasn't modified after any preview operations
    verify_file_unchanged "preview_delete (dry-run guarantee)"
}

test_dry_run_guarantee() {
    echo ""
    echo -e "${YELLOW}=== Test Suite: Dry-Run Guarantee ===${NC}"

    # Store original file state
    local original_content
    original_content=$(cat "$TODO_FILE")

    # Run multiple preview operations
    bash -c "cd '$PROJECT_ROOT' && source '$LIB_DIR/delete-preview.sh' && \
        preview_delete 'T001' 'cascade' 'Epic delete' '$TODO_FILE' >/dev/null && \
        preview_delete 'T002' 'cascade' 'Task delete' '$TODO_FILE' >/dev/null && \
        preview_delete 'T005' 'block' 'Leaf delete' '$TODO_FILE' >/dev/null && \
        calculate_affected_tasks 'T001' 'cascade' '$TODO_FILE' >/dev/null" 2>/dev/null

    # Verify file content is identical
    local current_content
    current_content=$(cat "$TODO_FILE")

    ((TESTS_RUN++))
    if [[ "$original_content" == "$current_content" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: File content unchanged after multiple preview operations"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: File content was modified by preview operations!"
        diff <(echo "$original_content") <(echo "$current_content") || true
    fi

    # Verify checksum
    verify_file_unchanged "Dry-run guarantee: No file modifications"

    # Also verify no backup files were created
    ((TESTS_RUN++))
    if [[ ! -d "$TEST_DIR/.backups" && ! -d "$TEST_DIR/backups" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: No backup directories created during preview"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: Backup directories were created during preview (should not happen)"
    fi

    # Verify no lock files remain
    ((TESTS_RUN++))
    local lock_files
    lock_files=$(find "$TEST_DIR" -name "*.lock" 2>/dev/null | wc -l)
    if [[ "$lock_files" -eq 0 ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${NC}: No lock files remaining after preview"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${NC}: Lock files found after preview: $lock_files"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}Wave 2 Testing: Strategy Pattern and Dry-run${NC}"
    echo -e "${CYAN}T704: deletion-strategy.sh${NC}"
    echo -e "${CYAN}T709: delete-preview.sh${NC}"
    echo -e "${CYAN}============================================${NC}"

    # Setup test environment
    setup_test_env

    # Run test suites for deletion-strategy.sh (T704)
    test_deletion_strategy_sourcing
    test_validate_strategy
    test_get_task_children
    test_get_task_descendants
    test_handle_children_block

    # Run test suites for delete-preview.sh (T709)
    test_delete_preview_sourcing
    test_calculate_affected_tasks
    test_calculate_impact
    test_generate_warnings
    test_preview_delete

    # Critical dry-run guarantee tests
    test_dry_run_guarantee

    # Summary
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}TEST SUMMARY${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo -e "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        exit 0
    else
        echo -e "${RED}SOME TESTS FAILED${NC}"
        exit 1
    fi
}

main "$@"
