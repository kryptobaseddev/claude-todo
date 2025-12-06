#!/usr/bin/env bash
# test-archive.sh - Archive operation tests
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

echo "=== Archive Tests ==="
echo ""

# Test 1: Archive script exists
echo "Testing archive script presence..."
if [[ -f "$PROJECT_ROOT/scripts/archive.sh" ]]; then
  test_result "Archive script exists" "true" "true"
else
  test_result "Archive script exists" "true" "false"
fi

# Test 2: Archive script is executable
if [[ -x "$PROJECT_ROOT/scripts/archive.sh" ]]; then
  test_result "Archive script executable" "true" "true"
else
  test_result "Archive script executable" "true" "false"
fi

# Test 3: Archive schema exists
if [[ -f "$PROJECT_ROOT/schemas/archive.schema.json" ]]; then
  test_result "Archive schema exists" "true" "true"
else
  test_result "Archive schema exists" "true" "false"
fi

# Test 4: Archive template exists
if [[ -f "$PROJECT_ROOT/templates/archive.template.json" ]]; then
  test_result "Archive template exists" "true" "true"
else
  test_result "Archive template exists" "true" "false"
fi

# Test 5: Archive template is valid JSON
if [[ -f "$PROJECT_ROOT/templates/archive.template.json" ]]; then
  if jq empty "$PROJECT_ROOT/templates/archive.template.json" 2>/dev/null; then
    test_result "Archive template valid JSON" "pass" "pass"
  else
    test_result "Archive template valid JSON" "pass" "fail"
  fi
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
