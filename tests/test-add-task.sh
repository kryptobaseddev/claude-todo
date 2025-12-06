#!/usr/bin/env bash
# test-add-task.sh - Task creation tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

echo "=== Add Task Tests ==="
echo ""

# Test 1: Add task script exists
echo "Testing add-task script presence..."
if [[ -f "$PROJECT_ROOT/scripts/add-task.sh" ]]; then
  test_result "Add task script exists" "true" "true"
else
  test_result "Add task script exists" "true" "false"
fi

# Test 2: Add task script is executable
if [[ -x "$PROJECT_ROOT/scripts/add-task.sh" ]]; then
  test_result "Add task script executable" "true" "true"
else
  test_result "Add task script executable" "true" "false"
fi

# Test 3: Todo schema exists for validation
if [[ -f "$PROJECT_ROOT/schemas/todo.schema.json" ]]; then
  test_result "Todo schema exists" "true" "true"
else
  test_result "Todo schema exists" "true" "false"
fi

# Test 4: Todo template exists
if [[ -f "$PROJECT_ROOT/templates/todo.template.json" ]]; then
  test_result "Todo template exists" "true" "true"
else
  test_result "Todo template exists" "true" "false"
fi

# Test 5: Todo template is valid JSON
if [[ -f "$PROJECT_ROOT/templates/todo.template.json" ]]; then
  if jq empty "$PROJECT_ROOT/templates/todo.template.json" 2>/dev/null; then
    test_result "Todo template valid JSON" "pass" "pass"
  else
    test_result "Todo template valid JSON" "pass" "fail"
  fi
fi

# Test 6: Validation library exists
if [[ -f "$PROJECT_ROOT/lib/validation.sh" ]]; then
  test_result "Validation library exists" "true" "true"
else
  test_result "Validation library exists" "true" "false"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
