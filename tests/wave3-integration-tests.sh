#!/usr/bin/env bash
# =============================================================================
# wave3-integration-tests.sh - Wave 3 Integration Tests
# =============================================================================
# Tests for Focus Integration (T705), Archive Integration (T706),
# and Dependency Cleanup (T707)
#
# Usage: ./tests/wave3-integration-tests.sh
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
LIB_DIR="${PROJECT_ROOT}/lib"

# Test directory
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

setup_test_env() {
    local test_name="$1"
    local test_dir="${TEST_TEMP_DIR}/${test_name}"
    mkdir -p "${test_dir}/.claude/.backups"

    export TODO_FILE="${test_dir}/.claude/todo.json"
    export CONFIG_FILE="${test_dir}/.claude/todo-config.json"
    export LOG_FILE="${test_dir}/.claude/todo-log.json"
    export ARCHIVE_FILE="${test_dir}/.claude/todo-archive.json"
    export CLAUDE_TODO_FORMAT="text"

    # Create minimal config
    cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "2.2.0",
  "validation": {
    "strictMode": false,
    "requireDescription": false
  },
  "cancellation": {
    "requireReason": true,
    "defaultChildStrategy": "block",
    "cascadeConfirmThreshold": 10,
    "allowCascade": true,
    "daysUntilArchive": 0
  }
}
EOF

    # Create empty log
    echo '{"entries": [], "_meta": {"version": "2.1.0"}}' > "$LOG_FILE"

    cd "$test_dir"
}

log_test() {
    local status="$1"
    local test_name="$2"
    local details="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$status" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}[PASS]${NC} $test_name"
        TEST_RESULTS+=("PASS: $test_name")
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}[FAIL]${NC} $test_name"
        if [[ -n "$details" ]]; then
            echo -e "       ${YELLOW}Details:${NC} $details"
        fi
        TEST_RESULTS+=("FAIL: $test_name - $details")
    fi
}

# =============================================================================
# T705: FOCUS INTEGRATION TESTS
# =============================================================================

echo -e "\n${BLUE}=== T705: Focus Integration Tests ===${NC}\n"

# Test 1: Delete focused task clears focus
test_delete_focused_task_clears_focus() {
    setup_test_env "focus_clear_test"

    # Create todo.json with a focused task
    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {
        "currentTask": "T001",
        "currentPhase": "core",
        "sessionNote": "Working on feature"
    },
    "tasks": [
        {"id": "T001", "title": "Focused task", "status": "active", "priority": "medium", "phase": "core", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Other task", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    # Delete the focused task
    local output
    output=$(bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing focus clear" --force 2>&1) || true

    # Check if focus was cleared
    local current_focus
    current_focus=$(jq -r '.focus.currentTask // "null"' "$TODO_FILE")

    if [[ "$current_focus" == "null" ]]; then
        log_test "PASS" "Delete focused task clears focus.currentTask"
    else
        log_test "FAIL" "Delete focused task clears focus.currentTask" "Expected null, got: $current_focus"
    fi
}

# Test 2: JSON output includes focusCleared: true
test_delete_focused_task_json_output() {
    setup_test_env "focus_json_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {
        "currentTask": "T001",
        "currentPhase": "core"
    },
    "tasks": [
        {"id": "T001", "title": "Focused task", "status": "active", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    local output
    output=$(bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing focus clear" --force --json 2>&1) || true

    local focus_cleared
    focus_cleared=$(echo "$output" | jq -r '.focusCleared // false')

    if [[ "$focus_cleared" == "true" ]]; then
        log_test "PASS" "JSON output includes focusCleared: true"
    else
        log_test "FAIL" "JSON output includes focusCleared: true" "focusCleared was: $focus_cleared"
    fi
}

# Test 3: Delete non-focused task does not affect focus
test_delete_nonfocused_task() {
    setup_test_env "focus_preserve_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {
        "currentTask": "T001",
        "currentPhase": "core"
    },
    "tasks": [
        {"id": "T001", "title": "Focused task", "status": "active", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Other task", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    # Delete the non-focused task
    local output
    output=$(bash "${SCRIPTS_DIR}/delete.sh" T002 --reason "Testing focus preserve" --force 2>&1) || true

    # Check if focus is preserved
    local current_focus
    current_focus=$(jq -r '.focus.currentTask // "null"' "$TODO_FILE")

    if [[ "$current_focus" == "T001" ]]; then
        log_test "PASS" "Delete non-focused task preserves focus"
    else
        log_test "FAIL" "Delete non-focused task preserves focus" "Focus was: $current_focus"
    fi
}

# Test 4: Session note is preserved when focus is cleared
test_session_note_preserved() {
    setup_test_env "session_note_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {
        "currentTask": "T001",
        "sessionNote": "Important context for session"
    },
    "tasks": [
        {"id": "T001", "title": "Focused task", "status": "active", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing session note" --force >/dev/null 2>&1 || true

    local session_note
    session_note=$(jq -r '.focus.sessionNote // "null"' "$TODO_FILE")

    if [[ "$session_note" == "Important context for session" ]]; then
        log_test "PASS" "Session note is preserved when focus is cleared"
    else
        log_test "FAIL" "Session note is preserved when focus is cleared" "Got: $session_note"
    fi
}

# Run Focus Integration tests
test_delete_focused_task_clears_focus
test_delete_focused_task_json_output
test_delete_nonfocused_task
test_session_note_preserved

# =============================================================================
# T706: ARCHIVE INTEGRATION TESTS
# =============================================================================

echo -e "\n${BLUE}=== T706: Archive Integration Tests ===${NC}\n"

# Test 5: Archive schema has 'cancelled' in statistics
test_archive_schema_has_cancelled() {
    local schema_file="${PROJECT_ROOT}/schemas/archive.schema.json"

    if [[ ! -f "$schema_file" ]]; then
        log_test "FAIL" "Archive schema has 'cancelled' in statistics" "Schema file not found"
        return
    fi

    local has_cancelled
    has_cancelled=$(jq -r '.properties.statistics.properties.cancelled // "missing"' "$schema_file")

    if [[ "$has_cancelled" != "missing" && "$has_cancelled" != "null" ]]; then
        log_test "PASS" "Archive schema has 'cancelled' in statistics"
    else
        log_test "FAIL" "Archive schema has 'cancelled' in statistics" "Missing cancelled property"
    fi
}

# Test 6: archive-cancel.sh creates proper archive entries
test_archive_cancel_creates_entries() {
    setup_test_env "archive_cancel_test"

    # Source the library
    source "$LIB_DIR/archive-cancel.sh" 2>/dev/null || true

    # Create a cancelled task JSON
    local task_json='{"id": "T001", "title": "Cancelled task", "status": "cancelled", "priority": "medium", "phase": "core", "createdAt": "2025-01-01T00:00:00Z", "cancelledAt": "2025-01-02T00:00:00Z", "cancelReason": "Feature deprecated"}'

    if declare -f prepare_cancel_archive_entry >/dev/null 2>&1; then
        local entry
        entry=$(prepare_cancel_archive_entry "$task_json" "test-session" "delete-command")

        # Check for cancellationDetails
        local has_details
        has_details=$(echo "$entry" | jq -r '._archive.cancellationDetails // "missing"')

        if [[ "$has_details" != "missing" && "$has_details" != "null" ]]; then
            log_test "PASS" "archive-cancel.sh creates cancellationDetails object"
        else
            log_test "FAIL" "archive-cancel.sh creates cancellationDetails object" "Missing cancellationDetails"
        fi

        # Check archive reason is "cancelled"
        local reason
        reason=$(echo "$entry" | jq -r '._archive.reason')

        if [[ "$reason" == "cancelled" ]]; then
            log_test "PASS" "archive-cancel.sh sets reason to 'cancelled'"
        else
            log_test "FAIL" "archive-cancel.sh sets reason to 'cancelled'" "Got: $reason"
        fi
    else
        log_test "FAIL" "archive-cancel.sh creates cancellationDetails object" "Function not found"
        log_test "FAIL" "archive-cancel.sh sets reason to 'cancelled'" "Function not found"
    fi
}

# Test 7: archive_cancelled_task updates statistics.cancelled counter
test_archive_updates_cancelled_counter() {
    setup_test_env "archive_counter_test"

    source "$LIB_DIR/archive-cancel.sh" 2>/dev/null || true
    source "$LIB_DIR/file-ops.sh" 2>/dev/null || true

    # Create todo.json with a cancelled task
    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "tasks": [
        {"id": "T001", "title": "Cancelled task", "status": "cancelled", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z", "cancelledAt": "2025-01-02T00:00:00Z", "cancelReason": "Feature deprecated"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    # Create empty archive
    cat > "$ARCHIVE_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": "test",
    "_meta": {"totalArchived": 0, "lastArchived": null},
    "archivedTasks": [],
    "statistics": {"byPhase": {}, "byPriority": {"critical":0,"high":0,"medium":0,"low":0}, "cancelled": 0}
}
EOF

    if declare -f archive_cancelled_task >/dev/null 2>&1; then
        archive_cancelled_task "T001" "$TODO_FILE" "$ARCHIVE_FILE" "test-session" >/dev/null 2>&1 || true

        local cancelled_count
        cancelled_count=$(jq -r '.statistics.cancelled // 0' "$ARCHIVE_FILE")

        if [[ "$cancelled_count" == "1" ]]; then
            log_test "PASS" "Archive updates statistics.cancelled counter"
        else
            log_test "FAIL" "Archive updates statistics.cancelled counter" "Expected 1, got: $cancelled_count"
        fi
    else
        log_test "FAIL" "Archive updates statistics.cancelled counter" "Function not found"
    fi
}

# Test 8: Archived task has proper cancellationDetails structure
test_archive_entry_structure() {
    setup_test_env "archive_structure_test"

    source "$LIB_DIR/archive-cancel.sh" 2>/dev/null || true

    local task_json='{"id": "T002", "title": "Another cancelled", "status": "cancelled", "priority": "high", "createdAt": "2025-01-01T00:00:00Z", "cancelledAt": "2025-01-03T00:00:00Z", "cancelReason": "Superseded by T010"}'

    if declare -f prepare_cancel_archive_entry >/dev/null 2>&1; then
        local entry
        entry=$(prepare_cancel_archive_entry "$task_json" "test-session")

        # Check all required fields in cancellationDetails
        local cancelled_at cancelled_by
        cancelled_at=$(echo "$entry" | jq -r '._archive.cancellationDetails.cancelledAt // "missing"')
        cancelled_by=$(echo "$entry" | jq -r '._archive.cancellationDetails.cancelledBy // "missing"')

        if [[ "$cancelled_at" != "missing" && "$cancelled_by" != "missing" ]]; then
            log_test "PASS" "Archive entry has proper cancellationDetails structure"
        else
            log_test "FAIL" "Archive entry has proper cancellationDetails structure" "Missing fields"
        fi
    else
        log_test "FAIL" "Archive entry has proper cancellationDetails structure" "Function not found"
    fi
}

# Run Archive Integration tests
test_archive_schema_has_cancelled
test_archive_cancel_creates_entries
test_archive_updates_cancelled_counter
test_archive_entry_structure

# =============================================================================
# T707: DEPENDENCY CLEANUP TESTS
# =============================================================================

echo -e "\n${BLUE}=== T707: Dependency Cleanup Tests ===${NC}\n"

# Test 9: Delete task with orphan strategy removes from depends array
test_orphan_removes_dependency() {
    setup_test_env "orphan_deps_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {},
    "tasks": [
        {"id": "T001", "title": "Dependency task", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Dependent task", "status": "pending", "priority": "medium", "depends": ["T001"], "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    # Delete T001 with orphan strategy (no children, but has dependents)
    bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing dependency cleanup" --force >/dev/null 2>&1 || true

    # Check if T002's depends array no longer contains T001
    local depends
    depends=$(jq -r '.tasks[] | select(.id == "T002") | .depends // []' "$TODO_FILE")
    local has_t001
    has_t001=$(echo "$depends" | jq 'index("T001") != null')

    if [[ "$has_t001" == "false" ]]; then
        log_test "PASS" "Delete removes task from dependent's depends array"
    else
        log_test "FAIL" "Delete removes task from dependent's depends array" "T001 still in depends: $depends"
    fi
}

# Test 10: JSON output includes dependentsAffected list
test_dependents_affected_in_output() {
    setup_test_env "dependents_json_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {},
    "tasks": [
        {"id": "T001", "title": "Dependency task", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Dependent task", "status": "pending", "priority": "medium", "depends": ["T001"], "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T003", "title": "Another dependent", "status": "pending", "priority": "medium", "depends": ["T001", "T002"], "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    local output
    output=$(bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing dependents output" --force --json 2>&1) || true

    local dependents_count
    dependents_count=$(echo "$output" | jq -r '.dependentsAffected | length // 0')

    if [[ "$dependents_count" -gt 0 ]]; then
        log_test "PASS" "JSON output includes dependentsAffected list"
    else
        log_test "FAIL" "JSON output includes dependentsAffected list" "Count was: $dependents_count"
    fi
}

# Test 11: Multiple dependents are all cleaned up
test_multiple_dependents_cleanup() {
    setup_test_env "multi_deps_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {},
    "tasks": [
        {"id": "T001", "title": "Core dependency", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "First dependent", "status": "pending", "priority": "medium", "depends": ["T001"], "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T003", "title": "Second dependent", "status": "pending", "priority": "medium", "depends": ["T001"], "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T004", "title": "Third dependent", "status": "pending", "priority": "medium", "depends": ["T001", "T002"], "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing multi cleanup" --force >/dev/null 2>&1 || true

    # Check all dependents
    local t002_deps t003_deps t004_deps
    t002_deps=$(jq -r '.tasks[] | select(.id == "T002") | .depends | index("T001") != null' "$TODO_FILE")
    t003_deps=$(jq -r '.tasks[] | select(.id == "T003") | .depends | index("T001") != null' "$TODO_FILE")
    t004_deps=$(jq -r '.tasks[] | select(.id == "T004") | .depends | index("T001") != null' "$TODO_FILE")

    if [[ "$t002_deps" == "false" && "$t003_deps" == "false" && "$t004_deps" == "false" ]]; then
        log_test "PASS" "All dependents have T001 removed from depends array"
    else
        log_test "FAIL" "All dependents have T001 removed from depends array" "T002:$t002_deps T003:$t003_deps T004:$t004_deps"
    fi
}

# Test 12: Orphan strategy for parent with children
test_orphan_removes_parent_reference() {
    setup_test_env "orphan_parent_test"

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "focus": {},
    "tasks": [
        {"id": "T001", "title": "Parent task", "status": "pending", "priority": "medium", "type": "epic", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Child task", "status": "pending", "priority": "medium", "parentId": "T001", "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    bash "${SCRIPTS_DIR}/delete.sh" T001 --reason "Testing orphan children" --children orphan --force >/dev/null 2>&1 || true

    # Check if child's parentId is now null
    local parent_id
    parent_id=$(jq -r '.tasks[] | select(.id == "T002") | .parentId // "null"' "$TODO_FILE")

    if [[ "$parent_id" == "null" ]]; then
        log_test "PASS" "Orphan strategy removes parentId from children"
    else
        log_test "FAIL" "Orphan strategy removes parentId from children" "parentId was: $parent_id"
    fi
}

# Test 13: cleanup_dependencies function works correctly
test_cleanup_dependencies_function() {
    setup_test_env "cleanup_fn_test"

    source "$LIB_DIR/hierarchy.sh" 2>/dev/null || true

    cat > "$TODO_FILE" << 'EOF'
{
    "version": "2.2.0",
    "project": {"name": "test", "phases": {}},
    "lastUpdated": "2025-01-01T00:00:00Z",
    "tasks": [
        {"id": "T001", "title": "Dependency", "status": "pending", "priority": "medium", "createdAt": "2025-01-01T00:00:00Z"},
        {"id": "T002", "title": "Dependent", "status": "pending", "priority": "medium", "depends": ["T001"], "createdAt": "2025-01-01T00:00:00Z"}
    ],
    "_meta": {"checksum": "abc123", "configVersion": "2.2.0"}
}
EOF

    if declare -f cleanup_dependencies >/dev/null 2>&1; then
        local result
        result=$(cleanup_dependencies "T001" "$TODO_FILE")

        local success
        success=$(echo "$result" | jq -r '.success')

        if [[ "$success" == "true" ]]; then
            log_test "PASS" "cleanup_dependencies function returns success"
        else
            log_test "FAIL" "cleanup_dependencies function returns success" "Result: $result"
        fi
    else
        log_test "FAIL" "cleanup_dependencies function returns success" "Function not found"
    fi
}

# Run Dependency Cleanup tests
test_orphan_removes_dependency
test_dependents_affected_in_output
test_multiple_dependents_cleanup
test_orphan_removes_parent_reference
test_cleanup_dependencies_function

# =============================================================================
# SUMMARY
# =============================================================================

echo -e "\n${BLUE}============================================${NC}"
echo -e "${BLUE}       WAVE 3 TEST RESULTS SUMMARY          ${NC}"
echo -e "${BLUE}============================================${NC}\n"

echo -e "Total Tests: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:${NC} ${PASSED_TESTS}"
echo -e "${RED}Failed:${NC} ${FAILED_TESTS}"

echo -e "\n${BLUE}--- Detailed Results ---${NC}\n"

for result in "${TEST_RESULTS[@]}"; do
    if [[ "$result" == PASS* ]]; then
        echo -e "${GREEN}${result}${NC}"
    else
        echo -e "${RED}${result}${NC}"
    fi
done

echo -e "\n${BLUE}============================================${NC}"

if [[ "$FAILED_TESTS" -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
fi
