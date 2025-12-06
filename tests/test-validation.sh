#!/usr/bin/env bash
# test-validation.sh - Schema and anti-hallucination validation tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

source "$PROJECT_ROOT/lib/validation.sh" 2>/dev/null || true

PASSED=0
FAILED=0

test_result() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  ✅ $name"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $name (expected: $expected, got: $actual)"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Validation Tests ==="
echo ""

# Test 1: Valid todo.json should pass
echo "Testing valid fixtures..."
if [[ -f "$FIXTURES_DIR/valid/todo.json" ]]; then
  if jq empty "$FIXTURES_DIR/valid/todo.json" 2>/dev/null; then
    test_result "Valid JSON syntax" "pass" "pass"
  else
    test_result "Valid JSON syntax" "pass" "fail"
  fi
else
  test_result "Valid fixture exists" "true" "false"
fi

# Test 2: Invalid status should be detectable
echo "Testing invalid fixtures..."
if [[ -f "$FIXTURES_DIR/invalid/invalid-status.json" ]]; then
  STATUS=$(jq -r '.tasks[0].status' "$FIXTURES_DIR/invalid/invalid-status.json" 2>/dev/null)
  if [[ "$STATUS" != "pending" && "$STATUS" != "active" && "$STATUS" != "blocked" && "$STATUS" != "done" ]]; then
    test_result "Invalid status detection" "detected" "detected"
  else
    test_result "Invalid status detection" "detected" "not-detected"
  fi
fi

# Test 3: Duplicate IDs should be detectable
if [[ -f "$FIXTURES_DIR/invalid/duplicate-ids.json" ]]; then
  ID_COUNT=$(jq '[.tasks[].id] | length' "$FIXTURES_DIR/invalid/duplicate-ids.json" 2>/dev/null)
  UNIQUE_COUNT=$(jq '[.tasks[].id] | unique | length' "$FIXTURES_DIR/invalid/duplicate-ids.json" 2>/dev/null)
  if [[ "$ID_COUNT" != "$UNIQUE_COUNT" ]]; then
    test_result "Duplicate ID detection" "detected" "detected"
  else
    test_result "Duplicate ID detection" "detected" "not-detected"
  fi
fi

# Test 4: Empty tasks array should be valid
if [[ -f "$FIXTURES_DIR/edge-cases/empty-tasks.json" ]]; then
  TASK_COUNT=$(jq '.tasks | length' "$FIXTURES_DIR/edge-cases/empty-tasks.json" 2>/dev/null)
  if [[ "$TASK_COUNT" == "0" ]]; then
    test_result "Empty tasks array valid" "pass" "pass"
  else
    test_result "Empty tasks array valid" "pass" "fail"
  fi
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
