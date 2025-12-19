#!/usr/bin/env bash
# flags.sh - Check flag support compliance
# Part of LLM-Agent-First Compliance Validator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

# Check flag compliance for a script file
# Usage: check_flags <script_path> <schema_json> <command_name> [verbose]
check_flags() {
    local script="$1"
    local schema="$2"
    local command="${3:-}"
    local verbose="${4:-false}"
    local script_name
    script_name=$(basename "$script")

    # If command not provided, derive from script name
    if [[ -z "$command" ]]; then
        command="${script_name%.sh}"
        command="${command%-task}"
        command="${command%-command}"
        command="${command%-todowrite}"
    fi

    local results=()
    local passed=0
    local failed=0
    local skipped=0

    # Check 1: --format flag
    local format_pattern
    format_pattern=$(echo "$schema" | jq -r '.requirements.flags.universal.patterns.format_flag')

    if pattern_exists "$script" "$format_pattern"; then
        results+=('{"check": "format_flag", "passed": true, "details": "--format flag supported"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "--format flag"
    else
        results+=('{"check": "format_flag", "passed": false, "details": "--format flag not found"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "--format flag" "Pattern: $format_pattern"
    fi

    # Check 2: --quiet flag
    local quiet_pattern
    quiet_pattern=$(echo "$schema" | jq -r '.requirements.flags.universal.patterns.quiet_flag')

    if pattern_exists "$script" "$quiet_pattern"; then
        results+=('{"check": "quiet_flag", "passed": true, "details": "--quiet flag supported"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "--quiet flag"
    else
        results+=('{"check": "quiet_flag", "passed": false, "details": "--quiet flag not found"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "--quiet flag" "Pattern: $quiet_pattern"
    fi

    # Check 3: --json shortcut
    local json_pattern
    json_pattern=$(echo "$schema" | jq -r '.requirements.flags.universal.patterns.json_shortcut')

    if pattern_exists "$script" "$json_pattern"; then
        results+=('{"check": "json_shortcut", "passed": true, "details": "--json shortcut supported"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "--json shortcut"
    else
        results+=('{"check": "json_shortcut", "passed": false, "details": "--json shortcut not found"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "--json shortcut" "Pattern: $json_pattern"
    fi

    # Check 4: --human shortcut
    local human_pattern
    human_pattern=$(echo "$schema" | jq -r '.requirements.flags.universal.patterns.human_shortcut')

    if pattern_exists "$script" "$human_pattern"; then
        results+=('{"check": "human_shortcut", "passed": true, "details": "--human shortcut supported"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "--human shortcut"
    else
        results+=('{"check": "human_shortcut", "passed": false, "details": "--human shortcut not found"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "--human shortcut" "Pattern: $human_pattern"
    fi

    # Check 5: resolve_format() called
    local resolve_pattern
    resolve_pattern=$(echo "$schema" | jq -r '.requirements.flags.format_resolution.pattern')

    if pattern_exists "$script" "$resolve_pattern"; then
        results+=('{"check": "resolve_format", "passed": true, "details": "resolve_format() called for TTY-aware resolution"}')
        ((passed++)) || true
        [[ "$verbose" == "true" ]] && print_check pass "resolve_format() called"
    else
        results+=('{"check": "resolve_format", "passed": false, "details": "resolve_format() not called - TTY detection missing"}')
        ((failed++)) || true
        [[ "$verbose" == "true" ]] && print_check fail "resolve_format()" "TTY-aware format resolution missing"
    fi

    # Check 6: --dry-run flag (only for write commands)
    if needs_dry_run "$command" "$schema"; then
        if pattern_exists "$script" "--dry-run\\)"; then
            results+=('{"check": "dry_run", "passed": true, "details": "--dry-run flag supported (required for write command)"}')
            ((passed++)) || true
            [[ "$verbose" == "true" ]] && print_check pass "--dry-run flag (required for write command)"
        else
            results+=('{"check": "dry_run", "passed": false, "details": "--dry-run flag missing (required for write command)"}')
            ((failed++)) || true
            [[ "$verbose" == "true" ]] && print_check fail "--dry-run flag" "Required for write commands"
        fi
    else
        results+=('{"check": "dry_run", "passed": true, "skipped": true, "details": "--dry-run not required (read-only command)"}')
        ((skipped++)) || true
        [[ "$verbose" == "true" ]] && print_check skip "--dry-run (not required for read command)"
    fi

    # Build JSON result
    local total=$((passed + failed))
    local score
    score=$(calc_score "$passed" "$total")

    jq -n \
        --arg script "$script_name" \
        --arg command "$command" \
        --argjson passed "$passed" \
        --argjson failed "$failed" \
        --argjson skipped "$skipped" \
        --argjson total "$total" \
        --arg score "$score" \
        --argjson checks "$(printf '%s\n' "${results[@]}" | jq -s '.')" \
        '{
            script: $script,
            command: $command,
            category: "flags",
            passed: $passed,
            failed: $failed,
            skipped: $skipped,
            total: $total,
            score: ($score | tonumber),
            checks: $checks
        }'
}

# Run check on all scripts in directory
# Usage: check_all_flags <scripts_dir> <schema_json> [verbose]
check_all_flags() {
    local scripts_dir="$1"
    local schema="$2"
    local verbose="${3:-false}"

    local all_results=()

    for script in "$scripts_dir"/*.sh; do
        [[ -f "$script" ]] || continue
        local result
        result=$(check_flags "$script" "$schema" "" "$verbose")
        all_results+=("$result")
    done

    printf '%s\n' "${all_results[@]}" | jq -s '.'
}

# Main entry point when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <script_path> <schema_path> [command_name] [--verbose]"
        exit 1
    fi

    script_path="$1"
    schema_path="$2"
    command_name="${3:-}"
    verbose="false"

    # Check if command_name is actually --verbose
    if [[ "$command_name" == "--verbose" ]]; then
        command_name=""
        verbose="true"
    elif [[ "${4:-}" == "--verbose" ]]; then
        verbose="true"
    fi

    schema=$(load_schema "$schema_path")
    check_flags "$script_path" "$schema" "$command_name" "$verbose"
fi
