# Code Style and Conventions

## Bash Script Style

### File Organization
```bash
#!/usr/bin/env bash
# Script: script-name.sh
# Purpose: Brief description
# Usage: script-name.sh [options] [arguments]

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Safe word splitting

# Source libraries
source "$(dirname "$0")/../lib/validation.sh"
source "$(dirname "$0")/../lib/logging.sh"

# Constants (UPPERCASE)
readonly CLAUDE_TODO_DIR="${HOME}/.claude-todo"
readonly TODO_FILE=".claude/todo.json"

# Functions before main logic
function main() {
    # Main script logic
}

# Run main
main "$@"
```

### Naming Conventions
- **Scripts**: kebab-case (add-task.sh, archive.sh)
- **Functions**: snake_case (validate_schema, atomic_write)
- **Constants**: UPPERCASE_WITH_UNDERSCORES
- **Local variables**: lowercase_with_underscores
- **Environment vars**: CLAUDE_TODO_PREFIX

### Function Documentation
```bash
# Description: Brief one-line summary
# Arguments:
#   $1 - First argument description
#   $2 - Second argument description
# Returns:
#   0 - Success
#   1 - Failure with error message to stderr
# Example:
#   validate_task_json "path/to/todo.json"
function validate_task_json() {
    local json_file="$1"
    # Implementation
}
```

### Error Handling
```bash
# Always check return codes
if ! validate_schema "$file"; then
    log_error "Schema validation failed: $file"
    return 1
fi

# Use explicit error messages
die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Validate inputs early
[[ -z "$task_id" ]] && die "Task ID required"
[[ ! -f "$config_file" ]] && die "Config file not found: $config_file"
```

### Output Conventions
```bash
# Use structured output functions
log_info "Starting archive operation..."
log_success "Archived 5 tasks successfully"
log_warning "Archive size exceeds recommended limit"
log_error "Failed to write file: $filename"

# JSON output for machine consumption
if [[ "$output_format" == "json" ]]; then
    jq -n --arg status "success" '{status: $status}'
fi
```

## JSON Structure Conventions

### Consistent Field Ordering
```json
{
  "id": "unique-identifier",
  "title": "Task description (imperative form)",
  "description": "Task description (continuous form)",
  "status": "pending|active|blocked|done",
  "priority": "low|medium|high|critical",
  "createdAt": "ISO 8601 timestamp",
  "completedAt": "ISO 8601 timestamp or null"
}
```

### Timestamp Format
- **Standard**: ISO 8601 with timezone (2025-12-05T10:00:00Z)
- **Timezone**: UTC preferred, local with offset acceptable
- **Parsing**: Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` for generation

### ID Generation
```bash
# Format: prefix-timestamp-random
generate_task_id() {
    echo "task-$(date +%s)-$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"
}
```

## Schema Design Conventions

### Required vs Optional
- **Always Required**: id, title, status, priority, createdAt
- **Conditionally Required**: completedAt (required when status=done)
- **Optional**: description, files, acceptance, depends, blockedBy, notes, labels

### Enum Constraints
```json
{
  "status": {
    "type": "string",
    "enum": ["pending", "active", "blocked", "done"]
  },
  "priority": {
    "type": "string",
    "enum": ["low", "medium", "high", "critical"]
  }
}
```

### Anti-Hallucination Constraints
- Enforce title ≠ description (different strings when description provided)
- Validate timestamp sanity (not in future)
- Ensure ID uniqueness across files
- Prevent duplicate task titles

## Configuration Conventions

### Hierarchy
1. Hardcoded defaults in scripts
2. Global config: ~/.claude-todo/config.json
3. Project config: .claude/todo-config.json
4. Environment: CLAUDE_TODO_* variables
5. CLI flags: --option=value

### Naming Pattern
- **Config files**: todo-config.json
- **Environment vars**: CLAUDE_TODO_ARCHIVE_DAYS
- **CLI flags**: --archive-days=7

## Testing Conventions

### Test Structure
```bash
# tests/test-validation.sh
source "$(dirname "$0")/../lib/validation.sh"

test_valid_schema() {
    local test_file="fixtures/valid-todo.json"
    if validate_schema "$test_file"; then
        echo "✅ PASS: Valid schema accepted"
        return 0
    else
        echo "❌ FAIL: Valid schema rejected"
        return 1
    fi
}

# Run all tests
test_valid_schema
test_invalid_schema
test_duplicate_ids
```

### Test Data
- **Location**: tests/fixtures/
- **Naming**: descriptive-scenario.json
- **Coverage**: Valid, invalid, edge cases

## Documentation Conventions

### Comments
- **What vs Why**: Explain WHY, not WHAT (code shows what)
- **Complex Logic**: Comment non-obvious algorithms
- **TODOs**: Use TODO: prefix with GitHub issue link if applicable

### README Structure
1. Overview
2. Installation
3. Quick Start
4. Usage Examples
5. Configuration
6. Troubleshooting
7. Contributing
8. License

### API Documentation
- All public functions documented
- Parameter types and constraints specified
- Return values and error codes documented
- Usage examples provided
