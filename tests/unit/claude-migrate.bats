#!/usr/bin/env bats
# =============================================================================
# claude-migrate.bats - Unit tests for claude-migrate.sh
# =============================================================================
# Tests the CLEO migration detection and execution for T915-T918
# =============================================================================

setup_file() {
    load '../test_helper/common_setup'
    common_setup_file

    # Override HOME to avoid affecting real user data
    export ORIGINAL_HOME="$HOME"
}

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    common_setup_per_test

    # Create isolated HOME for each test
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "$HOME"

    # Suppress migration warnings
    export _CLEO_MIGRATION_WARNING_SHOWN=1

    # Clear legacy env vars
    unset CLAUDE_TODO_HOME CLAUDE_TODO_DIR CLAUDE_TODO_FORMAT CLAUDE_TODO_DEBUG 2>/dev/null || true
}

teardown() {
    common_teardown_per_test
    export HOME="$ORIGINAL_HOME"
}

teardown_file() {
    common_teardown_file
}

# =============================================================================
# Help and Basic Command Tests
# =============================================================================

@test "claude-migrate --help shows usage" {
    run "$SCRIPTS_DIR/claude-migrate.sh" --help
    assert_success
    assert_output --partial "Usage: cleo claude-migrate"
    assert_output --partial "--check"
    assert_output --partial "--global"
    assert_output --partial "--project"
    assert_output --partial "--all"
}

@test "claude-migrate -h shows usage" {
    run "$SCRIPTS_DIR/claude-migrate.sh" -h
    assert_success
    assert_output --partial "Usage: cleo claude-migrate"
}

@test "claude-migrate without mode shows error" {
    run "$SCRIPTS_DIR/claude-migrate.sh"
    assert_failure
    assert_output --partial "Must specify --check, --global, --project, or --all"
}

@test "claude-migrate with unknown option shows error" {
    run "$SCRIPTS_DIR/claude-migrate.sh" --invalid
    assert_failure
    assert_output --partial "Unknown option"
}

# =============================================================================
# CHECK MODE - NO LEGACY
# =============================================================================

@test "claude-migrate --check exits 1 when no legacy found" {
    # Ensure no legacy directories exist
    rm -rf "$HOME/.claude-todo" 2>/dev/null || true

    # Work in temp dir with no .claude
    cd "$TEST_TEMP_DIR"
    rm -rf ".claude" 2>/dev/null || true

    run "$SCRIPTS_DIR/claude-migrate.sh" --check
    assert_failure 1  # Exit code 1 = no legacy found
}

@test "claude-migrate --check --format json returns valid JSON when no legacy" {
    rm -rf "$HOME/.claude-todo" 2>/dev/null || true
    cd "$TEST_TEMP_DIR"
    rm -rf ".claude" 2>/dev/null || true

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_failure 1  # No legacy found

    # Store output for multiple jq checks
    local json_output="$output"

    # Verify JSON structure
    jq -e '.migrationNeeded == false' <<< "$json_output"
    jq -e '.global.found == false' <<< "$json_output"
    jq -e '.project.found == false' <<< "$json_output"
}

@test "claude-migrate --check text output shows clean state" {
    rm -rf "$HOME/.claude-todo" 2>/dev/null || true
    cd "$TEST_TEMP_DIR"
    rm -rf ".claude" 2>/dev/null || true

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format text
    assert_failure 1
    assert_output --partial "No migration needed"
}

# =============================================================================
# CHECK MODE - LEGACY GLOBAL
# =============================================================================

@test "claude-migrate --check exits 0 when legacy global found" {
    # Create legacy global directory
    mkdir -p "$HOME/.claude-todo"
    touch "$HOME/.claude-todo/todo.json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check
    assert_success  # Exit code 0 = legacy found
}

@test "claude-migrate --check --format json detects legacy global" {
    mkdir -p "$HOME/.claude-todo"
    echo '{"tasks":[]}' > "$HOME/.claude-todo/todo.json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    # Store output for multiple jq checks
    local json_output="$output"

    # Verify JSON structure
    jq -e '.migrationNeeded == true' <<< "$json_output"
    jq -e '.global.found == true' <<< "$json_output"
    jq -e '.global.hasTodo == true' <<< "$json_output"
}

@test "claude-migrate --check detects legacy global config" {
    mkdir -p "$HOME/.claude-todo"
    echo '{}' > "$HOME/.claude-todo/todo-config.json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    local json_output="$output"
    jq -e '.global.hasConfig == true' <<< "$json_output"
}

# =============================================================================
# CHECK MODE - LEGACY PROJECT
# =============================================================================

@test "claude-migrate --check exits 0 when legacy project found" {
    # Create legacy project directory in temp location
    cd "$TEST_TEMP_DIR"
    mkdir -p ".claude"
    touch ".claude/todo.json"

    run "$SCRIPTS_DIR/claude-migrate.sh" --check
    assert_success
}

@test "claude-migrate --check --format json detects legacy project" {
    cd "$TEST_TEMP_DIR"
    mkdir -p ".claude"
    echo '{"tasks":[]}' > ".claude/todo.json"

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    local json_output="$output"
    jq -e '.migrationNeeded == true' <<< "$json_output"
    jq -e '.project.found == true' <<< "$json_output"
    jq -e '.project.hasTodo == true' <<< "$json_output"
}

@test "claude-migrate --check detects legacy project with all files" {
    cd "$TEST_TEMP_DIR"
    mkdir -p ".claude"
    echo '{}' > ".claude/todo.json"
    echo '{}' > ".claude/todo-config.json"
    echo '[]' > ".claude/todo-log.json"
    echo '{"archived":[]}' > ".claude/todo-archive.json"

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    local json_output="$output"
    jq -e '.project.hasTodo == true' <<< "$json_output"
    jq -e '.project.hasConfig == true' <<< "$json_output"
    jq -e '.project.hasLog == true' <<< "$json_output"
    jq -e '.project.hasArchive == true' <<< "$json_output"
}

# =============================================================================
# CHECK MODE - LEGACY ENVIRONMENT
# =============================================================================

@test "claude-migrate --check detects CLAUDE_TODO_HOME" {
    export CLAUDE_TODO_HOME="/old/path"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    # Note: env detection alone triggers legacy found
    assert_success

    local json_output="$output"
    jq -e '.environment.found == true' <<< "$json_output"

    unset CLAUDE_TODO_HOME
}

@test "claude-migrate --check detects multiple legacy env vars" {
    export CLAUDE_TODO_HOME="/old/path"
    export CLAUDE_TODO_FORMAT="json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    local json_output="$output"
    jq -e '.environment.count >= 2' <<< "$json_output"

    unset CLAUDE_TODO_HOME CLAUDE_TODO_FORMAT
}

@test "claude-migrate --check shows clean env when no legacy vars" {
    unset CLAUDE_TODO_HOME CLAUDE_TODO_DIR CLAUDE_TODO_FORMAT CLAUDE_TODO_DEBUG 2>/dev/null || true

    cd "$TEST_TEMP_DIR"
    rm -rf ".claude" "$HOME/.claude-todo" 2>/dev/null || true

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    # No legacy at all

    local json_output="$output"
    jq -e '.environment.found == false' <<< "$json_output"
}

# =============================================================================
# CHECK MODE - COMBINED DETECTION
# =============================================================================

@test "claude-migrate --check detects both global and project legacy" {
    mkdir -p "$HOME/.claude-todo"
    echo '{}' > "$HOME/.claude-todo/todo.json"

    cd "$TEST_TEMP_DIR"
    mkdir -p ".claude"
    echo '{}' > ".claude/todo.json"

    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format json
    assert_success

    local json_output="$output"
    jq -e '.global.found == true' <<< "$json_output"
    jq -e '.project.found == true' <<< "$json_output"
}

# =============================================================================
# UNIMPLEMENTED MODES (T916-T918)
# =============================================================================

@test "claude-migrate --global shows not implemented" {
    run "$SCRIPTS_DIR/claude-migrate.sh" --global
    assert_failure
    assert_output --partial "not yet implemented"
}

@test "claude-migrate --project shows not implemented" {
    run "$SCRIPTS_DIR/claude-migrate.sh" --project
    assert_failure
    assert_output --partial "not yet implemented"
}

@test "claude-migrate --all shows not implemented" {
    run "$SCRIPTS_DIR/claude-migrate.sh" --all
    assert_failure
    assert_output --partial "not yet implemented"
}

# =============================================================================
# VERBOSE MODE
# =============================================================================

@test "claude-migrate --check --verbose shows extra details" {
    mkdir -p "$HOME/.claude-todo"
    touch "$HOME/.claude-todo/todo.json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format text --verbose
    assert_success
    assert_output --partial "Run: cleo claude-migrate"
}

@test "claude-migrate --check -v works as verbose shorthand" {
    mkdir -p "$HOME/.claude-todo"
    touch "$HOME/.claude-todo/todo.json"

    cd "$TEST_TEMP_DIR"
    run "$SCRIPTS_DIR/claude-migrate.sh" --check --format text -v
    assert_success
    assert_output --partial "Run: cleo claude-migrate"
}
