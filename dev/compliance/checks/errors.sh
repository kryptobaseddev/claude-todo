#!/usr/bin/env bash
# errors.sh - Check error handling compliance
# Part of LLM-Agent-First Compliance Validator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Check error handling compliance for a script file
# Usage: check_errors <script_path> <schema_json> [verbose]
check_errors() {
    local script="$1"
    local schema="$2"
    local verbose="${3:-false}"
    local script_name
    script_name=$(basename "$script")

    local results=()
    local passed=0
    local failed=0
    local warnings=0

    # Check 1: Uses output_error() function
    local output_error_pattern
    output_error_pattern=$(echo "$schema" | jq -r '.requirements.error_handling.required_function')

    local error_func_count
    error_func_count=$(pattern_count "$script" "$output_error_pattern")

    if [[ "$error_func_count" -gt 0 ]]; then
        results+=('{"check": "output_error_usage", "passed": true, "details": "Uses output_error() function ('"$error_func_count"' calls)"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "output_error() used ($error_func_count calls)"
    else
        # Check if there's any error output at all
        local has_errors
        has_errors=$(pattern_count "$script" ">&2|stderr|error" || echo "0")

        if [[ "$has_errors" -gt 0 ]]; then
            results+=('{"check": "output_error_usage", "passed": false, "details": "Has error handling but doesn'\''t use output_error()"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check fail "output_error()" "Has error handling but not using standard function"
        else
            results+=('{"check": "output_error_usage", "passed": true, "skipped": true, "details": "No apparent error output (may not need it)"}')
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check skip "output_error() (no error handling found)"
        fi
    fi

    # Check 2: Defensive function check (declare -f output_error)
    local defensive_pattern
    defensive_pattern=$(echo "$schema" | jq -r '.requirements.error_handling.defensive_check')

    if pattern_exists "$script" "$defensive_pattern"; then
        results+=('{"check": "defensive_check", "passed": true, "details": "Defensive function check present"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "Defensive function check"
    else
        # Only fail if output_error is used
        if [[ "$error_func_count" -gt 0 ]]; then
            results+=('{"check": "defensive_check", "passed": false, "details": "Uses output_error() but no defensive check (declare -f)"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check fail "Defensive check" "Add: declare -f output_error >/dev/null"
        else
            results+=('{"check": "defensive_check", "passed": true, "skipped": true, "details": "Not needed (output_error not used)"}')
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check skip "Defensive check (output_error not used)"
        fi
    fi

    # Check 3: Error codes use E_* pattern
    local error_code_pattern
    error_code_pattern=$(echo "$schema" | jq -r '.requirements.error_handling.error_codes_pattern')

    local error_code_count
    error_code_count=$(pattern_count "$script" "$error_code_pattern")

    if [[ "$error_code_count" -gt 0 ]]; then
        # Extract unique error codes used
        local error_codes
        error_codes=$(grep -oE 'E_[A-Z_]+' "$script" 2>/dev/null | sort -u | head -5 | tr '\n' ',' | sed 's/,$//' || echo "")
        results+=('{"check": "error_codes", "passed": true, "details": "Uses E_* error codes: '"$error_codes"'"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "E_* error codes ($error_codes)"
    else
        # Check if there are any error situations
        if [[ "$error_func_count" -gt 0 ]]; then
            results+=('{"check": "error_codes", "passed": false, "details": "Uses output_error() but no E_* error codes"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check fail "E_* error codes" "Should use standard error codes with output_error()"
        else
            results+=('{"check": "error_codes", "passed": true, "skipped": true, "details": "No error handling requiring codes"}')
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check skip "E_* error codes (no error handling)"
        fi
    fi

    # Check 4: error-json.sh library sourced
    if pattern_exists "$script" "source.*error-json\\.sh"; then
        results+=('{"check": "error_lib_sourced", "passed": true, "details": "error-json.sh library sourced"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "error-json.sh sourced"
    else
        results+=('{"check": "error_lib_sourced", "passed": false, "details": "error-json.sh library not sourced"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "error-json.sh" "Library not sourced"
    fi

    # Check 5: Proper error JSON structure (if using jq for errors)
    local json_error_count
    json_error_count=$(pattern_count "$script" '"error".*:.*"' || echo "0")

    if [[ "$json_error_count" -gt 0 ]]; then
        # Check for proper structure
        if pattern_exists "$script" '"success".*:.*false'; then
            results+=('{"check": "error_json_structure", "passed": true, "details": "Error JSON includes success: false"}')
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check pass "Error JSON structure"
        else
            results+=('{"check": "error_json_structure", "passed": false, "warning": true, "details": "Error JSON should include success: false"}')
            ((warnings++)) || true
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check warn "Error JSON structure" "Consider adding success: false to error responses"
        fi
    else
        results+=('{"check": "error_json_structure", "passed": true, "skipped": true, "details": "No inline JSON errors found"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check skip "Error JSON structure (no inline JSON)"
    fi

    # Build JSON result
    local total=$((passed + failed))
    local score
    score=$(calc_score "$passed" "$total")

    jq -n \
        --arg script "$script_name" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson warnings "$warnings" \
        --argjson total "$total" \
        --arg score "$score" \
        --argjson checks "$(printf '%s\n' "${results[@]}" | jq -s '.')" \
        '{
            script: $script,
            category: "errors",
            passed: $passed,
            failed: $failed,
            warnings: $warnings,
            total: $total,
            score: ($score | tonumber),
            checks: $checks
        }'
}

# Run check on all scripts in directory
# Usage: check_all_errors <scripts_dir> <schema_json> [verbose]
check_all_errors() {
    local scripts_dir="$1"
    local schema="$2"
    local verbose="${3:-false}"

    local all_results=()

    for script in "$scripts_dir"/*.sh; do
        [[ -f "$script" ]] || continue
        local result
        result=$(check_errors "$script" "$schema" "$verbose")
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
    check_errors "$script_path" "$schema" "$verbose"
fi
