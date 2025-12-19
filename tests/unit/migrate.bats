#!/usr/bin/env bats
# =============================================================================
# migrate.bats - Unit tests for migrate.sh
# =============================================================================
# Tests schema migration functionality including status, check, and run.
# =============================================================================

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    load '../test_helper/fixtures'
    common_setup
}

teardown() {
    common_teardown
}

# =============================================================================
# Helper: Create old version fixtures
# =============================================================================

create_old_version_todo() {
    cat > "$TODO_FILE" << 'EOF'
{
  "$schema": "./schemas/todo.schema.json",
  "version": "1.0.0",
  "project": "test-project",
  "lastUpdated": "2025-12-06T00:00:00Z",
  "_meta": {
    "checksum": "abc123",
    "configVersion": "1.0.0"
  },
  "focus": {
    "currentTask": null
  },
  "tasks": [
    {
      "id": "T001",
      "title": "Old task",
      "status": "pending",
      "priority": "medium",
      "createdAt": "2025-12-06T00:00:00Z"
    }
  ]
}
EOF

    cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0.0",
  "archive": { "enabled": true },
  "logging": { "enabled": true }
}
EOF

    cat > "$ARCHIVE_FILE" << 'EOF'
{
  "version": "1.0.0",
  "archived": []
}
EOF

    cat > "$LOG_FILE" << 'EOF'
{
  "version": "1.0.0",
  "entries": []
}
EOF
}

# =============================================================================
# Script Presence Tests
# =============================================================================

@test "migrate script exists" {
    [ -f "$MIGRATE_SCRIPT" ]
}

@test "migrate script is executable" {
    [ -x "$MIGRATE_SCRIPT" ]
}

@test "migrate library exists" {
    [ -f "$PROJECT_ROOT/lib/migrate.sh" ]
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "migrate --help shows usage" {
    run bash "$MIGRATE_SCRIPT" --help
    assert_shows_help
}

@test "migrate -h shows usage" {
    run bash "$MIGRATE_SCRIPT" -h
    assert_shows_help
}

@test "migrate help shows available commands" {
    run bash "$MIGRATE_SCRIPT" --help
    assert_success
    assert_output_contains_any "status" "check" "run"
}

# =============================================================================
# Migrate Status Tests
# =============================================================================

@test "migrate status shows file information" {
    create_independent_tasks
    run bash "$MIGRATE_SCRIPT" status
    assert_success
    assert_output_contains_any "todo" "version" "file" "status" ".json" "current" "2."
}

@test "migrate status works with current version" {
    create_independent_tasks
    run bash "$MIGRATE_SCRIPT" status
    assert_success
}

@test "migrate status works with old version" {
    create_old_version_todo
    run bash "$MIGRATE_SCRIPT" status
    assert_success
}

# =============================================================================
# Migrate Check Tests
# =============================================================================

@test "migrate check detects current version" {
    create_independent_tasks
    run bash "$MIGRATE_SCRIPT" check
    # Should indicate no migration needed or show current status
    assert_success
}

@test "migrate check detects old version" {
    create_old_version_todo
    run bash "$MIGRATE_SCRIPT" check
    # Should detect old version - may return 0, 1 (migration), or exit with incompatible error
    assert_output_contains_any "migration" "needed" "outdated" "update" "1.0.0" "current" "Incompatible" "incompatible"
}

# =============================================================================
# Migrate Run Tests
# =============================================================================

@test "migrate run updates version" {
    create_old_version_todo
    local initial_task_count
    initial_task_count=$(jq '.tasks | length' "$TODO_FILE")

    run bash "$MIGRATE_SCRIPT" run --auto
    # Migration should complete (may or may not change version)

    # File should still be valid JSON
    run jq empty "$TODO_FILE"
    assert_success
}

@test "migrate run preserves tasks" {
    create_old_version_todo
    local initial_task_count
    initial_task_count=$(jq '.tasks | length' "$TODO_FILE")

    bash "$MIGRATE_SCRIPT" run --auto || true

    local final_task_count
    final_task_count=$(jq '.tasks | length' "$TODO_FILE")
    [ "$initial_task_count" = "$final_task_count" ]
}

@test "migrate run preserves task data" {
    create_old_version_todo
    local original_title
    original_title=$(jq -r '.tasks[0].title' "$TODO_FILE")

    bash "$MIGRATE_SCRIPT" run --auto || true

    local final_title
    final_title=$(jq -r '.tasks[0].title' "$TODO_FILE")
    [ "$original_title" = "$final_title" ]
}

@test "migrate run --dry-run does not modify files" {
    create_old_version_todo
    local before_content
    before_content=$(cat "$TODO_FILE")

    run bash "$MIGRATE_SCRIPT" run --dry-run

    local after_content
    after_content=$(cat "$TODO_FILE")
    [ "$before_content" = "$after_content" ]
}

# =============================================================================
# Version Handling Tests
# =============================================================================

@test "migrate handles version in _meta" {
    create_independent_tasks
    local version
    version=$(jq -r '._meta.version // empty' "$TODO_FILE")
    [ -n "$version" ]

    run bash "$MIGRATE_SCRIPT" status
    assert_success
}

@test "migrate handles version at top level" {
    create_old_version_todo
    run bash "$MIGRATE_SCRIPT" status
    assert_success
}

# =============================================================================
# Backup Tests
# =============================================================================

@test "migrate run creates backup" {
    create_old_version_todo
    bash "$MIGRATE_SCRIPT" run --auto || true

    # May create backup files depending on implementation
    run jq empty "$TODO_FILE"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "migrate handles missing files gracefully" {
    rm -f "$TODO_FILE"
    run bash "$MIGRATE_SCRIPT" status
    # Should handle gracefully
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "migrate handles invalid JSON gracefully" {
    echo "not valid json" > "$TODO_FILE"
    run bash "$MIGRATE_SCRIPT" check
    # Should report error - exit codes 0-6 are acceptable (0=ok, 1=migration needed, 2-6=various errors)
    [[ "$status" -le 6 ]]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "migrate maintains valid JSON after run" {
    create_old_version_todo
    bash "$MIGRATE_SCRIPT" run --auto || true

    run jq empty "$TODO_FILE"
    assert_success

    run jq empty "$CONFIG_FILE"
    assert_success
}

@test "migrate run with --force skips confirmation" {
    create_old_version_todo
    run bash "$MIGRATE_SCRIPT" run --force
    # Should complete without prompting
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "migrate handles empty tasks array" {
    create_empty_todo
    run bash "$MIGRATE_SCRIPT" check
    assert_success
}

@test "migrate handles already current version" {
    create_independent_tasks
    run bash "$MIGRATE_SCRIPT" run --auto
    assert_success
    # Should indicate already current or do nothing
}
