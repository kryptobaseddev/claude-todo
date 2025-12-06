#!/usr/bin/env bash
# CLAUDE-TODO Test Runner
# Usage: ./run-all-tests.sh [--verbose] [--suite NAME]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=false
SUITE=""
PASSED=0
FAILED=0
SKIPPED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose) VERBOSE=true; shift ;;
    --suite) SUITE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Test execution function
run_test() {
  local test_file="$1"
  local test_name=$(basename "$test_file" .sh)

  if [[ -n "$SUITE" && "$test_name" != *"$SUITE"* ]]; then
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  echo -n "Running $test_name... "

  if bash "$test_file" > /tmp/test_output.txt 2>&1; then
    echo -e "${GREEN}✅ PASSED${NC}"
    PASSED=$((PASSED + 1))
    if [[ "$VERBOSE" == true ]]; then cat /tmp/test_output.txt; fi
  else
    echo -e "${RED}❌ FAILED${NC}"
    FAILED=$((FAILED + 1))
    cat /tmp/test_output.txt
  fi
}

# Run all test files
echo "=========================================="
echo "CLAUDE-TODO Test Suite"
echo "=========================================="
echo ""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [[ -f "$test_file" ]] && run_test "$test_file"
done

# Summary
echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
echo ""

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
