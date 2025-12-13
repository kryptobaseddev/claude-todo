# Backup Test Cases - Detailed Specifications

Concrete test case specifications with expected inputs, outputs, and assertions.

## Unit Tests: lib/backup.sh

### Section A: Configuration Loading

#### Test 1.1: _load_backup_config uses defaults when config missing
```bash
@test "_load_backup_config uses defaults when config missing" {
    # Setup
    rm -f "$CONFIG_FILE"

    # Execute
    _load_backup_config

    # Assert
    [ "$BACKUP_ENABLED" = "true" ]
    [ "$BACKUP_DIR" = ".claude/backups" ]
    [ "$MAX_SNAPSHOTS" = "10" ]
    [ "$MAX_SAFETY_BACKUPS" = "5" ]
    [ "$MAX_INCREMENTAL" = "10" ]
    [ "$MAX_ARCHIVE_BACKUPS" = "3" ]
    [ "$SAFETY_RETENTION_DAYS" = "7" ]
}
```

**Expected Output**: All default values set correctly

---

#### Test 1.2: _load_backup_config overrides with config file values
```bash
@test "_load_backup_config overrides with config file values" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{
  "backup": {
    "enabled": false,
    "directory": "custom/backups",
    "maxSnapshots": 20,
    "maxSafetyBackups": 10,
    "maxIncremental": 15,
    "maxArchiveBackups": 5,
    "safetyRetentionDays": 14
  }
}
EOF

    # Execute
    _load_backup_config

    # Assert
    [ "$BACKUP_ENABLED" = "false" ]
    [ "$BACKUP_DIR" = "custom/backups" ]
    [ "$MAX_SNAPSHOTS" = "20" ]
    [ "$MAX_SAFETY_BACKUPS" = "10" ]
    [ "$MAX_INCREMENTAL" = "15" ]
    [ "$MAX_ARCHIVE_BACKUPS" = "5" ]
    [ "$SAFETY_RETENTION_DAYS" = "14" ]
}
```

**Expected Output**: Config values override defaults

---

#### Test 1.3: _load_backup_config handles invalid config gracefully
```bash
@test "_load_backup_config handles invalid config gracefully" {
    # Setup
    echo "invalid json" > "$CONFIG_FILE"

    # Execute
    _load_backup_config

    # Assert - should fall back to defaults
    [ "$BACKUP_ENABLED" = "true" ]
    [ "$MAX_SNAPSHOTS" = "10" ]
}
```

**Expected Output**: Falls back to defaults on invalid JSON

---

### Section B: Metadata Generation

#### Test 2.1: _create_backup_metadata generates valid JSON structure
```bash
@test "_create_backup_metadata generates valid JSON structure" {
    # Setup
    local files_json='[{"source":"todo.json","backup":"todo.json","size":1024,"checksum":"abc123"}]'

    # Execute
    local metadata
    metadata=$(_create_backup_metadata "snapshot" "manual" "backup" "$files_json" 1024)

    # Assert
    assert_valid_json "$metadata"
    echo "$metadata" | jq -e '.backupType' > /dev/null
    echo "$metadata" | jq -e '.timestamp' > /dev/null
    echo "$metadata" | jq -e '.version' > /dev/null
    echo "$metadata" | jq -e '.trigger' > /dev/null
    echo "$metadata" | jq -e '.operation' > /dev/null
    echo "$metadata" | jq -e '.files' > /dev/null
    echo "$metadata" | jq -e '.totalSize' > /dev/null
}
```

**Expected Output**: Valid JSON with all required fields

---

#### Test 2.2: _create_backup_metadata includes correct values
```bash
@test "_create_backup_metadata includes correct values" {
    # Setup
    local files_json='[]'

    # Execute
    local metadata
    metadata=$(_create_backup_metadata "safety" "auto" "complete" "$files_json" 512)

    # Assert
    local backup_type
    backup_type=$(echo "$metadata" | jq -r '.backupType')
    [ "$backup_type" = "safety" ]

    local trigger
    trigger=$(echo "$metadata" | jq -r '.trigger')
    [ "$trigger" = "auto" ]

    local operation
    operation=$(echo "$metadata" | jq -r '.operation')
    [ "$operation" = "complete" ]

    local size
    size=$(echo "$metadata" | jq -r '.totalSize')
    [ "$size" = "512" ]
}
```

**Expected Output**: Metadata contains provided values

---

### Section C: Validation

#### Test 3.1: _validate_backup accepts valid backup directory
```bash
@test "_validate_backup accepts valid backup directory" {
    # Setup
    local backup_dir="$BACKUPS_ROOT/test_backup"
    mkdir -p "$backup_dir"

    # Create valid metadata
    cat > "$backup_dir/metadata.json" << 'EOF'
{
  "backupType": "snapshot",
  "timestamp": "2025-12-13T10:00:00Z",
  "version": "0.9.8",
  "trigger": "test",
  "operation": "test",
  "files": [],
  "totalSize": 0
}
EOF

    # Create valid backup file
    echo '{"tasks":[]}' > "$backup_dir/todo.json"

    # Execute
    run _validate_backup "$backup_dir"

    # Assert
    assert_success
}
```

**Expected Output**: Validation passes, returns 0

---

#### Test 3.2: _validate_backup rejects backup without metadata
```bash
@test "_validate_backup rejects backup without metadata" {
    # Setup
    local backup_dir="$BACKUPS_ROOT/test_backup"
    mkdir -p "$backup_dir"
    # No metadata.json created

    # Execute
    run _validate_backup "$backup_dir"

    # Assert
    assert_failure
    assert_output --partial "Backup metadata not found"
}
```

**Expected Output**: Validation fails with error message

---

### Section D: Snapshot Backups

#### Test 4.1: create_snapshot_backup creates all system files
```bash
@test "create_snapshot_backup creates all system files" {
    # Setup
    create_independent_tasks  # Creates valid todo.json

    # Execute
    run create_snapshot_backup

    # Assert
    assert_success

    local backup_path="$output"
    assert_file_exists "$backup_path/metadata.json"
    assert_file_exists "$backup_path/todo.json"
    assert_file_exists "$backup_path/todo-archive.json"
    assert_file_exists "$backup_path/todo-config.json"
    assert_file_exists "$backup_path/todo-log.json"
}
```

**Expected Output**:
- Backup directory created
- All system files copied
- metadata.json created
- Backup path returned

---

#### Test 4.2: create_snapshot_backup validates files before backup
```bash
@test "create_snapshot_backup validates files before backup" {
    # Setup
    create_independent_tasks
    echo "invalid json" > "$TODO_FILE"  # Corrupt file

    # Execute
    run create_snapshot_backup

    # Assert
    assert_failure
}
```

**Expected Output**: Backup fails if source files are invalid

---

#### Test 4.3: create_snapshot_backup respects BACKUP_ENABLED=false
```bash
@test "create_snapshot_backup respects BACKUP_ENABLED=false" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{
  "backup": {
    "enabled": false
  }
}
EOF

    # Execute
    run create_snapshot_backup

    # Assert
    assert_failure
    assert_output --partial "Backups are disabled"
}
```

**Expected Output**: Backup skipped with warning message

---

#### Test 4.4: create_snapshot_backup triggers rotation
```bash
@test "create_snapshot_backup triggers rotation" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{
  "backup": {
    "maxSnapshots": 2
  }
}
EOF

    create_independent_tasks

    # Create 2 existing backups
    create_multiple_backups "snapshot" 2

    # Execute - should create 3rd and delete oldest
    run create_snapshot_backup

    # Assert
    assert_success

    # Should have exactly 2 backups now (oldest deleted)
    assert_backup_count "snapshot" 2
}
```

**Expected Output**: Old backups rotated after creation

---

### Section E: Safety Backups

#### Test 5.1: create_safety_backup requires file path
```bash
@test "create_safety_backup requires file path" {
    # Execute
    run create_safety_backup

    # Assert
    assert_failure
    assert_output --partial "File path required"
}
```

**Expected Output**: Error if no file path provided

---

#### Test 5.2: create_safety_backup returns error if file missing
```bash
@test "create_safety_backup returns error if file missing" {
    # Execute
    run create_safety_backup "/nonexistent/file.json" "test"

    # Assert
    assert_failure
    assert_output --partial "File not found"
}
```

**Expected Output**: Error if file doesn't exist

---

#### Test 5.3: create_safety_backup silently skips if BACKUP_ENABLED=false
```bash
@test "create_safety_backup silently skips if BACKUP_ENABLED=false" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "enabled": false } }
EOF
    create_independent_tasks

    # Execute
    run create_safety_backup "$TODO_FILE" "test"

    # Assert - should return 0 (success) but not create backup
    assert_success

    # No backup created
    [ ! -d "$BACKUPS_ROOT/safety" ] || assert_backup_count "safety" 0
}
```

**Expected Output**: Returns 0 but creates no backup

---

### Section F: Rotation

#### Test 6.1: rotate_backups deletes oldest when exceeding limit
```bash
@test "rotate_backups deletes oldest when exceeding limit" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "maxSnapshots": 3 } }
EOF

    # Create 5 backups (over limit by 2)
    create_multiple_backups "snapshot" 5

    # Execute
    run rotate_backups "snapshot"

    # Assert
    assert_success
    assert_backup_count "snapshot" 3
}
```

**Expected Output**: Oldest 2 backups deleted, 3 remain

---

#### Test 6.2: rotate_backups respects different limits per type
```bash
@test "rotate_backups respects different limits per type" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{
  "backup": {
    "maxSnapshots": 5,
    "maxSafetyBackups": 3,
    "maxIncremental": 10
  }
}
EOF

    create_multiple_backups "snapshot" 10
    create_multiple_backups "safety" 10
    create_multiple_backups "incremental" 10

    # Execute
    rotate_backups "snapshot"
    rotate_backups "safety"
    rotate_backups "incremental"

    # Assert
    assert_backup_count "snapshot" 5
    assert_backup_count "safety" 3
    assert_backup_count "incremental" 10
}
```

**Expected Output**: Each type rotated according to its limit

---

#### Test 6.3: rotate_backups never deletes migration backups
```bash
@test "rotate_backups never deletes migration backups" {
    # Setup
    create_multiple_backups "migration" 100

    # Execute
    run rotate_backups "migration"

    # Assert
    assert_success
    assert_backup_count "migration" 100  # All still there
}
```

**Expected Output**: All migration backups preserved

---

#### Test 6.4: rotate_backups skips when max_backups=0 (unlimited)
```bash
@test "rotate_backups skips when max_backups=0 (unlimited)" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "maxSnapshots": 0 } }
EOF

    create_multiple_backups "snapshot" 50

    # Execute
    run rotate_backups "snapshot"

    # Assert
    assert_success
    assert_backup_count "snapshot" 50  # No deletion
}
```

**Expected Output**: No rotation when limit is 0

---

### Section G: Migration Backups

#### Test 7.1: create_migration_backup always runs (ignores BACKUP_ENABLED)
```bash
@test "create_migration_backup always runs (ignores BACKUP_ENABLED)" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "enabled": false } }
EOF
    create_independent_tasks

    # Execute
    run create_migration_backup "0.10.0"

    # Assert
    assert_success
    local backup_path="$output"
    assert_backup_exists "$backup_path"
}
```

**Expected Output**: Backup created even when BACKUP_ENABLED=false

---

#### Test 7.2: create_migration_backup sets neverDelete=true
```bash
@test "create_migration_backup sets neverDelete=true" {
    # Setup
    create_independent_tasks

    # Execute
    run create_migration_backup "0.10.0"

    # Assert
    assert_success
    local backup_path="$output"

    local never_delete
    never_delete=$(jq -r '.neverDelete' "$backup_path/metadata.json")
    [ "$never_delete" = "true" ]
}
```

**Expected Output**: metadata.json has neverDelete=true

---

## Integration Tests: Script Integration

### init.sh Integration

#### Test 8.1: init.sh creates backup directory taxonomy
```bash
@test "init.sh creates backup directory taxonomy" {
    # Execute
    run bash "$INIT_SCRIPT" --force

    # Assert
    assert_success
    assert_dir_exists ".claude/backups"
    assert_dir_exists ".claude/backups/snapshot"
    assert_dir_exists ".claude/backups/safety"
    assert_dir_exists ".claude/backups/incremental"
    assert_dir_exists ".claude/backups/archive"
    assert_dir_exists ".claude/backups/migration"
}
```

**Expected Output**:
- `.claude/backups/` created
- All 5 subdirectories created

---

#### Test 8.2: init.sh handles existing directories gracefully
```bash
@test "init.sh handles existing directories gracefully" {
    # Setup - create directories first
    mkdir -p ".claude/backups/snapshot"

    # Execute
    run bash "$INIT_SCRIPT" --force

    # Assert - should not fail
    assert_success
    assert_dir_exists ".claude/backups/snapshot"
}
```

**Expected Output**: No error when directories exist

---

### complete-task.sh Integration

#### Test 9.1: complete-task.sh still creates legacy backups
```bash
@test "complete-task.sh still creates legacy backups" {
    # Setup
    create_independent_tasks

    # Execute
    run bash "$COMPLETE_SCRIPT" T001 --skip-notes

    # Assert
    assert_success
    assert_dir_exists ".claude/.backups"
    assert_file_exists ".claude/.backups/todo.json."*
}
```

**Expected Output**: Legacy `.claude/.backups/` directory still used

---

#### Test 9.2: complete-task.sh rotates legacy backups
```bash
@test "complete-task.sh rotates legacy backups" {
    # Setup
    create_independent_tasks

    # Create 15 existing legacy backups
    for i in {1..15}; do
        sleep 0.1
        cp "$TODO_FILE" ".claude/.backups/todo.json.$(date +%Y%m%d_%H%M%S)"
    done

    # Execute - should trigger rotation (max 10)
    run bash "$COMPLETE_SCRIPT" T001 --skip-notes

    # Assert
    local backup_count
    backup_count=$(find ".claude/.backups" -name "todo.json.*" | wc -l)
    [ "$backup_count" -le 10 ]
}
```

**Expected Output**: Old backups rotated, max 10 kept

---

## Edge Case Tests

### First Backup Scenarios

#### Test 10.1: create_snapshot_backup with no existing backups
```bash
@test "create_snapshot_backup with no existing backups" {
    # Setup
    create_independent_tasks
    # No existing backups

    # Execute
    run create_snapshot_backup

    # Assert
    assert_success
    assert_backup_count "snapshot" 1
}
```

**Expected Output**: First backup created successfully

---

### Rotation at Limits

#### Test 11.1: rotate_backups with exactly max backups (no deletion)
```bash
@test "rotate_backups with exactly max backups (no deletion)" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "maxSnapshots": 5 } }
EOF

    create_multiple_backups "snapshot" 5

    # Execute
    run rotate_backups "snapshot"

    # Assert
    assert_success
    assert_backup_count "snapshot" 5  # No deletion
}
```

**Expected Output**: All backups preserved at exact limit

---

#### Test 11.2: rotate_backups with one over limit (delete 1)
```bash
@test "rotate_backups with one over limit (delete 1)" {
    # Setup
    cat > "$CONFIG_FILE" << 'EOF'
{ "backup": { "maxSnapshots": 5 } }
EOF

    create_multiple_backups "snapshot" 6

    # Execute
    run rotate_backups "snapshot"

    # Assert
    assert_success
    assert_backup_count "snapshot" 5
}
```

**Expected Output**: Oldest backup deleted, 5 remain

---

### Error Handling

#### Test 12.1: create_snapshot_backup fails gracefully with permission denied
```bash
@test "create_snapshot_backup fails gracefully with permission denied" {
    # Setup
    create_independent_tasks
    mkdir -p ".claude/backups/snapshot"
    chmod 000 ".claude/backups/snapshot"  # Remove all permissions

    # Execute
    run create_snapshot_backup

    # Assert
    assert_failure
    # Clean up
    chmod 755 ".claude/backups/snapshot"
}
```

**Expected Output**: Clear error message about permissions

---

#### Test 12.2: restore_backup creates safety backup before restore
```bash
@test "restore_backup creates safety backup before restore" {
    # Setup
    create_independent_tasks

    # Create a snapshot backup
    local snapshot_path
    snapshot_path=$(create_snapshot_backup)

    # Modify todo.json
    echo '{"tasks":[]}' > "$TODO_FILE"

    # Execute restore
    run restore_backup "$snapshot_path"

    # Assert
    assert_success

    # Safety backup should have been created
    assert_backup_count "safety" 1
}
```

**Expected Output**: Safety backup created before restore

---

## Regression Tests

### Legacy Compatibility

#### Test 13.1: legacy .claude/.backups/ still accessible
```bash
@test "legacy .claude/.backups/ still accessible" {
    # Setup
    mkdir -p ".claude/.backups"
    cp "$TODO_FILE" ".claude/.backups/todo.json.20251213_120000"

    # Execute - should not interfere with legacy backups
    run create_snapshot_backup

    # Assert
    assert_success
    assert_file_exists ".claude/.backups/todo.json.20251213_120000"
}
```

**Expected Output**: Legacy backups coexist with new taxonomy

---

### Atomic Transactions

#### Test 14.1: complete-task.sh preserves atomic write pattern
```bash
@test "complete-task.sh preserves atomic write pattern" {
    # Setup
    create_independent_tasks

    # Execute
    run bash "$COMPLETE_SCRIPT" T001 --skip-notes

    # Assert
    assert_success

    # Verify checksum updated (indicates atomic write)
    local checksum
    checksum=$(jq -r '._meta.checksum' "$TODO_FILE")
    [ -n "$checksum" ]
    [ "$checksum" != "test123" ]  # Changed from initial
}
```

**Expected Output**: Checksum recalculated after completion

---

## Test Execution Examples

### Running Tests

```bash
# Run all backup unit tests
$ bats tests/unit/backup.bats
 ✓ _load_backup_config uses defaults when config missing
 ✓ _load_backup_config overrides with config file values
 ✓ _create_backup_metadata generates valid JSON structure
 ✓ create_snapshot_backup creates all system files
 ✓ create_snapshot_backup triggers rotation
 ✓ create_safety_backup requires file path
 ✓ rotate_backups deletes oldest when exceeding limit
 ✓ rotate_backups never deletes migration backups

48 tests, 0 failures

# Run integration tests
$ bats tests/integration/backup-integration.bats
 ✓ init.sh creates backup directory taxonomy
 ✓ init.sh handles existing directories gracefully
 ✓ complete-task.sh still creates legacy backups
 ✓ complete-task.sh rotates legacy backups

10 tests, 0 failures

# Run edge case tests
$ bats tests/unit/backup-edge-cases.bats
 ✓ create_snapshot_backup with no existing backups
 ✓ rotate_backups with exactly max backups (no deletion)
 ✓ rotate_backups with one over limit (delete 1)
 ✓ create_snapshot_backup fails gracefully with permission denied

20 tests, 0 failures

# Run regression tests
$ bats tests/integration/backup-regression.bats
 ✓ legacy .claude/.backups/ still accessible
 ✓ complete-task.sh preserves atomic write pattern

10 tests, 0 failures
```

---

## Related Documentation

- **Test Strategy**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_STRATEGY.md`
- **Test Summary**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_SUMMARY.md`
- **Test Roadmap**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_ROADMAP.md`
- **Backup Library**: `/mnt/projects/claude-todo/lib/backup.sh`
