#!/usr/bin/env bash
# migrate.sh - Schema migration command for claude-todo
# Handles version upgrades for todo files

set -euo pipefail

# Determine the library directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source required libraries
# shellcheck source=lib/backup.sh
if [[ -f "$LIB_DIR/backup.sh" ]]; then
  source "$LIB_DIR/backup.sh"
fi

# shellcheck source=lib/migrate.sh
source "$LIB_DIR/migrate.sh"

# ============================================================================
# DEPENDENCY CHECK (T167)
# ============================================================================
# jq is required for all migration operations
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for migration operations but not found." >&2
    echo "" >&2
    echo "Install jq:" >&2
    case "$(uname -s)" in
        Linux*)  echo "  sudo apt install jq  (Debian/Ubuntu)" >&2
                 echo "  sudo yum install jq  (RHEL/CentOS)" >&2 ;;
        Darwin*) echo "  brew install jq" >&2 ;;
        *)       echo "  See: https://stedolan.github.io/jq/download/" >&2 ;;
    esac
    exit 1
fi

# ============================================================================
# USAGE
# ============================================================================

show_usage() {
    cat <<EOF
Usage: claude-todo migrate [COMMAND] [OPTIONS]

Schema version migration for claude-todo files.

Commands:
  status                 Show version status of all files
  check                  Check if migration is needed
  run                    Execute migration for all files
  file <path> <type>     Migrate specific file
  rollback               Rollback from most recent migration backup

Options:
  --dir <path>          Project directory (default: current directory)
  --auto                Auto-migrate without confirmation
  --backup              Create backup before migration (default)
  --no-backup           Skip backup creation
  --force               Force migration even if versions match
  -h, --help            Show this help message

Rollback Options:
  --backup-id <id>      Specific backup to restore from (optional)
  --force               Skip confirmation prompt

Examples:
  # Check migration status
  claude-todo migrate status

  # Migrate all files in current project
  claude-todo migrate run

  # Migrate specific file
  claude-todo migrate file .claude/todo.json todo

  # Auto-migrate without confirmation
  claude-todo migrate run --auto

  # Rollback from most recent migration backup
  claude-todo migrate rollback

  # Rollback from specific backup
  claude-todo migrate rollback --backup-id migration_v2.1.0_20251215_120000

Schema Versions:
  todo:    $SCHEMA_VERSION_TODO
  config:  $SCHEMA_VERSION_CONFIG
  archive: $SCHEMA_VERSION_ARCHIVE
  log:     $SCHEMA_VERSION_LOG
EOF
}

# ============================================================================
# COMMAND HANDLERS
# ============================================================================

# Show migration status for all files
cmd_status() {
    local project_dir="${1:-.}"
    local claude_dir="$project_dir/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        echo "ERROR: No .claude directory found in $project_dir" >&2
        echo "Run 'claude-todo init' to initialize the project" >&2
        exit 1
    fi

    show_migration_status "$claude_dir"
}

# Check if migration is needed
cmd_check() {
    local project_dir="${1:-.}"
    local claude_dir="$project_dir/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        echo "ERROR: No .claude directory found" >&2
        exit 1
    fi

    local needs_migration=false
    local files=(
        "$claude_dir/todo.json:todo"
        "$claude_dir/todo-config.json:config"
        "$claude_dir/todo-archive.json:archive"
        "$claude_dir/todo-log.json:log"
    )

    for file_spec in "${files[@]}"; do
        IFS=':' read -r file file_type <<< "$file_spec"

        if [[ ! -f "$file" ]]; then
            continue
        fi

        local status
        check_compatibility "$file" "$file_type" && status=$? || status=$?

        if [[ $status -eq 1 ]]; then
            needs_migration=true
            break
        elif [[ $status -eq 2 ]]; then
            echo "ERROR: Incompatible version found in $file" >&2
            exit 1
        fi
    done

    if [[ "$needs_migration" == "true" ]]; then
        echo "Migration needed"
        exit 1
    else
        echo "All files up to date"
        exit 0
    fi
}

# Run migration for all files
cmd_run() {
    local project_dir="${1:-.}"
    local auto_migrate="${2:-false}"
    local create_backup="${3:-true}"
    local force_migration="${4:-false}"

    local claude_dir="$project_dir/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        echo "ERROR: No .claude directory found" >&2
        exit 1
    fi

    echo "Schema Migration"
    echo "================"
    echo ""
    echo "Project: $project_dir"
    echo "Target versions:"
    echo "  todo:    $SCHEMA_VERSION_TODO"
    echo "  config:  $SCHEMA_VERSION_CONFIG"
    echo "  archive: $SCHEMA_VERSION_ARCHIVE"
    echo "  log:     $SCHEMA_VERSION_LOG"
    echo ""

    # Check status first
    local files=(
        "$claude_dir/todo.json:todo"
        "$claude_dir/todo-config.json:config"
        "$claude_dir/todo-archive.json:archive"
        "$claude_dir/todo-log.json:log"
    )

    local migration_needed=false
    local incompatible_found=false

    for file_spec in "${files[@]}"; do
        IFS=':' read -r file file_type <<< "$file_spec"

        if [[ ! -f "$file" ]]; then
            continue
        fi

        local status
        check_compatibility "$file" "$file_type" && status=$? || status=$?

        if [[ $status -eq 1 ]]; then
            migration_needed=true
        elif [[ $status -eq 2 ]]; then
            incompatible_found=true
        fi
    done

    if [[ "$incompatible_found" == "true" ]]; then
        echo "ERROR: Incompatible versions detected" >&2
        echo "Manual intervention required" >&2
        exit 1
    fi

    if [[ "$migration_needed" == "false" && "$force_migration" == "false" ]]; then
        echo "✓ All files already at current versions"
        exit 0
    fi

    if [[ "$force_migration" == "true" ]]; then
        echo "⚠ Force migration enabled - will re-migrate all files"
    fi

    # Confirm migration
    if [[ "$auto_migrate" != "true" ]]; then
        echo "This will migrate your todo files to the latest schema versions."
        echo ""
        read -p "Continue? (y/N) " -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Migration cancelled"
            exit 0
        fi
    fi

    # Create project backup if requested using unified backup library
    if [[ "$create_backup" == "true" ]]; then
        echo "Creating project backup..."

        # Try using unified backup library first
        if declare -f create_migration_backup >/dev/null 2>&1; then
            local target_version="$SCHEMA_VERSION_TODO"
            BACKUP_PATH=$(create_migration_backup "$target_version" 2>&1) || {
                echo "⚠ Backup library failed, using fallback backup method" >&2
                # Fallback to inline backup if library fails
                local backup_dir="${claude_dir}/backups/migration/pre-migration-$(date +%Y%m%d-%H%M%S)"
                mkdir -p "$backup_dir"

                for file_spec in "${files[@]}"; do
                    IFS=':' read -r file file_type <<< "$file_spec"
                    if [[ -f "$file" ]]; then
                        cp "$file" "$backup_dir/" || {
                            echo "ERROR: Failed to create backup" >&2
                            exit 1
                        }
                    fi
                done
                BACKUP_PATH="$backup_dir"
            }
            echo "✓ Backup created: $BACKUP_PATH"
        else
            # Fallback if backup library not available
            local backup_dir="${claude_dir}/backups/migration/pre-migration-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"

            for file_spec in "${files[@]}"; do
                IFS=':' read -r file file_type <<< "$file_spec"
                if [[ -f "$file" ]]; then
                    cp "$file" "$backup_dir/" || {
                        echo "ERROR: Failed to create backup" >&2
                        exit 1
                    }
                fi
            done
            echo "✓ Backup created: $backup_dir"
        fi
        echo ""
    fi

    # Perform migration
    local migration_failed=false

    for file_spec in "${files[@]}"; do
        IFS=':' read -r file file_type <<< "$file_spec"

        if [[ ! -f "$file" ]]; then
            continue
        fi

        local status
        check_compatibility "$file" "$file_type" && status=$? || status=$?

        # Force migration if flag is set, otherwise only migrate if needed
        if [[ $status -eq 1 || "$force_migration" == "true" ]]; then
            if [[ "$force_migration" == "true" && $status -eq 0 ]]; then
                echo "Migrating $file_type (forced)..."
            else
                echo "Migrating $file_type..."
            fi

            local current_version expected_version
            current_version=$(detect_file_version "$file")
            expected_version=$(get_expected_version "$file_type")

            if ! migrate_file "$file" "$file_type" "$current_version" "$expected_version"; then
                echo "✗ Migration failed for $file_type" >&2
                migration_failed=true
                break
            fi

            echo ""
        fi
    done

    if [[ "$migration_failed" == "true" ]]; then
        echo "ERROR: Migration failed" >&2
        echo "Backups available in: ${claude_dir}/backups/migration/" >&2
        exit 1
    fi

    echo "✓ Migration completed successfully"
}

# Migrate specific file
cmd_file() {
    local file="$1"
    local file_type="$2"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        exit 1
    fi

    local status
    check_compatibility "$file" "$file_type" && status=$? || status=$?

    case $status in
        0)
            echo "✓ File already at current version"
            exit 0
            ;;
        1)
            local current_version expected_version
            current_version=$(detect_file_version "$file")
            expected_version=$(get_expected_version "$file_type")

            echo "Migrating: $file"
            echo "  From: v$current_version"
            echo "  To:   v$expected_version"
            echo ""

            if migrate_file "$file" "$file_type" "$current_version" "$expected_version"; then
                echo "✓ Migration successful"
                exit 0
            else
                echo "✗ Migration failed" >&2
                exit 1
            fi
            ;;
        2)
            echo "ERROR: Incompatible version - manual intervention required" >&2
            exit 1
            ;;
    esac
}

# Rollback from migration backup
cmd_rollback() {
    local project_dir="${1:-.}"
    local backup_id="${2:-}"
    local force="${3:-false}"

    local claude_dir="$project_dir/.claude"
    local backups_dir="$claude_dir/backups/migration"

    if [[ ! -d "$claude_dir" ]]; then
        echo "ERROR: No .claude directory found in $project_dir" >&2
        echo "Run 'claude-todo init' to initialize the project" >&2
        exit 1
    fi

    if [[ ! -d "$backups_dir" ]]; then
        echo "ERROR: No migration backups found" >&2
        echo "Migration backups directory does not exist: $backups_dir" >&2
        exit 1
    fi

    # Find migration backup to use
    local backup_path=""

    if [[ -n "$backup_id" ]]; then
        # Use specific backup ID
        backup_path="$backups_dir/$backup_id"

        if [[ ! -d "$backup_path" ]]; then
            echo "ERROR: Backup not found: $backup_id" >&2
            echo "Available migration backups:" >&2
            find "$backups_dir" -maxdepth 1 -type d -name "migration_*" -exec basename {} \; 2>/dev/null | sort -r | head -5
            exit 1
        fi
    else
        # Find most recent migration backup
        backup_path=$(find "$backups_dir" -maxdepth 1 -type d -name "migration_*" -print0 2>/dev/null | \
            xargs -0 ls -dt 2>/dev/null | head -1)

        if [[ -z "$backup_path" ]]; then
            echo "ERROR: No migration backups found in $backups_dir" >&2
            exit 1
        fi
    fi

    local backup_name
    backup_name=$(basename "$backup_path")

    echo "Migration Rollback"
    echo "=================="
    echo ""
    echo "Backup: $backup_name"
    echo "Path:   $backup_path"
    echo ""

    # Verify backup integrity
    if [[ ! -f "$backup_path/metadata.json" ]]; then
        echo "ERROR: Backup metadata not found" >&2
        echo "Backup may be corrupted: $backup_path" >&2
        exit 1
    fi

    # Show backup metadata
    local timestamp
    timestamp=$(jq -r '.timestamp // "unknown"' "$backup_path/metadata.json" 2>/dev/null)
    local files
    files=$(jq -r '.files[].source' "$backup_path/metadata.json" 2>/dev/null)

    echo "Backup Information:"
    echo "  Created: $timestamp"
    echo "  Files:"
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        echo "    - $file"
    done <<< "$files"
    echo ""

    # Confirm rollback
    if [[ "$force" != "true" ]]; then
        echo "⚠ WARNING: This will restore all files from the backup."
        echo "  Current files will be backed up before restoration."
        echo ""
        read -p "Continue with rollback? (y/N) " -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Rollback cancelled"
            exit 0
        fi
    fi

    # Create pre-rollback safety backup
    echo "Creating safety backup before rollback..."
    local safety_backup="$claude_dir/backups/safety/safety_$(date +"%Y%m%d_%H%M%S")_pre_rollback"
    mkdir -p "$safety_backup"

    local files=(
        "$claude_dir/todo.json"
        "$claude_dir/todo-config.json"
        "$claude_dir/todo-archive.json"
        "$claude_dir/todo-log.json"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$safety_backup/" || {
                echo "ERROR: Failed to create safety backup" >&2
                exit 1
            }
        fi
    done
    echo "✓ Safety backup created: $safety_backup"
    echo ""

    # Restore files from migration backup
    echo "Restoring files from backup..."
    local restore_errors=0
    local restored_files=()

    for file_spec in "${files[@]}"; do
        local filename
        filename=$(basename "$file_spec")
        local source_file="$backup_path/$filename"
        local target_file="$file_spec"

        if [[ ! -f "$source_file" ]]; then
            echo "⚠ Skipping $filename (not in backup)"
            continue
        fi

        # Validate JSON in backup
        if ! jq empty "$source_file" 2>/dev/null; then
            echo "ERROR: Invalid JSON in backup: $filename" >&2
            ((restore_errors++))
            continue
        fi

        # Restore file
        if cp "$source_file" "$target_file"; then
            echo "✓ Restored $filename"
            restored_files+=("$filename")
        else
            echo "✗ Failed to restore $filename" >&2
            ((restore_errors++))
        fi
    done

    echo ""

    # Check for errors
    if [[ $restore_errors -gt 0 ]]; then
        echo "ERROR: Rollback completed with $restore_errors errors" >&2
        echo "Safety backup available at: $safety_backup" >&2
        exit 1
    fi

    # Validate all restored files
    echo "Validating restored files..."
    local validation_errors=0

    for filename in "${restored_files[@]}"; do
        local target_file="$claude_dir/$filename"

        if [[ -f "$target_file" ]]; then
            if ! jq empty "$target_file" 2>/dev/null; then
                echo "✗ Validation failed: $filename" >&2
                ((validation_errors++))
            fi
        fi
    done

    if [[ $validation_errors -gt 0 ]]; then
        echo ""
        echo "ERROR: Validation failed after rollback" >&2
        echo "Safety backup available at: $safety_backup" >&2
        exit 1
    fi

    echo "✓ All files validated successfully"
    echo ""

    # Show current versions after rollback
    echo "Current Schema Versions:"
    for file_spec in "${files[@]}"; do
        local filename
        filename=$(basename "$file_spec")
        local file_type

        case "$filename" in
            todo.json)
                file_type="todo"
                ;;
            todo-config.json)
                file_type="config"
                ;;
            todo-archive.json)
                file_type="archive"
                ;;
            todo-log.json)
                file_type="log"
                ;;
            *)
                continue
                ;;
        esac

        if [[ -f "$file_spec" ]]; then
            local version
            version=$(detect_file_version "$file_spec")
            echo "  $file_type: v$version"
        fi
    done

    echo ""
    echo "✓ Rollback completed successfully"
    echo ""
    echo "Note: Safety backup of pre-rollback state available at:"
    echo "  $safety_backup"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Handle global help flag first
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi

    local command="${1:-}"
    shift || true

    # Parse options based on command
    local project_dir="."
    local auto_migrate=false
    local create_backup=true
    local force_migration=false
    local backup_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)
                project_dir="$2"
                shift 2
                ;;
            --auto)
                auto_migrate=true
                shift
                ;;
            --backup)
                create_backup=true
                shift
                ;;
            --no-backup)
                create_backup=false
                shift
                ;;
            --force)
                force_migration=true
                shift
                ;;
            --backup-id)
                backup_id="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        "status")
            cmd_status "$project_dir"
            ;;
        "check")
            cmd_check "$project_dir"
            ;;
        "run")
            cmd_run "$project_dir" "$auto_migrate" "$create_backup" "$force_migration"
            ;;
        "file")
            if [[ $# -lt 2 ]]; then
                echo "ERROR: Missing arguments for 'file' command" >&2
                echo "Usage: claude-todo migrate file <path> <type>" >&2
                exit 1
            fi
            cmd_file "$1" "$2"
            ;;
        "rollback")
            cmd_rollback "$project_dir" "$backup_id" "$force_migration"
            ;;
        "")
            show_usage
            exit 1
            ;;
        *)
            echo "ERROR: Unknown command: $command" >&2
            echo "" >&2
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
