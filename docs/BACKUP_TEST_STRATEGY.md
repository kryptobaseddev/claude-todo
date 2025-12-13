# Backup System Test Strategy

Comprehensive testing strategy for backup integration (T162/T163).

## Overview

Test the integration of `/mnt/projects/claude-todo/lib/backup.sh` with operational scripts:
- `complete-task.sh` (safety backups)
- `archive.sh` (archive backups)
- `migrate.sh` (migration backups)
- `init.sh` (directory structure)

## Test Inventory

### 1. Unit Tests for lib/backup.sh

**File**: `/mnt/projects/claude-todo/tests/unit/backup.bats`

**Priority**: Critical (🔴)

#### Test Cases

##### 1.1 Configuration Loading
- `_load_backup_config` uses defaults when config missing
- `_load_backup_config` overrides with config file values
- `_load_backup_config` handles invalid config gracefully

##### 1.2 Metadata Generation
- `_create_backup_metadata` generates valid JSON structure
- Metadata includes all required fields (backupType, timestamp, version, trigger, operation, files, totalSize)
- Metadata uses current timestamp (not hardcoded)
- Metadata includes correct version string

##### 1.3 Backup Validation
- `_validate_backup` accepts valid backup directory with metadata.json
- `_validate_backup` rejects backup without metadata.json
- `_validate_backup` rejects backup with invalid JSON files
- `_validate_backup` rejects non-existent backup directory

##### 1.4 Snapshot Backups (create_snapshot_backup)
- Creates backup with all system files (todo.json, todo-archive.json, todo-config.json, todo-log.json)
- Returns backup path on success
- Creates metadata.json with correct structure
- Validates backed up files before committing
- Skips invalid JSON files with warning
- Respects BACKUP_ENABLED=false (returns error)
- Triggers rotation after creation
- Logs backup_created operation

##### 1.5 Safety Backups (create_safety_backup)
- Creates backup of single file before operation
- Requires file path argument (fails if missing)
- Returns error if file doesn't exist
- Silently skips if BACKUP_ENABLED=false (returns 0)
- Creates metadata with operation name
- Does NOT trigger rotation (rotation handled separately)

##### 1.6 Incremental Backups (create_incremental_backup)
- Creates versioned backup of single file
- Includes file checksum in metadata
- Triggers rotation automatically
- Respects BACKUP_ENABLED=false

##### 1.7 Archive Backups (create_archive_backup)
- Backs up todo.json and todo-archive.json only
- Creates metadata with "archive" operation
- Triggers rotation automatically
- Respects BACKUP_ENABLED=false

##### 1.8 Migration Backups (create_migration_backup)
- ALWAYS creates backup (ignores BACKUP_ENABLED)
- Includes version string in backup ID
- Sets neverDelete=true in metadata
- Never triggers rotation
- Backs up all system files

##### 1.9 Backup Rotation (rotate_backups)
- Deletes oldest backups when exceeding maxSnapshots
- Respects different limits per backup type
- Never rotates migration backups
- Skips rotation when max_backups=0 (unlimited)
- Uses mtime-based sorting (oldest first)
- Handles both GNU find (Linux) and BSD find (macOS)

##### 1.10 Backup Listing (list_backups)
- Lists all backups when filter_type="all"
- Lists specific type when filter provided
- Returns empty list for non-existent backup directory
- Sorts by modification time

##### 1.11 Backup Restoration (restore_backup)
- Accepts backup directory path
- Accepts backup ID and searches all types
- Creates safety backup before restoring
- Validates backup before restoration
- Returns error if backup not found
- Returns error if validation fails
- Logs backup_restored operation

##### 1.12 Metadata Retrieval (get_backup_metadata)
- Returns metadata JSON for valid backup
- Returns error if metadata.json missing
- Returns error if backup_path not provided

##### 1.13 Backup Pruning (prune_backups)
- Rotates all backup types
- Prunes safety backups by retention days
- Uses SAFETY_RETENTION_DAYS configuration
- Handles cutoff timestamp calculation correctly

---

### 2. Integration Tests for Script Integration

**File**: `/mnt/projects/claude-todo/tests/integration/backup-integration.bats`

**Priority**: Critical (🔴)

#### Test Cases

##### 2.1 complete-task.sh Integration
- **Existing backup creation**: Verify complete-task.sh still creates legacy `.backups/` directory backup
- **Safety backup NOT created yet**: Current implementation does NOT call lib/backup.sh (future work)
- Backup rotation works for legacy backups (MAX_COMPLETE_BACKUPS=10)
- Verify checksum recalculation after completion

##### 2.2 archive.sh Integration
- **Archive backup NOT created yet**: Current implementation does NOT call lib/backup.sh (future work)
- Atomic transaction creates backup before modification
- Backup includes todo.json and todo-archive.json
- Log entry created for archive operation

##### 2.3 init.sh Integration
- Creates `.claude/backups/` directory structure on init
- Directory taxonomy: `snapshot/`, `safety/`, `incremental/`, `archive/`, `migration/`
- Validates created directories exist
- Does not fail if directories already exist

##### 2.4 migrate.sh Integration
- **Migration backup NOT created yet**: Current implementation does NOT call lib/backup.sh (future work)
- Migration backup MUST be created (critical for schema changes)
- Backup includes all system files before migration

---

### 3. Edge Cases and Error Handling

**File**: `/mnt/projects/claude-todo/tests/unit/backup-edge-cases.bats`

**Priority**: High (🟡)

#### Test Cases

##### 3.1 First Backup Scenarios
- No existing backups: create_snapshot_backup creates first backup
- Rotation with single backup: does not delete
- List backups returns single entry

##### 3.2 Rotation at Limits
- Exactly at limit (maxSnapshots=10, have 10): no deletion
- One over limit (maxSnapshots=10, have 11): deletes 1 oldest
- Multiple over limit (maxSnapshots=5, have 20): deletes 15 oldest

##### 3.3 Restore from Different Backup Types
- Restore from snapshot backup
- Restore from safety backup
- Restore from archive backup
- Restore from migration backup

##### 3.4 Directory Permissions
- Backup creation fails gracefully with permission denied
- Rotation handles read-only backup directories
- Restore fails with helpful error if destination is read-only

##### 3.5 Disk Space Handling
- Backup creation fails if disk full (no partial backups)
- Error message indicates disk space issue
- Atomic write pattern prevents corruption

##### 3.6 Configuration Edge Cases
- BACKUP_ENABLED=false: safety backups silently skip
- BACKUP_ENABLED=false: migration backups STILL created
- Invalid maxSnapshots value (negative, non-numeric): uses default
- Missing config file: uses all defaults

##### 3.7 Concurrent Backup Operations
- Multiple snapshot backups created rapidly (unique timestamps)
- Safety backup during rotation (no race conditions)
- Restore during backup creation (file locking)

##### 3.8 Invalid JSON Handling
- Backup skips files with invalid JSON (with warning)
- Validation catches invalid JSON in backups
- Restore fails if backup contains invalid JSON

##### 3.9 Missing Files
- Backup creation handles missing optional files (todo-log.json)
- Restore handles backups with subset of files
- Validation doesn't require all files to exist

---

### 4. Regression Tests

**File**: `/mnt/projects/claude-todo/tests/integration/backup-regression.bats`

**Priority**: Important (🟡)

#### Test Cases

##### 4.1 Existing Functionality Still Works
- Legacy `.claude/.backups/` directory still created by complete-task.sh
- Legacy backup rotation still works (MAX_COMPLETE_BACKUPS=10)
- Atomic transaction pattern preserved in archive.sh
- Checksum validation after operations

##### 4.2 Old Backup Locations Accessible
- Legacy backups in `.claude/.backups/` remain accessible
- New backups use `.claude/backups/` taxonomy
- Both locations coexist without conflict

##### 4.3 File Locking and Atomicity
- save_json still uses file locking (lib/file-ops.sh)
- Temp file → validate → backup → rename pattern preserved
- No race conditions with concurrent operations

##### 4.4 Validation Still Enforced
- JSON validation before backup creation
- Checksum recalculation after modifications
- Schema validation for generated files

---

## Test File Locations

```
tests/
├── unit/
│   ├── backup.bats                      # Unit tests for lib/backup.sh (NEW)
│   ├── backup-edge-cases.bats           # Edge case tests (NEW)
│   ├── complete-task.bats               # Existing (verify legacy backups)
│   └── archive.bats                     # Existing (verify atomic transaction)
│
├── integration/
│   ├── backup-integration.bats          # Script integration tests (NEW)
│   └── backup-regression.bats           # Regression tests (NEW)
│
└── test_helper/
    ├── common_setup.bash                # Existing (add backup dir setup)
    ├── assertions.bash                  # Existing (add backup assertions)
    └── fixtures.bash                    # Existing (add backup fixtures)
```

---

## Priority Ranking

### Critical (🔴) - Must Have Before Merge

1. **Unit Tests for lib/backup.sh** (backup.bats)
   - Core backup functions (create_*_backup)
   - Rotation logic
   - Validation logic
   - Configuration loading

2. **Integration Tests** (backup-integration.bats)
   - init.sh creates backup directory structure
   - Verify legacy backups still work (complete-task.sh, archive.sh)

3. **Basic Edge Cases** (backup-edge-cases.bats)
   - First backup scenario
   - Rotation at limits
   - Configuration defaults

### Important (🟡) - Should Have for Quality

4. **Restore Functionality Tests** (backup.bats)
   - Restore from different backup types
   - Safety backup before restore
   - Validation before restore

5. **Regression Tests** (backup-regression.bats)
   - Legacy backup locations still work
   - Atomic transaction patterns preserved
   - Checksum validation intact

6. **Advanced Edge Cases** (backup-edge-cases.bats)
   - Disk space handling
   - Permission errors
   - Concurrent operations

### Nice-to-Have (🟢) - Future Improvements

7. **Performance Tests**
   - Backup creation time for large todo.json
   - Rotation performance with 100+ backups
   - Restore performance

8. **Stress Tests**
   - Rapid backup creation (timestamp uniqueness)
   - Very large backup directories
   - Backup corruption recovery

---

## Test Commands to Run

### Run All Backup Tests
```bash
# All new backup tests
bats tests/unit/backup.bats tests/unit/backup-edge-cases.bats tests/integration/backup-integration.bats tests/integration/backup-regression.bats

# All tests (including existing)
./tests/run-all-tests.sh
```

### Run Specific Test Categories
```bash
# Unit tests only
bats tests/unit/backup.bats

# Integration tests only
bats tests/integration/backup-integration.bats

# Edge cases only
bats tests/unit/backup-edge-cases.bats

# Regression tests only
bats tests/integration/backup-regression.bats
```

### Run Tests for Specific Feature
```bash
# Rotation tests
bats tests/unit/backup.bats --filter "rotate"

# Restore tests
bats tests/unit/backup.bats --filter "restore"

# Safety backup tests
bats tests/unit/backup.bats --filter "safety"
```

### CI/CD Integration
```bash
# Run in GitHub Actions
- name: Run Backup Tests
  run: |
    git submodule update --init --recursive
    bats tests/unit/backup*.bats tests/integration/backup*.bats
```

---

## Test Helper Additions Needed

### common_setup.bash

Add backup directory setup:
```bash
_create_test_project() {
    # ... existing code ...

    # Create backup directory structure (T163)
    mkdir -p "${base_dir}/.claude/backups/snapshot"
    mkdir -p "${base_dir}/.claude/backups/safety"
    mkdir -p "${base_dir}/.claude/backups/incremental"
    mkdir -p "${base_dir}/.claude/backups/archive"
    mkdir -p "${base_dir}/.claude/backups/migration"

    export BACKUPS_ROOT="${base_dir}/.claude/backups"
}
```

### assertions.bash

Add backup-specific assertions:
```bash
# Assert backup directory exists with metadata
assert_backup_exists() {
    local backup_path="$1"
    assert_dir_exists "$backup_path"
    assert_file_exists "$backup_path/metadata.json"
}

# Assert backup metadata has required fields
assert_backup_metadata_valid() {
    local backup_path="$1"
    local metadata="$backup_path/metadata.json"

    assert_file_exists "$metadata"
    assert_valid_json "$(cat "$metadata")"

    # Required fields
    jq -e '.backupType' "$metadata" > /dev/null
    jq -e '.timestamp' "$metadata" > /dev/null
    jq -e '.version' "$metadata" > /dev/null
    jq -e '.files' "$metadata" > /dev/null
}

# Assert backup count for specific type
assert_backup_count() {
    local backup_type="$1"
    local expected_count="$2"
    local backups_dir="${3:-$BACKUPS_ROOT}"

    local actual_count
    actual_count=$(find "$backups_dir/$backup_type" -maxdepth 1 -type d -name "${backup_type}_*" 2>/dev/null | wc -l)

    if [[ "$actual_count" -ne "$expected_count" ]]; then
        fail "Expected $expected_count $backup_type backups, got $actual_count"
    fi
}
```

### fixtures.bash

Add backup fixtures:
```bash
# Create backup with metadata
create_test_backup() {
    local backup_type="$1"
    local operation="${2:-test}"
    local base_dir="${3:-$BACKUPS_ROOT}"

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_id="${backup_type}_${timestamp}"
    local backup_path="$base_dir/$backup_type/$backup_id"

    mkdir -p "$backup_path"

    # Create sample metadata
    cat > "$backup_path/metadata.json" << EOF
{
  "backupType": "$backup_type",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "0.9.8",
  "trigger": "test",
  "operation": "$operation",
  "files": [],
  "totalSize": 0
}
EOF

    echo "$backup_path"
}

# Create multiple backups for rotation testing
create_multiple_backups() {
    local backup_type="$1"
    local count="$2"
    local base_dir="${3:-$BACKUPS_ROOT}"

    for i in $(seq 1 "$count"); do
        sleep 0.1  # Ensure unique timestamps
        create_test_backup "$backup_type" "test$i" "$base_dir"
    done
}
```

---

## Test Data Requirements

### Minimal test-config.json for Backup Tests
```json
{
  "version": "0.9.8",
  "backup": {
    "enabled": true,
    "directory": ".claude/backups",
    "maxSnapshots": 10,
    "maxSafetyBackups": 5,
    "maxIncremental": 10,
    "maxArchiveBackups": 3,
    "safetyRetentionDays": 7
  }
}
```

### Test Files for Backup
- `todo.json` with 3-5 tasks
- `todo-archive.json` with archived tasks
- `todo-config.json` with backup settings
- `todo-log.json` with log entries

---

## Coverage Goals

| Component | Target Coverage |
|-----------|----------------|
| lib/backup.sh functions | 90%+ |
| Script integration points | 100% |
| Edge cases | 80%+ |
| Error handling | 95%+ |
| Regression scenarios | 100% |

---

## Notes for Implementation

### Current State (Before Tests)
- `lib/backup.sh` exists but is NOT yet integrated into operational scripts
- `complete-task.sh` uses LEGACY backup pattern (`.claude/.backups/`)
- `archive.sh` uses atomic transaction but NO lib/backup.sh integration
- `init.sh` creates `.claude/.backups/` but NOT `.claude/backups/` taxonomy

### Expected Behavior After Integration (T162)
- `complete-task.sh` will call `create_safety_backup` BEFORE completion
- `archive.sh` will call `create_archive_backup` BEFORE archiving
- `migrate.sh` will call `create_migration_backup` BEFORE migration
- `init.sh` will create `.claude/backups/` taxonomy structure

### Testing Strategy
1. **Test lib/backup.sh in isolation first** (unit tests)
2. **Test script integration points** (integration tests)
3. **Verify legacy behavior preserved** (regression tests)
4. **Test edge cases and error handling** (edge case tests)

### Anti-Patterns to Avoid
- ❌ Don't test legacy backup paths in new backup.bats (test in regression.bats instead)
- ❌ Don't assume scripts are already integrated (verify current behavior first)
- ❌ Don't skip testing disabled backup behavior (BACKUP_ENABLED=false critical)
- ❌ Don't forget migration backups ignore BACKUP_ENABLED (test this explicitly)

---

## Success Criteria

### Definition of Done
- [ ] All critical (🔴) tests written and passing
- [ ] All important (🟡) tests written and passing
- [ ] Test coverage meets goals (90%+ for lib/backup.sh)
- [ ] CI/CD pipeline includes backup tests
- [ ] Test failures are clear and actionable
- [ ] Edge cases documented in fixtures/
- [ ] Regression scenarios verified

### Test Quality Checklist
- [ ] Tests are isolated (no dependencies between tests)
- [ ] Tests use fixtures and helpers (DRY principle)
- [ ] Tests have descriptive names explaining what is tested
- [ ] Error messages are clear and helpful
- [ ] Tests run in CI environment
- [ ] Tests are fast (<5s for unit tests, <30s for integration)

---

## Related Documentation
- `/mnt/projects/claude-todo/lib/backup.sh` - Backup library implementation
- `/mnt/projects/claude-todo/tests/README.md` - Test suite documentation
- `/mnt/projects/claude-todo/docs/architecture/ARCHITECTURE.md` - System architecture
- `/mnt/projects/claude-todo/docs/architecture/DATA-FLOWS.md` - Data flow diagrams
