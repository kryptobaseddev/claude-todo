#!/usr/bin/env bash
# Wave 1 Testing: Validation Library and Config (T717, T718)
# Tests the cancellation-related validation functions and config getters

set -euo pipefail

# Test counters
PASS_COUNT=0
FAIL_COUNT=0
TEST_RESULTS=()

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test helper functions
pass() {
    local test_name="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    TEST_RESULTS+=("PASS: $test_name")
    echo -e "${GREEN}PASS${NC}: $test_name"
}

fail() {
    local test_name="$1"
    local details="${2:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TEST_RESULTS+=("FAIL: $test_name - $details")
    echo -e "${RED}FAIL${NC}: $test_name"
    if [[ -n "$details" ]]; then
        echo "       Details: $details"
    fi
}

# Setup
LIB_DIR="/mnt/projects/claude-todo/lib"
PROJECT_DIR="/mnt/projects/claude-todo"

# Change to project directory (required for library sourcing)
cd "$PROJECT_DIR"

# Source the libraries
echo "=============================================="
echo "Wave 1 Testing: Validation Library and Config"
echo "=============================================="
echo ""

# Create temp directory for testing
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "Test directory: $TEST_DIR"
echo ""

# ============================================================================
# T717: Validation Library Tests
# ============================================================================
echo "=============================================="
echo "T717: Validation Library Tests"
echo "=============================================="
echo ""

# Source validation library
echo "Sourcing lib/validation.sh..."
if source "$LIB_DIR/validation.sh"; then
    pass "Source validation.sh"
else
    fail "Source validation.sh" "Failed to source library"
    exit 1
fi

# Test 1: VALID_STATUSES contains 'cancelled'
echo ""
echo "--- Test: VALID_STATUSES contains 'cancelled' ---"
if [[ " ${VALID_STATUSES[*]} " =~ " cancelled " ]]; then
    pass "VALID_STATUSES contains 'cancelled'"
else
    fail "VALID_STATUSES contains 'cancelled'" "Got: ${VALID_STATUSES[*]}"
fi

# Test 2: validate_cancel_reason() - Valid reasons
echo ""
echo "--- Test: validate_cancel_reason() with valid inputs ---"

# Valid: exactly 5 chars
if validate_cancel_reason "ABCDE" 2>/dev/null; then
    pass "validate_cancel_reason accepts 5 chars (minimum)"
else
    fail "validate_cancel_reason accepts 5 chars (minimum)"
fi

# Valid: normal reason
if validate_cancel_reason "Project requirements changed" 2>/dev/null; then
    pass "validate_cancel_reason accepts normal text"
else
    fail "validate_cancel_reason accepts normal text"
fi

# Valid: 300 chars (max)
LONG_REASON=$(printf 'a%.0s' {1..300})
if validate_cancel_reason "$LONG_REASON" 2>/dev/null; then
    pass "validate_cancel_reason accepts 300 chars (maximum)"
else
    fail "validate_cancel_reason accepts 300 chars (maximum)"
fi

# Test 3: validate_cancel_reason() - Invalid: too short
echo ""
echo "--- Test: validate_cancel_reason() rejects short input ---"
if ! validate_cancel_reason "ABC" 2>/dev/null; then
    pass "validate_cancel_reason rejects <5 chars"
else
    fail "validate_cancel_reason rejects <5 chars" "Should have failed for 3 chars"
fi

if ! validate_cancel_reason "" 2>/dev/null; then
    pass "validate_cancel_reason rejects empty string"
else
    fail "validate_cancel_reason rejects empty string"
fi

# Test 4: validate_cancel_reason() - Invalid: too long
echo ""
echo "--- Test: validate_cancel_reason() rejects long input ---"
VERY_LONG=$(printf 'a%.0s' {1..301})
if ! validate_cancel_reason "$VERY_LONG" 2>/dev/null; then
    pass "validate_cancel_reason rejects >300 chars"
else
    fail "validate_cancel_reason rejects >300 chars"
fi

# Test 5: validate_cancel_reason() - Rejects metacharacters
echo ""
echo "--- Test: validate_cancel_reason() rejects metacharacters ---"

METACHAR_TESTS=(
    "|pipe test"
    ";semicolon test"
    '&ampersand test'
    '$dollar test'
    '`backtick test`'
    '\backslash test'
    '<less than test'
    '>greater than test'
    '(paren test)'
    '{brace test}'
    '[bracket test]'
    '!exclaim test'
    '"double quote'
    "'single quote"
)

for test_input in "${METACHAR_TESTS[@]}"; do
    # Extract first char for display
    first_char="${test_input:0:1}"
    if ! validate_cancel_reason "$test_input" 2>/dev/null; then
        pass "validate_cancel_reason rejects '$first_char' metacharacter"
    else
        fail "validate_cancel_reason rejects '$first_char' metacharacter" "Input: $test_input"
    fi
done

# Test 6: validate_cancel_reason() - Rejects newlines
echo ""
echo "--- Test: validate_cancel_reason() rejects newlines ---"
if ! validate_cancel_reason $'Test with\nnewline' 2>/dev/null; then
    pass "validate_cancel_reason rejects newline"
else
    fail "validate_cancel_reason rejects newline"
fi

if ! validate_cancel_reason $'Test with\rcarriage return' 2>/dev/null; then
    pass "validate_cancel_reason rejects carriage return"
else
    fail "validate_cancel_reason rejects carriage return"
fi

# Test 7: validate_status_transition()
echo ""
echo "--- Test: validate_status_transition() ---"

# Valid transitions to cancelled
echo "Testing valid transitions TO cancelled..."
if validate_status_transition "pending" "cancelled" 2>/dev/null; then
    pass "pending -> cancelled is valid"
else
    fail "pending -> cancelled is valid"
fi

if validate_status_transition "active" "cancelled" 2>/dev/null; then
    pass "active -> cancelled is valid"
else
    fail "active -> cancelled is valid"
fi

if validate_status_transition "blocked" "cancelled" 2>/dev/null; then
    pass "blocked -> cancelled is valid"
else
    fail "blocked -> cancelled is valid"
fi

# Invalid: done -> cancelled
echo "Testing invalid transition: done -> cancelled..."
if ! validate_status_transition "done" "cancelled" 2>/dev/null; then
    pass "done -> cancelled is invalid"
else
    fail "done -> cancelled is invalid" "Done tasks should not be cancellable"
fi

# Restore from cancelled
echo "Testing restore FROM cancelled..."
if validate_status_transition "cancelled" "pending" 2>/dev/null; then
    pass "cancelled -> pending (restore) is valid"
else
    fail "cancelled -> pending (restore) is valid"
fi

# Invalid: cancelled -> active (must go through pending first)
if ! validate_status_transition "cancelled" "active" 2>/dev/null; then
    pass "cancelled -> active is invalid"
else
    fail "cancelled -> active is invalid" "Should only allow cancelled -> pending"
fi

# Test 8: check_cancelled_fields()
echo ""
echo "--- Test: check_cancelled_fields() ---"

# Create test file with cancelled task
cat > "$TEST_DIR/test-cancelled.json" << 'EOF'
{
  "tasks": [
    {
      "id": "T001",
      "content": "Test cancelled task",
      "activeForm": "Testing cancelled task",
      "status": "cancelled",
      "cancelledAt": "2025-12-20T10:00:00Z",
      "cancellationReason": "Requirements changed"
    }
  ]
}
EOF

if check_cancelled_fields "$TEST_DIR/test-cancelled.json" 0 2>/dev/null; then
    pass "check_cancelled_fields validates correct cancelled task"
else
    fail "check_cancelled_fields validates correct cancelled task"
fi

# Create test file with missing cancelledAt
cat > "$TEST_DIR/test-missing-timestamp.json" << 'EOF'
{
  "tasks": [
    {
      "id": "T002",
      "content": "Test missing timestamp",
      "activeForm": "Testing",
      "status": "cancelled",
      "cancellationReason": "Some reason"
    }
  ]
}
EOF

if ! check_cancelled_fields "$TEST_DIR/test-missing-timestamp.json" 0 2>/dev/null; then
    pass "check_cancelled_fields rejects cancelled without cancelledAt"
else
    fail "check_cancelled_fields rejects cancelled without cancelledAt"
fi

# Create test file with missing reason
cat > "$TEST_DIR/test-missing-reason.json" << 'EOF'
{
  "tasks": [
    {
      "id": "T003",
      "content": "Test missing reason",
      "activeForm": "Testing",
      "status": "cancelled",
      "cancelledAt": "2025-12-20T10:00:00Z"
    }
  ]
}
EOF

if ! check_cancelled_fields "$TEST_DIR/test-missing-reason.json" 0 2>/dev/null; then
    pass "check_cancelled_fields rejects cancelled without cancellationReason"
else
    fail "check_cancelled_fields rejects cancelled without cancellationReason"
fi

# ============================================================================
# T718: Configuration Tests
# ============================================================================
echo ""
echo "=============================================="
echo "T718: Configuration Tests"
echo "=============================================="
echo ""

# Source config library (should already be sourced via validation.sh)
echo "Testing config getter functions..."
echo ""

# Test get_cascade_threshold()
echo "--- Test: get_cascade_threshold() ---"
THRESHOLD=$(get_cascade_threshold)
if [[ "$THRESHOLD" == "10" ]]; then
    pass "get_cascade_threshold returns 10 (default)"
else
    fail "get_cascade_threshold returns 10" "Got: $THRESHOLD"
fi

# Test get_require_reason()
echo ""
echo "--- Test: get_require_reason() ---"
REQUIRE=$(get_require_reason)
if [[ "$REQUIRE" == "true" ]]; then
    pass "get_require_reason returns true (default)"
else
    fail "get_require_reason returns true" "Got: $REQUIRE"
fi

# Test get_cancel_days_until_archive()
echo ""
echo "--- Test: get_cancel_days_until_archive() ---"
DAYS=$(get_cancel_days_until_archive)
if [[ "$DAYS" == "3" ]]; then
    pass "get_cancel_days_until_archive returns 3 (default)"
else
    fail "get_cancel_days_until_archive returns 3" "Got: $DAYS"
fi

# Test get_allow_cascade()
echo ""
echo "--- Test: get_allow_cascade() ---"
CASCADE=$(get_allow_cascade)
if [[ "$CASCADE" == "true" ]]; then
    pass "get_allow_cascade returns true (default)"
else
    fail "get_allow_cascade returns true" "Got: $CASCADE"
fi

# Test get_default_child_strategy()
echo ""
echo "--- Test: get_default_child_strategy() ---"
STRATEGY=$(get_default_child_strategy)
if [[ "$STRATEGY" == "block" ]]; then
    pass "get_default_child_strategy returns 'block' (default)"
else
    fail "get_default_child_strategy returns 'block'" "Got: $STRATEGY"
fi

# Test todo-config.json has cancellation section
echo ""
echo "--- Test: todo-config.json has cancellation section ---"
CONFIG_FILE="$PROJECT_DIR/.claude/todo-config.json"
if jq -e '.cancellation' "$CONFIG_FILE" >/dev/null 2>&1; then
    pass "todo-config.json has cancellation section"

    # Verify structure
    if jq -e '.cancellation.cascadeConfirmThreshold' "$CONFIG_FILE" >/dev/null 2>&1; then
        pass "cancellation has cascadeConfirmThreshold"
    else
        fail "cancellation has cascadeConfirmThreshold"
    fi

    if jq -e '.cancellation.requireReason' "$CONFIG_FILE" >/dev/null 2>&1; then
        pass "cancellation has requireReason"
    else
        fail "cancellation has requireReason"
    fi

    if jq -e '.cancellation.daysUntilArchive' "$CONFIG_FILE" >/dev/null 2>&1; then
        pass "cancellation has daysUntilArchive"
    else
        fail "cancellation has daysUntilArchive"
    fi

    if jq -e '.cancellation.allowCascade' "$CONFIG_FILE" >/dev/null 2>&1; then
        pass "cancellation has allowCascade"
    else
        fail "cancellation has allowCascade"
    fi

    if jq -e '.cancellation.defaultChildStrategy' "$CONFIG_FILE" >/dev/null 2>&1; then
        pass "cancellation has defaultChildStrategy"
    else
        fail "cancellation has defaultChildStrategy"
    fi
else
    fail "todo-config.json has cancellation section"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=============================================="
echo "Test Summary"
echo "=============================================="
echo ""
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo ""
    echo "Failed tests:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == FAIL* ]]; then
            echo "  - ${result#FAIL: }"
        fi
    done
    exit 1
fi
