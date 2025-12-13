# Backup Test Implementation Roadmap

Visual roadmap for implementing backup system tests in priority order.

## Test Implementation Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PHASE 1: CRITICAL                           │
│                    (Must Have Before Merge)                         │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐
│ 1. Test Helpers      │ ← Start Here
│ - common_setup.bash  │
│ - assertions.bash    │
│ - fixtures.bash      │
└──────────────────────┘
         │
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. Unit Tests: lib/backup.sh Core Functions                     │
│ File: tests/unit/backup.bats                                     │
│                                                                  │
│ Section A: Configuration & Metadata (7 tests, ~30 min)          │
│   ✓ _load_backup_config (3 tests)                              │
│   ✓ _create_backup_metadata (4 tests)                          │
│                                                                  │
│ Section B: Validation (4 tests, ~20 min)                        │
│   ✓ _validate_backup (4 tests)                                 │
│                                                                  │
│ Section C: Backup Creation Functions (30 tests, ~2 hours)       │
│   ✓ create_snapshot_backup (8 tests)                           │
│   ✓ create_safety_backup (6 tests)                             │
│   ✓ create_incremental_backup (5 tests)                        │
│   ✓ create_archive_backup (5 tests)                            │
│   ✓ create_migration_backup (6 tests)                          │
│                                                                  │
│ Section D: Backup Management (7 tests, ~1 hour)                 │
│   ✓ rotate_backups (7 tests)                                   │
└──────────────────────────────────────────────────────────────────┘
         │
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ 3. Integration Tests: Script Integration                        │
│ File: tests/integration/backup-integration.bats                  │
│                                                                  │
│ Section A: init.sh Integration (3 tests, ~30 min)               │
│   ✓ Creates backup directory taxonomy                          │
│   ✓ Handles existing directories                               │
│   ✓ Validates directory structure                              │
│                                                                  │
│ Section B: complete-task.sh Integration (3 tests, ~30 min)      │
│   ✓ Legacy backups still created                               │
│   ✓ Backup rotation works                                      │
│   ✓ Atomic write pattern preserved                             │
│                                                                  │
│ Section C: archive.sh Integration (2 tests, ~20 min)            │
│   ✓ Atomic transaction still works                             │
│   ✓ Backup files included                                      │
│                                                                  │
│ Section D: migrate.sh Integration (2 tests, ~20 min)            │
│   ✓ Migration backup would be created (future)                 │
│   ✓ Backup includes all system files                           │
└──────────────────────────────────────────────────────────────────┘

Total Phase 1: 58 tests, ~6 hours

┌─────────────────────────────────────────────────────────────────────┐
│                        PHASE 2: IMPORTANT                           │
│                     (Should Have for Quality)                       │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ 4. Edge Cases & Error Handling                                  │
│ File: tests/unit/backup-edge-cases.bats                         │
│                                                                  │
│ Section A: First Backup Scenarios (3 tests, ~30 min)            │
│   ✓ No existing backups                                        │
│   ✓ Rotation with single backup                                │
│   ✓ List returns single entry                                  │
│                                                                  │
│ Section B: Rotation at Limits (5 tests, ~45 min)                │
│   ✓ Exactly at limit (no deletion)                             │
│   ✓ One over limit (delete 1)                                  │
│   ✓ Multiple over limit (delete N)                             │
│   ✓ Unlimited (max=0, no deletion)                             │
│   ✓ mtime-based sorting (oldest first)                         │
│                                                                  │
│ Section C: Restore Operations (4 tests, ~45 min)                │
│   ✓ Restore from snapshot                                      │
│   ✓ Restore from safety                                        │
│   ✓ Restore from archive                                       │
│   ✓ Restore from migration                                     │
│                                                                  │
│ Section D: Error Handling (8 tests, ~1 hour)                    │
│   ✓ Permission denied (backup creation)                        │
│   ✓ Disk full (atomic write prevents corruption)               │
│   ✓ Invalid JSON in backup                                     │
│   ✓ Missing config file (uses defaults)                        │
│   ✓ BACKUP_ENABLED=false (safety backups skip)                │
│   ✓ BACKUP_ENABLED=false (migration backups run)              │
│   ✓ Concurrent operations (no race conditions)                 │
│   ✓ Missing optional files (graceful handling)                 │
└──────────────────────────────────────────────────────────────────┘
         │
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ 5. Regression Tests                                             │
│ File: tests/integration/backup-regression.bats                   │
│                                                                  │
│ Section A: Legacy Compatibility (4 tests, ~45 min)              │
│   ✓ Legacy .claude/.backups/ still created                     │
│   ✓ Legacy backup rotation still works                         │
│   ✓ Old backups remain accessible                              │
│   ✓ New/old locations coexist                                  │
│                                                                  │
│ Section B: Atomic Transactions (3 tests, ~30 min)               │
│   ✓ Temp → validate → backup → rename pattern                  │
│   ✓ File locking still enforced                                │
│   ✓ No partial writes on error                                 │
│                                                                  │
│ Section C: Validation & Checksums (3 tests, ~30 min)            │
│   ✓ JSON validation before backup                              │
│   ✓ Checksum recalculation after ops                           │
│   ✓ Schema validation for generated files                      │
└──────────────────────────────────────────────────────────────────┘

Total Phase 2: 30 tests, ~5.5 hours

┌─────────────────────────────────────────────────────────────────────┐
│                    PHASE 3: NICE-TO-HAVE                            │
│                    (Future Improvements)                            │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ 6. Advanced Tests (Future)                                       │
│                                                                  │
│ - Restore Functionality (6 tests)                               │
│   • Restore validation                                          │
│   • Safety backup before restore                               │
│   • Partial restore handling                                    │
│                                                                  │
│ - Backup Management (7 tests)                                   │
│   • list_backups filtering                                      │
│   • get_backup_metadata                                         │
│   • prune_backups by retention                                  │
│                                                                  │
│ - Performance Tests                                             │
│   • Large todo.json backup speed                                │
│   • Rotation with 100+ backups                                  │
│   • Restore performance                                         │
│                                                                  │
│ - Stress Tests                                                  │
│   • Rapid backup creation                                       │
│   • Very large backup directories                               │
│   • Corruption recovery                                         │
└──────────────────────────────────────────────────────────────────┘

Total Phase 3: ~20 tests, ~4 hours

═══════════════════════════════════════════════════════════════════════
TOTAL ESTIMATED: 108 tests, ~15.5 hours implementation
═══════════════════════════════════════════════════════════════════════
```

---

## Test Execution Order (Recommended)

### Day 1: Foundation & Core Functions (4-5 hours)

```
09:00 - 09:30 │ Setup test helpers (common_setup, assertions, fixtures)
              │
09:30 - 10:00 │ Configuration & Metadata tests (Section A)
              │ - _load_backup_config
              │ - _create_backup_metadata
              │
10:00 - 10:20 │ Validation tests (Section B)
              │ - _validate_backup
              │
10:20 - 10:30 │ ☕ Break
              │
10:30 - 12:30 │ Backup Creation Functions (Section C)
              │ - create_snapshot_backup (8 tests)
              │ - create_safety_backup (6 tests)
              │ - create_incremental_backup (5 tests)
              │
12:30 - 13:30 │ 🍱 Lunch
              │
13:30 - 14:30 │ More Backup Functions (Section C continued)
              │ - create_archive_backup (5 tests)
              │ - create_migration_backup (6 tests)
              │
14:30 - 15:30 │ Rotation tests (Section D)
              │ - rotate_backups (7 tests)
              │
15:30 - 16:00 │ Run all unit tests, fix failures
```

**Deliverable**: `tests/unit/backup.bats` complete (48 tests)

---

### Day 2: Integration & Edge Cases (4-5 hours)

```
09:00 - 09:30 │ init.sh integration tests
              │ - Directory creation
              │ - Structure validation
              │
09:30 - 10:00 │ complete-task.sh integration tests
              │ - Legacy backups
              │ - Rotation
              │
10:00 - 10:20 │ archive.sh & migrate.sh integration tests
              │
10:20 - 10:30 │ ☕ Break
              │
10:30 - 11:00 │ First backup scenarios (Section A)
              │
11:00 - 11:45 │ Rotation at limits (Section B)
              │
11:45 - 12:30 │ Restore operations (Section C)
              │
12:30 - 13:30 │ 🍱 Lunch
              │
13:30 - 14:30 │ Error handling tests (Section D)
              │ - Permission errors
              │ - Disk space
              │ - Invalid JSON
              │
14:30 - 15:00 │ Configuration edge cases
              │
15:00 - 16:00 │ Run all tests, fix failures, verify coverage
```

**Deliverable**:
- `tests/integration/backup-integration.bats` complete (10 tests)
- `tests/unit/backup-edge-cases.bats` complete (20 tests)

---

### Day 3: Regression & Quality (3-4 hours)

```
09:00 - 09:45 │ Legacy compatibility tests
              │ - Old backup paths
              │ - Rotation still works
              │
09:45 - 10:15 │ Atomic transaction tests
              │ - File locking
              │ - No partial writes
              │
10:15 - 10:30 │ ☕ Break
              │
10:30 - 11:00 │ Validation & checksum tests
              │
11:00 - 12:00 │ Run full test suite
              │ - Fix any failures
              │ - Verify coverage metrics
              │ - Check CI pipeline
              │
12:00 - 13:00 │ Documentation & cleanup
              │ - Update test README
              │ - Add missing test comments
              │ - Document edge cases
```

**Deliverable**: `tests/integration/backup-regression.bats` complete (10 tests)

---

## Parallel Work Opportunities

### Can Run in Parallel

```
┌─────────────────────┐    ┌─────────────────────┐
│  Developer A        │    │  Developer B        │
│                     │    │                     │
│  Unit Tests         │    │  Integration Tests  │
│  backup.bats        │    │  backup-integration │
│  (Sections A-D)     │    │  .bats              │
└─────────────────────┘    └─────────────────────┘
         │                          │
         │                          │
         └──────────┬───────────────┘
                    ↓
           ┌─────────────────┐
           │  Merge & Run    │
           │  All Tests      │
           └─────────────────┘
```

### Sequential Dependencies

```
Test Helpers (fixtures, assertions)
         │
         ↓
    Unit Tests
         │
         ↓
  Integration Tests
         │
         ↓
    Edge Cases
         │
         ↓
  Regression Tests
```

---

## Coverage Tracking

### Phase 1 Coverage Goals

| Component | Target | Actual | Status |
|-----------|--------|--------|--------|
| `create_snapshot_backup` | 100% | TBD | ⏳ |
| `create_safety_backup` | 100% | TBD | ⏳ |
| `create_incremental_backup` | 100% | TBD | ⏳ |
| `create_archive_backup` | 100% | TBD | ⏳ |
| `create_migration_backup` | 100% | TBD | ⏳ |
| `rotate_backups` | 100% | TBD | ⏳ |
| `_validate_backup` | 100% | TBD | ⏳ |
| `_load_backup_config` | 100% | TBD | ⏳ |
| **Overall lib/backup.sh** | **90%+** | **TBD** | ⏳ |

### Phase 2 Coverage Goals

| Component | Target | Actual | Status |
|-----------|--------|--------|--------|
| Edge cases | 80%+ | TBD | ⏳ |
| Error handling | 95%+ | TBD | ⏳ |
| Integration points | 100% | TBD | ⏳ |
| Regression scenarios | 100% | TBD | ⏳ |

---

## Test Execution Checklist

### Before Starting
- [ ] Read full test strategy document
- [ ] Set up test environment (`git submodule update --init`)
- [ ] Install dependencies (`bats`, `jq`)
- [ ] Review existing test patterns (`tests/unit/complete-task.bats`)

### During Implementation
- [ ] Use test helpers (common_setup, assertions, fixtures)
- [ ] Follow naming conventions (descriptive test names)
- [ ] Add section headers for test organization
- [ ] Write tests before looking at implementation (TDD approach)
- [ ] Run tests frequently (`bats tests/unit/backup.bats`)

### After Implementation
- [ ] Run full test suite (`./tests/run-all-tests.sh`)
- [ ] Check coverage metrics (aim for 90%+ on lib/backup.sh)
- [ ] Verify CI pipeline passes
- [ ] Update test documentation (README.md)
- [ ] Add missing test comments and edge case docs

---

## Test File Templates

### Unit Test Template (`backup.bats`)

```bash
#!/usr/bin/env bats
# =============================================================================
# backup.bats - Unit tests for lib/backup.sh
# =============================================================================

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    load '../test_helper/fixtures'
    common_setup

    # Source backup library
    source "$LIB_DIR/backup.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# Configuration Loading Tests
# =============================================================================

@test "_load_backup_config uses defaults when config missing" {
    rm -f "$CONFIG_FILE"
    _load_backup_config

    [ "$BACKUP_ENABLED" = "true" ]
    [ "$MAX_SNAPSHOTS" = "10" ]
}

# More tests...
```

### Integration Test Template (`backup-integration.bats`)

```bash
#!/usr/bin/env bats
# =============================================================================
# backup-integration.bats - Integration tests for backup system
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
# init.sh Integration Tests
# =============================================================================

@test "init.sh creates backup directory taxonomy" {
    run bash "$INIT_SCRIPT" --force
    assert_success

    assert_dir_exists ".claude/backups/snapshot"
    assert_dir_exists ".claude/backups/safety"
    assert_dir_exists ".claude/backups/incremental"
    assert_dir_exists ".claude/backups/archive"
    assert_dir_exists ".claude/backups/migration"
}

# More tests...
```

---

## Success Metrics

### Phase 1 Success Criteria
✅ All 58 critical tests pass
✅ Unit test coverage ≥90% for lib/backup.sh
✅ Integration tests verify directory creation
✅ CI pipeline includes backup tests
✅ No test failures in local or CI environment

### Phase 2 Success Criteria
✅ All 30 important tests pass
✅ Edge cases documented and tested
✅ Regression tests verify backward compatibility
✅ Error handling coverage ≥95%
✅ Test execution time <5s (unit), <30s (integration)

### Phase 3 Success Criteria
✅ Restore functionality fully tested
✅ Performance benchmarks established
✅ Stress tests identify limits
✅ All test documentation complete

---

## Risk Mitigation

### High Risk Areas

| Risk | Mitigation | Tests |
|------|------------|-------|
| Race conditions in concurrent backups | Test rapid backup creation with unique timestamps | backup-edge-cases.bats |
| Disk full during backup | Test atomic write pattern, no partial backups | backup-edge-cases.bats |
| Permission errors | Test graceful failure with clear error messages | backup-edge-cases.bats |
| Invalid JSON in backups | Test validation before creation and restore | backup.bats |
| Legacy backup compatibility | Test old .backups/ path still works | backup-regression.bats |

### Medium Risk Areas

| Risk | Mitigation | Tests |
|------|------------|-------|
| Migration backup always runs | Test BACKUP_ENABLED=false doesn't skip | backup.bats |
| Rotation deletes wrong backups | Test mtime-based sorting (oldest first) | backup.bats |
| Restore overwrites without backup | Test safety backup created first | backup-edge-cases.bats |

---

## Quick Commands Reference

```bash
# Run specific test file
bats tests/unit/backup.bats

# Run specific test
bats tests/unit/backup.bats --filter "snapshot"

# Run with verbose output
bats tests/unit/backup.bats --trace

# Run all backup tests
bats tests/unit/backup*.bats tests/integration/backup*.bats

# Run all tests
./tests/run-all-tests.sh

# Check test coverage (manual - count tested functions)
grep -c "^@test" tests/unit/backup.bats
```

---

## Next Steps

1. **Review this roadmap** with team
2. **Assign ownership** (Developer A = unit tests, Developer B = integration tests)
3. **Set up test environment** (install dependencies, submodules)
4. **Implement Phase 1** (critical tests, 58 tests, ~6 hours)
5. **Review and iterate** (fix failures, verify coverage)
6. **Implement Phase 2** (important tests, 30 tests, ~5.5 hours)
7. **Implement Phase 3** (optional tests, future improvements)

---

## Related Documentation

- **Full Test Strategy**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_STRATEGY.md`
- **Quick Reference**: `/mnt/projects/claude-todo/docs/BACKUP_TEST_SUMMARY.md`
- **Test Suite README**: `/mnt/projects/claude-todo/tests/README.md`
- **Backup Library**: `/mnt/projects/claude-todo/lib/backup.sh`
