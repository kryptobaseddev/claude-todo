#!/usr/bin/env bash
# migrate-backups.sh - Migrate legacy backups to new taxonomy
# Part of claude-todo system
#
# Migrates backups from old locations to new unified taxonomy:
#   Old: .claude/.backups/ (various naming patterns)
#   New: .claude/backups/{snapshot,safety,incremental,archive,migration}/
#
# Usage:
#   migrate-backups.sh --detect        # List detected legacy backups
#   migrate-backups.sh --dry-run       # Preview migration without changes
#   migrate-backups.sh --run           # Perform actual migration
#   migrate-backups.sh --cleanup       # Remove old .backups directory after migration

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# SETUP AND DEPENDENCIES
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
# shellcheck source=lib/logging.sh
source "$LIB_DIR/logging.sh"
# shellcheck source=lib/backup.sh
source "$LIB_DIR/backup.sh"
# shellcheck source=lib/file-ops.sh
source "$LIB_DIR/file-ops.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly LEGACY_BACKUP_DIR=".claude/.backups"
readonly NEW_BACKUP_DIR=".claude/backups"
readonly MIGRATION_LOG=".claude/backup-migration.log"

# ============================================================================
# LEGACY BACKUP CLASSIFICATION
# ============================================================================

# Classify legacy backup by naming pattern
# Args: $1 = backup path (file or directory)
# Output: backup type (snapshot|safety|archive|migration|unknown)
classify_legacy_backup() {
    local backup_path="$1"
    local basename
    basename=$(basename "$backup_path")

    # Migration backups: pre-migration-* directories
    if [[ "$basename" =~ ^pre-migration- ]]; then
        echo "migration"
        return 0
    fi

    # Snapshot backups: backup_TIMESTAMP/ directories
    if [[ -d "$backup_path" && "$basename" =~ ^backup_[0-9]+ ]]; then
        echo "snapshot"
        return 0
    fi

    # Archive backups: *.backup.TIMESTAMP or archive-related patterns
    if [[ "$basename" =~ \.backup\. ]] || [[ "$basename" =~ ^archive ]]; then
        echo "archive"
        return 0
    fi

    # Safety backups: todo.json.YYYYMMDD_HHMMSS or *.YYYYMMDD_HHMMSS
    if [[ "$basename" =~ \.[0-9]{8}_[0-9]{6}$ ]]; then
        echo "safety"
        return 0
    fi

    # Numbered backups from file-ops.sh: filename.1, filename.2, etc
    if [[ "$basename" =~ \.[0-9]+$ ]]; then
        echo "safety"
        return 0
    fi

    echo "unknown"
}

# Extract timestamp from legacy backup name
# Args: $1 = backup path
# Output: ISO timestamp or "unknown"
extract_legacy_timestamp() {
    local backup_path="$1"
    local basename
    basename=$(basename "$backup_path")

    # Try YYYYMMDD_HHMMSS pattern
    if [[ "$basename" =~ ([0-9]{8}_[0-9]{6}) ]]; then
        local date_str="${BASH_REMATCH[1]}"
        # Convert to ISO format: YYYYMMDD_HHMMSS -> YYYY-MM-DDTHH:MM:SS
        local year="${date_str:0:4}"
        local month="${date_str:4:2}"
        local day="${date_str:6:2}"
        local hour="${date_str:9:2}"
        local minute="${date_str:11:2}"
        local second="${date_str:13:2}"
        echo "${year}-${month}-${day}T${hour}:${minute}:${second}Z"
        return 0
    fi

    # Try backup_TIMESTAMP pattern (epoch time)
    if [[ "$basename" =~ backup_([0-9]+) ]]; then
        local epoch="${BASH_REMATCH[1]}"
        date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        echo "unknown"
        return 0
    fi

    # Fall back to file modification time
    if [[ -e "$backup_path" ]]; then
        local mtime
        mtime=$(get_file_mtime "$backup_path")
        date -u -d "@$mtime" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -r "$mtime" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        echo "unknown"
        return 0
    fi

    echo "unknown"
}

# ============================================================================
# DETECTION
# ============================================================================

# Detect all legacy backups
# Output: JSON array of detected backups
detect_legacy_backups() {
    local legacy_dir="$LEGACY_BACKUP_DIR"

    if [[ ! -d "$legacy_dir" ]]; then
        echo "[]"
        return 0
    fi

    local backups=()

    # Find all files and directories in legacy backup location (maxdepth 1 for top-level only)
    while IFS= read -r backup_path; do
        [[ ! -e "$backup_path" ]] && continue
        [[ "$backup_path" == "$legacy_dir" ]] && continue

        local type
        type=$(classify_legacy_backup "$backup_path")

        local timestamp
        timestamp=$(extract_legacy_timestamp "$backup_path")

        local size=0
        if [[ -f "$backup_path" ]]; then
            size=$(get_file_size "$backup_path")
        elif [[ -d "$backup_path" ]]; then
            size=$(du -sb "$backup_path" 2>/dev/null | cut -f1 || echo "0")
        fi

        local is_dir="false"
        [[ -d "$backup_path" ]] && is_dir="true"

        local backup_json
        backup_json=$(jq -n \
            --arg path "$backup_path" \
            --arg type "$type" \
            --arg ts "$timestamp" \
            --argjson size "$size" \
            --argjson is_dir "$is_dir" \
            '{
                path: $path,
                type: $type,
                timestamp: $ts,
                size: $size,
                isDirectory: $is_dir
            }')

        backups+=("$backup_json")
    done < <(find "$legacy_dir" -mindepth 1 -maxdepth 1 2>/dev/null || true)

    # Output JSON array
    printf '%s\n' "${backups[@]}" | jq -s '.'
}

# ============================================================================
# MIGRATION
# ============================================================================

# Migrate single legacy backup
# Args: $1 = backup JSON object, $2 = dry_run (true|false)
# Returns: 0 on success, 1 on error
migrate_single_backup() {
    local backup_json="$1"
    local dry_run="${2:-false}"

    local source_path
    source_path=$(echo "$backup_json" | jq -r '.path')

    local backup_type
    backup_type=$(echo "$backup_json" | jq -r '.type')

    local original_timestamp
    original_timestamp=$(echo "$backup_json" | jq -r '.timestamp')

    local is_dir
    is_dir=$(echo "$backup_json" | jq -r '.isDirectory')

    # Skip unknown types
    if [[ "$backup_type" == "unknown" ]]; then
        echo "WARNING: Skipping unknown backup type: $source_path" >&2
        return 2  # Special return code for "skipped"
    fi

    # Generate new backup ID based on type
    local backup_id
    local timestamp_suffix
    timestamp_suffix=$(date +"%Y%m%d_%H%M%S")

    case "$backup_type" in
        snapshot)
            backup_id="snapshot_${timestamp_suffix}_migrated"
            ;;
        safety)
            local filename
            filename=$(basename "$source_path" | sed 's/\.[0-9]\{8\}_[0-9]\{6\}$//' | sed 's/\.[0-9]\+$//')
            backup_id="safety_${timestamp_suffix}_migration_${filename}"
            ;;
        archive)
            backup_id="archive_${timestamp_suffix}_migrated"
            ;;
        migration)
            backup_id="migration_legacy_${timestamp_suffix}"
            ;;
        *)
            echo "ERROR: Invalid backup type: $backup_type" >&2
            return 1
            ;;
    esac

    # Create target directory
    local target_dir="$NEW_BACKUP_DIR/$backup_type/$backup_id"

    if [[ "$dry_run" == "true" ]]; then
        echo "WOULD MIGRATE: $source_path -> $target_dir"
        return 0
    fi

    # Ensure target directory exists
    ensure_directory "$target_dir" || {
        echo "ERROR: Failed to create target directory: $target_dir" >&2
        return 1
    }

    # Copy files to target
    if [[ "$is_dir" == "true" ]]; then
        # Directory backup: copy contents
        cp -r "$source_path"/* "$target_dir/" 2>/dev/null || {
            echo "ERROR: Failed to copy directory contents: $source_path" >&2
            return 1
        }
    else
        # File backup: copy to target with original name
        local filename
        filename=$(basename "$source_path")
        # Strip backup suffixes to get original filename
        filename=$(echo "$filename" | sed 's/\.[0-9]\{8\}_[0-9]\{6\}$//' | sed 's/\.[0-9]\+$//' | sed 's/\.backup\.[0-9]\+$//')

        cp "$source_path" "$target_dir/$filename" 2>/dev/null || {
            echo "ERROR: Failed to copy file: $source_path" >&2
            return 1
        }
    fi

    # Generate metadata
    local files_json="[]"
    local total_size=0

    # Collect file information
    local file_info=()
    while IFS= read -r file; do
        [[ ! -f "$file" ]] && continue

        local filename
        filename=$(basename "$file")

        local file_size
        file_size=$(get_file_size "$file")

        local checksum
        checksum=$(safe_checksum "$file")

        file_info+=("$(jq -n \
            --arg src "$filename" \
            --arg backup "$filename" \
            --argjson size "$file_size" \
            --arg checksum "$checksum" \
            '{source: $src, backup: $backup, size: $size, checksum: $checksum}')")

        total_size=$((total_size + file_size))
    done < <(find "$target_dir" -type f -name "*.json" 2>/dev/null || true)

    if [[ ${#file_info[@]} -gt 0 ]]; then
        files_json=$(printf '%s\n' "${file_info[@]}" | jq -s '.')
    fi

    # Create metadata with migration flags
    local metadata
    metadata=$(jq -n \
        --arg type "$backup_type" \
        --arg ts "$(get_iso_timestamp)" \
        --arg ver "${CLAUDE_TODO_VERSION:-0.9.8}" \
        --arg trigger "migration" \
        --arg op "migrate_legacy" \
        --argjson files "$files_json" \
        --argjson size "$total_size" \
        --arg orig_ts "$original_timestamp" \
        --arg orig_path "$source_path" \
        '{
            backupType: $type,
            timestamp: $ts,
            version: $ver,
            trigger: $trigger,
            operation: $op,
            files: $files,
            totalSize: $size,
            migrated: true,
            originalTimestamp: $orig_ts,
            originalPath: $orig_path
        }')

    # Add neverDelete flag for migration backups
    if [[ "$backup_type" == "migration" ]]; then
        metadata=$(echo "$metadata" | jq '. + {neverDelete: true}')
    fi

    echo "$metadata" > "$target_dir/metadata.json"

    # Verify integrity
    local errors=0

    # Check metadata exists
    if [[ ! -f "$target_dir/metadata.json" ]]; then
        echo "ERROR: Migration failed - metadata not created" >&2
        ((errors++))
    fi

    # Verify file sizes match (for file backups)
    if [[ "$is_dir" == "false" ]]; then
        local source_size
        source_size=$(get_file_size "$source_path")

        local target_file
        target_file=$(find "$target_dir" -type f -name "*.json" ! -name "metadata.json" | head -1)

        if [[ -n "$target_file" ]]; then
            local target_size
            target_size=$(get_file_size "$target_file")

            if [[ "$source_size" -ne "$target_size" ]]; then
                echo "ERROR: Size mismatch after migration: $source_size != $target_size" >&2
                ((errors++))
            fi
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: Migration validation failed for $source_path" >&2
        return 1
    fi

    # Log successful migration
    echo "$(get_iso_timestamp) MIGRATED: $source_path -> $target_dir" >> "$MIGRATION_LOG"
    echo "MIGRATED: $source_path -> $target_dir"

    return 0
}

# Migrate all legacy backups
# Args: $1 = dry_run (true|false)
# Returns: 0 on success
migrate_all_backups() {
    local dry_run="${1:-false}"

    local backups
    backups=$(detect_legacy_backups)

    local count
    count=$(echo "$backups" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "No legacy backups found in $LEGACY_BACKUP_DIR"
        return 0
    fi

    echo "Found $count legacy backup(s) to migrate"
    echo ""

    local migrated=0
    local failed=0
    local skipped=0

    # Migrate each backup
    while IFS= read -r backup_json; do
        local result=0
        migrate_single_backup "$backup_json" "$dry_run" && result=0 || result=$?

        if [[ $result -eq 0 ]]; then
            migrated=$((migrated + 1))
        elif [[ $result -eq 2 ]]; then
            skipped=$((skipped + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(echo "$backups" | jq -c '.[]')

    echo ""
    echo "Migration summary:"
    echo "  Migrated: $migrated"
    echo "  Failed: $failed"
    echo "  Skipped (unknown): $skipped"

    [[ "$dry_run" == "false" ]] && echo "  Log: $MIGRATION_LOG"

    return 0
}

# ============================================================================
# CLEANUP
# ============================================================================

# Remove legacy backup directory after successful migration
# Returns: 0 on success, 1 on error
cleanup_legacy_backups() {
    local legacy_dir="$LEGACY_BACKUP_DIR"

    if [[ ! -d "$legacy_dir" ]]; then
        echo "No legacy backup directory found: $legacy_dir"
        return 0
    fi

    # Safety check: ensure new backup directory exists and has backups
    if [[ ! -d "$NEW_BACKUP_DIR" ]]; then
        echo "ERROR: New backup directory not found: $NEW_BACKUP_DIR" >&2
        echo "Run migration first before cleanup" >&2
        return 1
    fi

    local new_backup_count
    new_backup_count=$(find "$NEW_BACKUP_DIR" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)

    if [[ "$new_backup_count" -eq 0 ]]; then
        echo "ERROR: No backups found in new location: $NEW_BACKUP_DIR" >&2
        echo "Run migration first before cleanup" >&2
        return 1
    fi

    # Count legacy backups
    local legacy_count
    legacy_count=$(detect_legacy_backups | jq 'length')

    if [[ "$legacy_count" -gt 0 ]]; then
        echo "WARNING: $legacy_count legacy backup(s) still present" >&2
        echo "Ensure migration completed successfully before cleanup" >&2
        read -p "Continue with cleanup anyway? (yes/no): " -r confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Cleanup cancelled"
            return 1
        fi
    fi

    # Remove legacy directory
    echo "Removing legacy backup directory: $legacy_dir"
    rm -rf "$legacy_dir" || {
        echo "ERROR: Failed to remove legacy directory" >&2
        return 1
    }

    echo "Cleanup complete"
    return 0
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

# Display detected backups in human-readable format
display_detected_backups() {
    local backups
    backups=$(detect_legacy_backups)

    local count
    count=$(echo "$backups" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "No legacy backups found in $LEGACY_BACKUP_DIR"
        return 0
    fi

    echo "Detected $count legacy backup(s):"
    echo ""

    # Group by type
    local types
    types=$(echo "$backups" | jq -r '.[].type' | sort -u)

    while IFS= read -r type; do
        [[ -z "$type" ]] && continue

        echo "[$type backups]"

        echo "$backups" | jq -r --arg type "$type" \
            '.[] | select(.type == $type) |
            "  \(.path)\n    Timestamp: \(.timestamp)\n    Size: \(.size) bytes\n"'
    done <<< "$types"

    echo "Classification:"
    echo "  snapshot   - Complete system state captures"
    echo "  safety     - Pre-operation safety backups"
    echo "  archive    - Long-term archive backups"
    echo "  migration  - Schema migration backups"
    echo "  unknown    - Unrecognized backup patterns (will be skipped)"
}

# ============================================================================
# COMMAND-LINE INTERFACE
# ============================================================================

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Migrate legacy backups to new unified taxonomy.

OPTIONS:
    --detect        List detected legacy backups with classification
    --dry-run       Preview migration without making changes
    --run           Perform actual migration
    --cleanup       Remove old .backups directory after migration
    -h, --help      Show this help message

EXAMPLES:
    # Detect legacy backups
    $(basename "$0") --detect

    # Preview migration
    $(basename "$0") --dry-run

    # Perform migration
    $(basename "$0") --run

    # Cleanup after successful migration
    $(basename "$0") --cleanup

BACKUP TAXONOMY:
    Legacy location: .claude/.backups/
    New location:    .claude/backups/{type}/

    Types:
        snapshot/      - Point-in-time snapshots
        safety/        - Pre-operation safety backups
        incremental/   - Delta-based backups
        archive/       - Long-term archive backups
        migration/     - Schema migration backups

EOF
}

# Main entry point
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    case "$1" in
        --detect)
            display_detected_backups
            ;;
        --dry-run)
            echo "DRY RUN MODE - No changes will be made"
            echo ""
            migrate_all_backups "true"
            ;;
        --run)
            migrate_all_backups "false"
            ;;
        --cleanup)
            cleanup_legacy_backups
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "" >&2
            show_usage
            exit 1
            ;;
    esac
}

# Execute main if running as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
