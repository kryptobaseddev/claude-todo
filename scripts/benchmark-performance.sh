#!/usr/bin/env bash
#####################################################################
# benchmark-performance.sh - Performance Testing for Claude Todo
#
# Tests command performance with varying dataset sizes:
# - 100, 500, 1000, 2000 tasks
# - Measures execution time for critical commands
# - Reports on performance targets
#
# Usage:
#   benchmark-performance.sh [OPTIONS]
#
# Options:
#   --sizes "100 500 1000"  Custom dataset sizes (default: 100 500 1000 2000)
#   --runs N                Number of runs per test (default: 3)
#   --output FILE           Save results to file (default: stdout)
#   --help                  Show this help
#
# Performance Targets:
#   list command:  < 100ms for 1000+ tasks
#   stats command: < 1s for 1000+ tasks
#####################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_TODO_HOME="${CLAUDE_TODO_HOME:-$HOME/.claude-todo}"

# Defaults
DATASET_SIZES="100 500 1000 2000"
NUM_RUNS=3
OUTPUT_FILE=""
TEMP_DIR=""

# Performance targets (in milliseconds)
TARGET_LIST_MS=100
TARGET_STATS_MS=1000

usage() {
  cat << 'EOF'
Usage: benchmark-performance.sh [OPTIONS]

Test claude-todo performance with varying dataset sizes.

Options:
  --sizes "100 500 1000"  Custom dataset sizes (default: 100 500 1000 2000)
  --runs N                Number of runs per test (default: 3)
  --output FILE           Save results to file (default: stdout)
  -h, --help              Show this help

Performance Targets:
  list command:  < 100ms for 1000+ tasks
  stats command: < 1000ms for 1000+ tasks

Examples:
  benchmark-performance.sh
  benchmark-performance.sh --sizes "1000 2000 5000"
  benchmark-performance.sh --runs 5 --output benchmark.txt
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --sizes) DATASET_SIZES="$2"; shift 2 ;;
    --runs) NUM_RUNS="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "[ERROR] jq is required but not installed." >&2
  exit 1
fi

if ! command -v bc &>/dev/null; then
  echo "[ERROR] bc is required but not installed." >&2
  exit 1
fi

# Generate random task data
generate_task() {
  local id="$1"
  local statuses=("pending" "active" "blocked" "done")
  local priorities=("critical" "high" "medium" "low")
  local phases=("setup" "core" "polish" "maintenance")
  local labels=("bug" "feature" "docs" "test" "refactor")

  local status="${statuses[$((RANDOM % 4))]}"
  local priority="${priorities[$((RANDOM % 4))]}"
  local phase="${phases[$((RANDOM % 4))]}"
  local label_count=$((RANDOM % 3))

  # Generate labels array
  local labels_json="[]"
  if [[ "$label_count" -gt 0 ]]; then
    local selected_labels=()
    for ((i=0; i<label_count; i++)); do
      selected_labels+=("\"${labels[$((RANDOM % 5))]}\"")
    done
    labels_json="[$(IFS=,; echo "${selected_labels[*]}")]"
  fi

  cat << EOF
{
  "id": "T$(printf "%03d" "$id")",
  "title": "Task $id: Performance test task",
  "description": "Generated task for performance testing with some description text to simulate real usage",
  "status": "$status",
  "priority": "$priority",
  "phase": "$phase",
  "labels": $labels_json,
  "createdAt": "$(date -u -d "-$((RANDOM % 365)) days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-"$((RANDOM % 365))d" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)",
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Generate test dataset
generate_dataset() {
  local size="$1"
  local tasks_json="[]"

  echo "[INFO] Generating $size tasks..." >&2

  for ((i=1; i<=size; i++)); do
    if [[ "$i" -eq 1 ]]; then
      tasks_json="[$(generate_task "$i")]"
    else
      tasks_json="$(echo "$tasks_json" | jq ". += [$(generate_task "$i")]")"
    fi

    # Progress indicator every 100 tasks
    if [[ $((i % 100)) -eq 0 ]]; then
      echo "  Generated $i/$size tasks..." >&2
    fi
  done

  # Create full todo.json structure
  cat << EOF
{
  "version": "1.0.0",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tasks": $tasks_json
}
EOF
}

# Measure command execution time
measure_time() {
  local cmd="$1"
  local start_ns end_ns elapsed_ms

  start_ns=$(date +%s%N 2>/dev/null || echo "0")
  eval "$cmd" >/dev/null 2>&1
  end_ns=$(date +%s%N 2>/dev/null || echo "$start_ns")

  if [[ "$start_ns" != "0" ]] && [[ "$end_ns" != "0" ]]; then
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    # Fallback: use milliseconds if nanoseconds not available
    start_ms=$(date +%s%3N 2>/dev/null || echo "0")
    eval "$cmd" >/dev/null 2>&1
    end_ms=$(date +%s%3N 2>/dev/null || echo "$start_ms")
    elapsed_ms=$((end_ms - start_ms))
  fi

  echo "$elapsed_ms"
}

# Calculate statistics (mean, min, max)
calculate_stats() {
  local values=("$@")
  local sum=0
  local min=${values[0]}
  local max=${values[0]}

  for val in "${values[@]}"; do
    sum=$((sum + val))
    [[ "$val" -lt "$min" ]] && min="$val"
    [[ "$val" -gt "$max" ]] && max="$val"
  done

  local mean=$((sum / ${#values[@]}))
  echo "$mean $min $max"
}

# Run benchmark for a specific dataset size
benchmark_dataset() {
  local size="$1"

  echo ""
  echo "========================================="
  echo "BENCHMARK: $size tasks"
  echo "========================================="

  # Generate dataset
  local dataset
  dataset=$(generate_dataset "$size")

  # Write to temp todo.json
  echo "$dataset" > "$TEMP_DIR/todo.json"

  # Create minimal log file for stats command
  cat > "$TEMP_DIR/todo-log.json" << 'EOF'
{
  "version": "1.0.0",
  "entries": []
}
EOF

  # Test list command
  echo ""
  echo "Testing: list command ($NUM_RUNS runs)"
  local list_times=()
  for ((run=1; run<=NUM_RUNS; run++)); do
    local elapsed
    elapsed=$(measure_time "TODO_FILE=$TEMP_DIR/todo.json $SCRIPT_DIR/list-tasks.sh -q -f json")
    list_times+=("$elapsed")
    echo "  Run $run: ${elapsed}ms"
  done

  read -r list_mean list_min list_max <<< "$(calculate_stats "${list_times[@]}")"
  local list_status="PASS"
  [[ "$size" -ge 1000 ]] && [[ "$list_mean" -gt "$TARGET_LIST_MS" ]] && list_status="FAIL"

  echo "  Result: mean=${list_mean}ms min=${list_min}ms max=${list_max}ms [$list_status]"

  # Test stats command
  echo ""
  echo "Testing: stats command ($NUM_RUNS runs)"
  local stats_times=()
  for ((run=1; run<=NUM_RUNS; run++)); do
    local elapsed
    elapsed=$(measure_time "TODO_FILE=$TEMP_DIR/todo.json STATS_LOG_FILE=$TEMP_DIR/todo-log.json $SCRIPT_DIR/../scripts/stats.sh -f json")
    stats_times+=("$elapsed")
    echo "  Run $run: ${elapsed}ms"
  done

  read -r stats_mean stats_min stats_max <<< "$(calculate_stats "${stats_times[@]}")"
  local stats_status="PASS"
  [[ "$size" -ge 1000 ]] && [[ "$stats_mean" -gt "$TARGET_STATS_MS" ]] && stats_status="FAIL"

  echo "  Result: mean=${stats_mean}ms min=${stats_min}ms max=${stats_max}ms [$stats_status]"

  # Summary
  echo ""
  echo "Summary for $size tasks:"
  echo "  list:  ${list_mean}ms (target: <${TARGET_LIST_MS}ms for 1000+) [$list_status]"
  echo "  stats: ${stats_mean}ms (target: <${TARGET_STATS_MS}ms for 1000+) [$stats_status]"
}

# Main execution
main() {
  # Create temporary directory
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT

  # Redirect output if file specified
  if [[ -n "$OUTPUT_FILE" ]]; then
    exec > >(tee "$OUTPUT_FILE")
  fi

  echo "========================================="
  echo "CLAUDE-TODO PERFORMANCE BENCHMARK"
  echo "========================================="
  echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "Datasets: $DATASET_SIZES"
  echo "Runs per test: $NUM_RUNS"
  echo "Targets:"
  echo "  list:  < ${TARGET_LIST_MS}ms for 1000+ tasks"
  echo "  stats: < ${TARGET_STATS_MS}ms for 1000+ tasks"

  # Run benchmarks for each dataset size
  for size in $DATASET_SIZES; do
    benchmark_dataset "$size"
  done

  echo ""
  echo "========================================="
  echo "BENCHMARK COMPLETE"
  echo "========================================="

  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "Results saved to: $OUTPUT_FILE"
  fi
}

main "$@"
