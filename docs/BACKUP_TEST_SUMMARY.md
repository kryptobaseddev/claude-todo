# Backup Test Strategy - Quick Reference

Quick reference for backup system test implementation (T162/T163).

## Test Files Overview

```
tests/
├── unit/
│   ├── backup.bats              ← 🔴 CRITICAL - Core backup functions
│   └── backup-edge-cases.bats   ← 🟡 IMPORTANT - Edge cases & errors
│
└── integration/
    ├── backup-integration.bats  ← 🔴 CRITICAL - Script integration
    └── backup-regression.bats   ← 🟡 IMPORTANT - Legacy behavior preserved
```

---

## Priority Matrix

### Must Have Before Merge (🔴 Critical)

| Test File | Test Count | Focus |
|-----------|------------|-------|
| `unit/backup.bats` | ~50 tests | All backup functions, rotation, validation |
| `integration/backup-integration.bats` | ~10 tests | init.sh creates directories, legacy backups work |

**Estimated Total**: 60 critical tests

### Should Have for Quality (🟡 Important)

| Test File | Test Count | Focus |
|-----------|------------|-------|
| `unit/backup-edge-cases.bats` | ~20 tests | First backup, rotation limits, permissions, disk space |
| `integration/backup-regression.bats` | ~10 tests | Legacy paths accessible, atomic transactions preserved |

**Estimated Total**: 30 important tests

### Nice-to-Have (🟢 Recommended)

- Performance tests (backup speed, rotation performance)
- Stress tests (rapid creation, large directories)
- Recovery tests (corruption handling)

---

## Core Functions to Test

### lib/backup.sh Functions

| Function | Priority | Test Count |
|----------|----------|------------|
| `create_snapshot_backup` | 🔴 Critical | 8 tests |
| `create_safety_backup` | 🔴 Critical | 6 tests |
| `create_incremental_backup` | 🔴 Critical | 5 tests |
| `create_archive_backup` | 🔴 Critical | 5 tests |
| `create_migration_backup` | 🔴 Critical | 6 tests |
| `rotate_backups` | 🔴 Critical | 7 tests |
| `list_backups` | 🟡 Important | 4 tests |
| `restore_backup` | 🟡 Important | 6 tests |
| `get_backup_metadata` | 🟡 Important | 3 tests |
| `prune_backups` | 🟡 Important | 4 tests |

**Total Core Tests**: 54 tests

---

## Integration Points to Test

### Script Integration

| Script | Current Behavior | Expected After T162 | Test Priority |
|--------|-----------------|---------------------|---------------|
| `init.sh` | Creates `.claude/.backups/` | Creates `.claude/backups/` taxonomy | 🔴 Critical |
| `complete-task.sh` | Legacy backup in `.backups/` | Calls `create_safety_backup` | 🔴 Critical |
| `archive.sh` | Atomic transaction only | Calls `create_archive_backup` | 🟡 Important |
| `migrate.sh` | No backup integration | Calls `create_migration_backup` | 🟡 Important |

---

## Key Test Scenarios

### Backup Creation
```bash
# Snapshot backup with all files
create_snapshot_backup → creates metadata.json + all system files

# Safety backup before operation
create_safety_backup todo.json "complete" → single file backup

# Migration backup (always runs)
BACKUP_ENABLED=false && create_migration_backup → still creates backup
```

### Backup Rotation
```bash
# At limit: no deletion
maxSnapshots=10, count=10 → no backups deleted

# Over limit: delete oldest
maxSnapshots=10, count=15 → delete 5 oldest

# Migration: never delete
rotate_backups migration → returns 0, no deletion
```

### Restore
```bash
# From snapshot
restore_backup snapshot_20251213_120000 → restores all files

# From safety backup
restore_backup safety_20251213_120000_complete_todo.json → single file
```

---

## Edge Cases to Test

### High Priority Edge Cases
1. **First backup** (no existing backups)
2. **Rotation at exact limit** (maxSnapshots=10, have 10)
3. **BACKUP_ENABLED=false** (safety backups skip, migration backups run)
4. **Missing config file** (uses all defaults)
5. **Invalid JSON in backup** (validation catches, restore fails)

### Medium Priority Edge Cases
6. **Permission denied** (fails gracefully with clear error)
7. **Disk full** (atomic write prevents partial backups)
8. **Concurrent backups** (unique timestamps, no race conditions)
9. **Restore overwrites** (creates safety backup first)
10. **Empty backup directory** (list_backups returns empty)

---

## Test Helper Functions Needed

### Add to `test_helper/common_setup.bash`

```bash
_create_test_project() {
    # ... existing code ...

    # Add backup directory structure
    mkdir -p "${base_dir}/.claude/backups/snapshot"
    mkdir -p "${base_dir}/.claude/backups/safety"
    mkdir -p "${base_dir}/.claude/backups/incremental"
    mkdir -p "${base_dir}/.claude/backups/archive"
    mkdir -p "${base_dir}/.claude/backups/migration"

    export BACKUPS_ROOT="${base_dir}/.claude/backups"
}
```

### Add to `test_helper/assertions.bash`

```bash
assert_backup_exists() {
    local backup_path="$1"
    assert_dir_exists "$backup_path"
    assert_file_exists "$backup_path/metadata.json"
}

assert_backup_metadata_valid() {
    local backup_path="$1"
    # Validate metadata structure
}

assert_backup_count() {
    local backup_type="$1"
    local expected_count="$2"
    # Count backups of specific type
}
```

### Add to `test_helper/fixtures.bash`

```bash
create_test_backup() {
    local backup_type="$1"
    # Create minimal valid backup with metadata
}

create_multiple_backups() {
    local backup_type="$1"
    local count="$2"
    # Create N backups for rotation testing
}
```

---

## Test Commands Quick Reference

```bash
# Run all backup tests
bats tests/unit/backup*.bats tests/integration/backup*.bats

# Run critical tests only
bats tests/unit/backup.bats tests/integration/backup-integration.bats

# Run specific function tests
bats tests/unit/backup.bats --filter "rotate"
bats tests/unit/backup.bats --filter "snapshot"
bats tests/unit/backup.bats --filter "restore"

# Run with verbose output
bats tests/unit/backup.bats --trace

# Run in CI
./tests/run-all-tests.sh
```

---

## Implementation Checklist

### Phase 1: Critical Tests (Before Merge)
- [ ] Create `tests/unit/backup.bats`
  - [ ] Configuration loading tests (3 tests)
  - [ ] Metadata generation tests (4 tests)
  - [ ] Validation tests (4 tests)
  - [ ] Snapshot backup tests (8 tests)
  - [ ] Safety backup tests (6 tests)
  - [ ] Incremental backup tests (5 tests)
  - [ ] Archive backup tests (5 tests)
  - [ ] Migration backup tests (6 tests)
  - [ ] Rotation tests (7 tests)

- [ ] Create `tests/integration/backup-integration.bats`
  - [ ] init.sh creates backup directories (3 tests)
  - [ ] complete-task.sh legacy backups work (3 tests)
  - [ ] archive.sh atomic transaction preserved (2 tests)
  - [ ] migrate.sh integration (2 tests)

- [ ] Update test helpers
  - [ ] `common_setup.bash`: Add backup directory creation
  - [ ] `assertions.bash`: Add backup assertions
  - [ ] `fixtures.bash`: Add backup fixtures

### Phase 2: Important Tests (Quality Assurance)
- [ ] Create `tests/unit/backup-edge-cases.bats`
  - [ ] First backup scenarios (3 tests)
  - [ ] Rotation at limits (5 tests)
  - [ ] Restore from different types (4 tests)
  - [ ] Permission errors (3 tests)
  - [ ] Configuration edge cases (5 tests)

- [ ] Create `tests/integration/backup-regression.bats`
  - [ ] Legacy backup locations accessible (4 tests)
  - [ ] Atomic transaction patterns preserved (3 tests)
  - [ ] File locking still enforced (3 tests)

### Phase 3: Optional Tests (Future Improvements)
- [ ] Performance tests
- [ ] Stress tests
- [ ] Recovery tests

---

## Success Metrics

### Coverage Goals
- **lib/backup.sh**: 90%+ line coverage
- **Integration points**: 100% coverage
- **Edge cases**: 80%+ coverage
- **Error handling**: 95%+ coverage

### Test Quality Goals
- All tests isolated (no inter-test dependencies)
- All tests run in <5s (unit), <30s (integration)
- All test failures have clear, actionable messages
- All tests use fixtures and helpers (DRY)
- All tests pass in CI environment

### Documentation Goals
- All edge cases documented in test comments
- All regression scenarios explained
- All test helpers documented in README.md
- All fixtures have usage examples

---

## Notes

### Current State (Before T162)
- `lib/backup.sh` exists but **NOT integrated** into scripts
- `complete-task.sh` uses **legacy** `.claude/.backups/` pattern
- `archive.sh` uses atomic transaction but **NO backup lib**
- `init.sh` creates `.claude/.backups/` but **NOT** backup taxonomy

### After T162 Integration
- Scripts will call `lib/backup.sh` functions
- New backups use `.claude/backups/` taxonomy
- Legacy backups remain in `.claude/.backups/` (backward compat)
- Migration backups ALWAYS created (ignore BACKUP_ENABLED)

### Testing Philosophy
1. Test `lib/backup.sh` **in isolation first** (unit tests)
2. Test **script integration points** (integration tests)
3. Verify **legacy behavior preserved** (regression tests)
4. Test **edge cases and errors** (edge case tests)

---

## Quick Start

### For Test Authors

1. **Read full strategy**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_STRATEGY.md`
2. **Check existing patterns**: `/mnt/projects/claude-todo/tests/unit/complete-task.bats`
3. **Use test helpers**: `/mnt/projects/claude-todo/tests/test_helper/`
4. **Follow naming conventions**: Descriptive test names, section headers
5. **Run tests locally**: `bats tests/unit/backup.bats`
6. **Verify in CI**: `./tests/run-all-tests.sh`

### For Code Reviewers

1. **Check coverage**: All critical functions tested
2. **Verify edge cases**: Permission errors, disk full, concurrent ops
3. **Validate regression tests**: Legacy behavior preserved
4. **Review test quality**: Isolated, fast, clear error messages
5. **Ensure CI passing**: All tests green in pipeline

---

## Related Documentation

- **Full Test Strategy**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_STRATEGY.md`
- **Test Suite README**: `/mnt/projects/claude-todo/tests/README.md`
- **Backup Library**: `/mnt/projects/claude-todo/lib/backup.sh`
- **Architecture**: `/mnt/projects/claude-todo/docs/architecture/ARCHITECTURE.md`
