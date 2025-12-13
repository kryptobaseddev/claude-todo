#!/usr/bin/env bats
# Tests for migrate-backups.sh
# Validates legacy backup migration to new taxonomy

setup() {
    load '../test_helper/common_setup'
    load '../test_helper/assertions'
    load '../test_helper/fixtures'
    common_setup

    # Set script path
    export MIGRATE_BACKUPS_SCRIPT="${SCRIPTS_DIR}/migrate-backups.sh"
}

teardown() {
    common_teardown
}

@test "migrate-backups: shows help" {
    run bash "$MIGRATE_BACKUPS_SCRIPT" --help
    assert_success
    assert_output --partial "Migrate legacy backups to new unified taxonomy"
    assert_output --partial "--detect"
    assert_output --partial "--dry-run"
    assert_output --partial "--run"
    assert_output --partial "--cleanup"
}

@test "migrate-backups: detects no backups in empty directory" {
    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "No legacy backups found"
}

@test "migrate-backups: classifies safety backup (YYYYMMDD_HHMMSS)" {
    mkdir -p .claude/.backups

    # Create safety backup
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000

    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "[safety backups]"
    assert_output --partial "todo.json.20241201_120000"
    assert_output --partial "2024-12-01T12:00:00Z"
}

@test "migrate-backups: classifies archive backup (.backup.TIMESTAMP)" {
    mkdir -p .claude/.backups

    # Create archive backup
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.backup.1234567890

    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "[archive backups]"
    assert_output --partial "todo.json.backup.1234567890"
}

@test "migrate-backups: classifies snapshot backup (backup_TIMESTAMP)" {
    mkdir -p .claude/.backups/backup_1234567890

    # Create snapshot backup directory
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/backup_1234567890/todo.json

    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "[snapshot backups]"
    assert_output --partial "backup_1234567890"
}

@test "migrate-backups: classifies migration backup (pre-migration-*)" {
    mkdir -p .claude/.backups/pre-migration-v0.8.0

    # Create migration backup directory
    echo '{"version":"0.8.0","tasks":[]}' > .claude/.backups/pre-migration-v0.8.0/todo.json

    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "[migration backups]"
    assert_output --partial "pre-migration-v0.8.0"
}

@test "migrate-backups: classifies numbered safety backups" {
    mkdir -p .claude/.backups

    # Create numbered backups (from file-ops.sh)
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.1
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.2

    run bash "$MIGRATE_BACKUPS_SCRIPT" --detect
    assert_success
    assert_output --partial "[safety backups]"
    assert_output --partial "todo.json.1"
    assert_output --partial "todo.json.2"
}

@test "migrate-backups: dry-run shows migration plan without changes" {
    mkdir -p .claude/.backups

    # Create test backup
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000

    run bash "$MIGRATE_BACKUPS_SCRIPT" --dry-run
    assert_success
    assert_output --partial "DRY RUN MODE"
    assert_output --partial "WOULD MIGRATE"
    assert_output --partial "todo.json.20241201_120000"

    # Verify no changes were made
    [ ! -d ".claude/backups/safety" ]
}

@test "migrate-backups: actual migration creates new backup structure" {
    mkdir -p .claude/.backups

    # Create test backup
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success
    assert_output --partial "MIGRATED:"
    assert_output --partial "Migrated: 1"

    # Verify new structure was created
    [ -d ".claude/backups/safety" ]

    # Verify metadata was created
    local backup_dir=$(find .claude/backups/safety -type d -name "safety_*" | head -1)
    [ -f "$backup_dir/metadata.json" ]

    # Verify metadata contains migration flag
    run jq -r '.migrated' "$backup_dir/metadata.json"
    assert_output "true"
}

@test "migrate-backups: preserves file integrity during migration" {
    mkdir -p .claude/.backups

    # Create test backup with known content
    local test_content='{"version":"0.9.0","tasks":[{"id":"T001","title":"Test"}]}'
    echo "$test_content" > .claude/.backups/todo.json.20241201_120000

    # Get original checksum
    local original_checksum=$(sha256sum .claude/.backups/todo.json.20241201_120000 | cut -d' ' -f1)

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success

    # Find migrated file
    local migrated_file=$(find .claude/backups/safety -name "todo.json" | head -1)

    # Verify checksum matches
    local migrated_checksum=$(sha256sum "$migrated_file" | cut -d' ' -f1)
    [ "$original_checksum" = "$migrated_checksum" ]
}

@test "migrate-backups: cleanup requires confirmation when backups remain" {
    mkdir -p .claude/.backups

    # Create test backup but don't migrate
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000

    # Cleanup should fail without migration first
    run bash -c "echo 'no' | bash $MIGRATE_BACKUPS_SCRIPT --cleanup"
    assert_failure
    assert_output --partial "Run migration first before cleanup"

    # Directory should still exist
    [ -d ".claude/.backups" ]
}

@test "migrate-backups: metadata includes original timestamp and path" {
    mkdir -p .claude/.backups

    # Create test backup
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success

    # Find metadata
    local backup_dir=$(find .claude/backups/safety -type d -name "safety_*" | head -1)
    local metadata_file="$backup_dir/metadata.json"

    # Verify metadata fields
    run jq -r '.originalTimestamp' "$metadata_file"
    assert_output "2024-12-01T12:00:00Z"

    run jq -r '.originalPath' "$metadata_file"
    assert_output --partial "todo.json.20241201_120000"

    run jq -r '.operation' "$metadata_file"
    assert_output "migrate_legacy"
}

@test "migrate-backups: migration backups get neverDelete flag" {
    mkdir -p .claude/.backups/pre-migration-v0.8.0

    # Create migration backup
    echo '{"version":"0.8.0","tasks":[]}' > .claude/.backups/pre-migration-v0.8.0/todo.json

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success

    # Find metadata
    local backup_dir=$(find .claude/backups/migration -type d -name "migration_*" | head -1)
    local metadata_file="$backup_dir/metadata.json"

    # Verify neverDelete flag
    run jq -r '.neverDelete' "$metadata_file"
    assert_output "true"
}

@test "migrate-backups: skips unknown backup types" {
    mkdir -p .claude/.backups

    # Create unrecognized backup
    echo "random content" > .claude/.backups/unknown_file.txt

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success
    assert_output --partial "Skipped (unknown): 1"
}

@test "migrate-backups: handles multiple backup types in single run" {
    mkdir -p .claude/.backups/backup_1234567890
    mkdir -p .claude/.backups/pre-migration-v0.8.0

    # Create different backup types
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/todo.json.20241201_120000  # safety
    echo '{"version":"0.9.0","tasks":[]}' > .claude/.backups/backup_1234567890/todo.json  # snapshot
    echo '{"version":"0.8.0","tasks":[]}' > .claude/.backups/pre-migration-v0.8.0/todo.json  # migration

    run bash "$MIGRATE_BACKUPS_SCRIPT" --run
    assert_success
    assert_output --partial "Migrated: 3"

    # Verify all types were created
    [ -d ".claude/backups/safety" ]
    [ -d ".claude/backups/snapshot" ]
    [ -d ".claude/backups/migration" ]
}
