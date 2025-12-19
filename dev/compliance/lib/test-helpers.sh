#!/usr/bin/env bash
# test-helpers.sh - Common utilities for compliance checking
# Part of LLM-Agent-First Compliance Validator

set -euo pipefail

# Colors for output (respects NO_COLOR)
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# Symbols
PASS_SYM="✓"
FAIL_SYM="✗"
WARN_SYM="⚠"
SKIP_SYM="○"
INFO_SYM="ℹ"

# Global counters
declare -g TOTAL_CHECKS=0
declare -g PASSED_CHECKS=0
declare -g FAILED_CHECKS=0
declare -g SKIPPED_CHECKS=0

# Load schema from JSON file
# Usage: load_schema <schema_path>
load_schema() {
    local schema_path="$1"
    if [[ ! -f "$schema_path" ]]; then
        echo "ERROR: Schema not found: $schema_path" >&2
        return 1
    fi
    cat "$schema_path"
}

# Get value from schema using jq
# Usage: schema_get <json> <jq_path>
schema_get() {
    local json="$1"
    local path="$2"
    echo "$json" | jq -r "$path"
}

# Check if pattern exists in file
# Usage: pattern_exists <file> <pattern>
# Returns: 0 if found, 1 if not
pattern_exists() {
    local file="$1"
    local pattern="$2"
    grep -qE -- "$pattern" "$file" 2>/dev/null
}

# Count pattern matches in file
# Usage: pattern_count <file> <pattern>
pattern_count() {
    local file="$1"
    local pattern="$2"
    local count
    count=$(grep -cE -- "$pattern" "$file" 2>/dev/null) || count=0
    echo "$count" | tr -d '[:space:]'
}

# Get all matching lines for pattern
# Usage: pattern_matches <file> <pattern>
pattern_matches() {
    local file="$1"
    local pattern="$2"
    grep -nE "$pattern" "$file" 2>/dev/null || true
}

# Record a check result
# Usage: record_check <pass|fail|skip> <check_name> [details]
record_check() {
    local status="$1"
    local check_name="$2"
    local details="${3:-}"

    ((TOTAL_CHECKS++)) || true

    case "$status" in
        pass)
            ((PASSED_CHECKS++)) || true
            ;;
        fail)
            ((FAILED_CHECKS++)) || true
            ;;
        skip)
            ((SKIPPED_CHECKS++)) || true
            ;;
    esac
}

# Print check result in text format (to stderr to not mix with JSON)
# Usage: print_check <pass|fail|skip|warn> <message> [details]
print_check() {
    local status="$1"
    local message="$2"
    local details="${3:-}"

    case "$status" in
        pass)
            echo -e "  ${GREEN}${PASS_SYM}${NC} $message" >&2
            ;;
        fail)
            echo -e "  ${RED}${FAIL_SYM}${NC} $message" >&2
            [[ -n "$details" ]] && echo -e "    ${DIM}$details${NC}" >&2
            ;;
        skip)
            echo -e "  ${DIM}${SKIP_SYM} $message (skipped)${NC}" >&2
            ;;
        warn)
            echo -e "  ${YELLOW}${WARN_SYM}${NC} $message" >&2
            [[ -n "$details" ]] && echo -e "    ${DIM}$details${NC}" >&2
            ;;
        info)
            echo -e "  ${BLUE}${INFO_SYM}${NC} $message" >&2
            ;;
    esac
}

# Calculate compliance score
# Usage: calc_score <passed> <total>
calc_score() {
    local passed="$1"
    local total="$2"

    if [[ "$total" -eq 0 ]]; then
        echo "0"
        return
    fi

    # Use bc for floating point, or awk as fallback
    if command -v bc &>/dev/null; then
        echo "scale=1; $passed * 100 / $total" | bc
    else
        awk "BEGIN {printf \"%.1f\", $passed * 100 / $total}"
    fi
}

# Check if command is a write command
# Usage: is_write_command <command_name> <schema_json>
is_write_command() {
    local cmd="$1"
    local schema="$2"

    local write_cmds
    write_cmds=$(echo "$schema" | jq -r '.commands.write[]' 2>/dev/null)
    echo "$write_cmds" | grep -qx "$cmd"
}

# Check if command needs --dry-run
# Usage: needs_dry_run <command_name> <schema_json>
needs_dry_run() {
    local cmd="$1"
    local schema="$2"

    local dry_run_cmds
    dry_run_cmds=$(echo "$schema" | jq -r '.requirements.flags.write_commands.commands[]' 2>/dev/null)
    echo "$dry_run_cmds" | grep -qx "$cmd"
}

# Get script file for command
# Usage: get_script_for_command <command_name> <schema_json>
get_script_for_command() {
    local cmd="$1"
    local schema="$2"

    echo "$schema" | jq -r ".commandScripts[\"$cmd\"] // empty"
}

# List all commands from schema
# Usage: list_all_commands <schema_json>
list_all_commands() {
    local schema="$1"
    echo "$schema" | jq -r '
        (.commands.write + .commands.read + .commands.sync + .commands.maintenance)
        | unique | .[]
    '
}

# Create cache key from file
# Usage: get_file_hash <file_path>
get_file_hash() {
    local file="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" 2>/dev/null | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1
    else
        # Fallback to md5
        md5sum "$file" 2>/dev/null | cut -d' ' -f1
    fi
}

# Load cache file
# Usage: load_cache <cache_path>
load_cache() {
    local cache_path="$1"
    if [[ -f "$cache_path" ]]; then
        cat "$cache_path"
    else
        echo "{}"
    fi
}

# Check if file has changed since last check
# Usage: file_changed <file_path> <cache_json>
file_changed() {
    local file="$1"
    local cache="$2"

    local current_hash
    current_hash=$(get_file_hash "$file")

    local cached_hash
    cached_hash=$(echo "$cache" | jq -r ".files[\"$file\"].hash // empty")

    [[ "$current_hash" != "$cached_hash" ]]
}

# Format timestamp for output
# Usage: format_timestamp
format_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Execute command and capture JSON output
# Usage: run_command_json <command> [args...]
# Returns: JSON output or error
run_command_json() {
    local output
    local exit_code=0

    output=$("$@" --format json 2>&1) || exit_code=$?

    # Try to parse as JSON
    if echo "$output" | jq . &>/dev/null; then
        echo "$output"
    else
        echo "{\"error\": \"Invalid JSON output\", \"raw\": $(echo "$output" | jq -Rs .), \"exit_code\": $exit_code}"
    fi
}

# Validate JSON envelope structure
# Usage: validate_envelope <json_output>
# Returns: JSON with validation results
validate_envelope() {
    local json="$1"

    local has_schema has_meta has_success
    has_schema=$(echo "$json" | jq 'has("$schema")' 2>/dev/null || echo "false")
    has_meta=$(echo "$json" | jq 'has("_meta")' 2>/dev/null || echo "false")
    has_success=$(echo "$json" | jq 'has("success")' 2>/dev/null || echo "false")

    local meta_fields=""
    if [[ "$has_meta" == "true" ]]; then
        meta_fields=$(echo "$json" | jq '._meta | keys | join(",")' 2>/dev/null || echo "[]")
    fi

    jq -n \
        --argjson has_schema "$has_schema" \
        --argjson has_meta "$has_meta" \
        --argjson has_success "$has_success" \
        --arg meta_fields "$meta_fields" \
        '{
            has_schema: $has_schema,
            has_meta: $has_meta,
            has_success: $has_success,
            meta_fields: $meta_fields
        }'
}

# Print section header
# Usage: print_header <title>
print_header() {
    local title="$1"
    echo -e "\n${BOLD}${CYAN}$title${NC}"
    echo -e "${DIM}$(printf '%.0s─' {1..60})${NC}"
}

# Print summary statistics
# Usage: print_summary <passed> <failed> <skipped> <total>
print_summary() {
    local passed="$1"
    local failed="$2"
    local skipped="$3"
    local total="$4"

    local score
    score=$(calc_score "$passed" "$total")

    echo -e "\n${BOLD}Summary${NC}"
    echo -e "${DIM}$(printf '%.0s─' {1..40})${NC}"
    echo -e "Total checks: ${BOLD}$total${NC}"
    echo -e "Passed:       ${GREEN}$passed${NC}"
    echo -e "Failed:       ${RED}$failed${NC}"
    echo -e "Skipped:      ${DIM}$skipped${NC}"
    echo -e "Score:        ${BOLD}${score}%${NC}"
}

# Reset counters for new command
reset_counters() {
    TOTAL_CHECKS=0
    PASSED_CHECKS=0
    FAILED_CHECKS=0
    SKIPPED_CHECKS=0
}

# Get counters as JSON
get_counters_json() {
    jq -n \
        --argjson total "$TOTAL_CHECKS" \
        --argjson passed "$PASSED_CHECKS" \
        --argjson failed "$FAILED_CHECKS" \
        --argjson skipped "$SKIPPED_CHECKS" \
        '{
            total: $total,
            passed: $passed,
            failed: $failed,
            skipped: $skipped,
            score: (if $total > 0 then ($passed * 100 / $total) else 0 end)
        }'
}
