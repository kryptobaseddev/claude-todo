#!/usr/bin/env bash
# foundation.sh - Check library sourcing and foundational requirements
# Part of LLM-Agent-First Compliance Validator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Check foundation compliance for a script file
# Usage: check_foundation <script_path> <schema_json> [verbose]
check_foundation() {
    local script="$1"
    local schema="$2"
    local verbose="${3:-false}"
    local script_name
    script_name=$(basename "$script")

    local results=()
    local passed=0
    local failed=0

    # Check 1: Required libraries sourced
    local required_libs
    required_libs=$(echo "$schema" | jq -r '.requirements.foundation.libraries.required[]')

    local libs_found=0
    local libs_missing=()

    for lib in $required_libs; do
        if pattern_exists "$script" "source.*$lib"; then
            ((libs_found++)) || true
        else
            libs_missing+=("$lib")
        fi
    done

    local total_libs
    total_libs=$(echo "$required_libs" | wc -w | tr -d ' ')

    if [[ "$libs_found" -eq "$total_libs" ]]; then
        results+=('{"check": "foundation_libs", "passed": true, "details": "All '"$total_libs"' required libraries sourced"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "Foundation libs (exit-codes, error-json, output-format)"
    else
        results+=('{"check": "foundation_libs", "passed": false, "details": "Missing: '"${libs_missing[*]}"'"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "Foundation libs" "Missing: ${libs_missing[*]}"
    fi

    # Check 2: Dual-path fallback support
    local dual_path_pattern
    dual_path_pattern=$(echo "$schema" | jq -r '.requirements.foundation.libraries.patterns.dual_path')

    if pattern_exists "$script" "$dual_path_pattern"; then
        results+=('{"check": "dual_path", "passed": true, "details": "Dual-path library loading supported"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "Dual-path fallback support"
    else
        results+=('{"check": "dual_path", "passed": false, "details": "No dual-path fallback for library loading"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "Dual-path fallback" "Should support both LIB_DIR and CLAUDE_TODO_HOME paths"
    fi

    # Check 3: COMMAND_NAME variable set
    local cmd_name_pattern
    cmd_name_pattern=$(echo "$schema" | jq -r '.requirements.foundation.variables.patterns.command_name')

    if pattern_exists "$script" "$cmd_name_pattern"; then
        # Extract the command name value (escape quotes for JSON)
        local cmd_value
        cmd_value=$(grep -oE 'COMMAND_NAME="[^"]+"' "$script" 2>/dev/null | head -1 || echo "")
        cmd_value="${cmd_value//\"/\\\"}"
        results+=('{"check": "command_name", "passed": true, "details": "'"$cmd_value"'"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "COMMAND_NAME set ($cmd_value)"
    else
        results+=('{"check": "command_name", "passed": false, "details": "COMMAND_NAME variable not set"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "COMMAND_NAME" "Variable not set at script top"
    fi

    # Check 4: VERSION from central location
    local version_pattern
    version_pattern=$(echo "$schema" | jq -r '.requirements.foundation.variables.patterns.version_central')

    if pattern_exists "$script" "$version_pattern"; then
        results+=('{"check": "version_central", "passed": true, "details": "VERSION loaded from central file"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "VERSION from central location"
    else
        # Check if VERSION is defined but not from central location
        if pattern_exists "$script" 'VERSION='; then
            results+=('{"check": "version_central", "passed": false, "details": "VERSION set but not from central file"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check warn "VERSION" "Set but not from central CLAUDE_TODO_HOME/VERSION or SCRIPT_DIR/../VERSION"
        else
            results+=('{"check": "version_central", "passed": false, "details": "VERSION variable not found"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check fail "VERSION" "Variable not found"
        fi
    fi

    # Build JSON result
    local total=$((passed + failed))
    local score
    score=$(calc_score "$passed" "$total")

    jq -n \
        --arg script "$script_name" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson total "$total" \
        --arg score "$score" \
        --argjson checks "$(printf '%s\n' "${results[@]}" | jq -s '.')" \
        '{
            script: $script,
            category: "foundation",
            passed: $passed,
            failed: $failed,
            total: $total,
            score: ($score | tonumber),
            checks: $checks
        }'
}

# Run check on all scripts in directory
# Usage: check_all_foundation <scripts_dir> <schema_json> [verbose]
check_all_foundation() {
    local scripts_dir="$1"
    local schema="$2"
    local verbose="${3:-false}"

    local all_results=()

    for script in "$scripts_dir"/*.sh; do
        [[ -f "$script" ]] || continue
        local result
        result=$(check_foundation "$script" "$schema" "$verbose")
        all_results+=("$result")
    done

    printf '%s\n' "${all_results[@]}" | jq -s '.'
}

# Main entry point when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <script_path> <schema_path> [--verbose]"
        exit 1
    fi

    script_path="$1"
    schema_path="$2"
    verbose="false"
    [[ "${3:-}" == "--verbose" ]] && verbose="true"

    schema=$(load_schema "$schema_path")
    check_foundation "$script_path" "$schema" "$verbose"
fi
