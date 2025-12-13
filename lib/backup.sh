#!/usr/bin/env bash
# Library: backup.sh
# Purpose: Unified backup management for claude-todo
# Usage: Source this file - source "$LIB_DIR/backup.sh"
#
# ============================================================================
# BACKUP TYPE TAXONOMY
# ============================================================================
#
# The backup system uses a hierarchical directory structure to organize
# different backup types with specific purposes and retention policies.
#
# Directory Structure:
#   .claude/backups/
#   ├── snapshot/      Point-in-time snapshots (frequent, short retention)
#   ├── safety/        Pre-operation safety backups (auto-created before changes)
#   ├── incremental/   Delta-based backups (efficient storage, version history)
#   ├── archive/       Long-term archive backups (compressed, long retention)
#   └── migration/     Schema migration backups (versioned, permanent)
#
# Backup Types:
#
# 1. SNAPSHOT (snapshot/)
#    - Purpose: Complete system state capture at a point in time
#    - Trigger: Manual user request via `claude-todo backup`
#    - Contains: All system files (todo.json, todo-archive.json, todo-config.json, todo-log.json)
#    - Retention: Configurable (default: keep last 10)
#    - Use Case: Regular backups, before major changes, scheduled snapshots
#    - Naming: snapshot_YYYYMMDD_HHMMSS[_custom_name]
#
# 2. SAFETY (safety/)
#    - Purpose: Pre-operation safety net for rollback capability
#    - Trigger: Automatic before any file modification operation
#    - Contains: Single file being modified
#    - Retention: Time-based (default: 7 days) + count-based (default: keep last 5)
#    - Use Case: Rollback protection, error recovery, undo capability
#    - Naming: safety_YYYYMMDD_HHMMSS_<operation>_<filename>
#
# 3. INCREMENTAL (incremental/)
#    - Purpose: Efficient file versioning with delta tracking
#    - Trigger: Automatic on file changes (when enabled)
#    - Contains: Single file version
#    - Retention: Configurable (default: keep last 10)
#    - Use Case: Version history, file evolution tracking, efficient storage
#    - Naming: incremental_YYYYMMDD_HHMMSS_<filename>
#
# 4. ARCHIVE (archive/)
#    - Purpose: Long-term preservation of completed work
#    - Trigger: Automatic before archive operations
#    - Contains: todo.json and todo-archive.json
#    - Retention: Configurable (default: keep last 3)
#    - Use Case: Long-term storage, compliance, historical records
#    - Naming: archive_YYYYMMDD_HHMMSS
#    - Future: May include compression (.tar.gz)
#
# 5. MIGRATION (migration/)
#    - Purpose: Schema version migration safety
#    - Trigger: Automatic before schema migrations
#    - Contains: All system files with version information
#    - Retention: PERMANENT (never auto-deleted)
#    - Use Case: Rollback from failed migrations, schema change audit trail
#    - Naming: migration_v<from>_to_v<to>_YYYYMMDD_HHMMSS
#    - Special: Marked with neverDelete flag
#
# Retention Policies:
#   - snapshot:     Count-based (maxSnapshots, default 10)
#   - safety:       Time-based (safetyRetentionDays, default 7) AND count-based (maxSafetyBackups, default 5)
#   - incremental:  Count-based (maxIncremental, default 10)
#   - archive:      Count-based (maxArchiveBackups, default 3)
#   - migration:    NEVER deleted automatically
#
# Configuration:
#   All retention policies are configurable via todo-config.json:
#   {
#     "backup": {
#       "enabled": true,
#       "directory": ".claude/backups",
#       "maxSnapshots": 10,
#       "maxSafetyBackups": 5,
#       "maxIncremental": 10,
#       "maxArchiveBackups": 3,
#       "safetyRetentionDays": 7
#     }
#   }
#
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# LIBRARY DEPENDENCIES
# ============================================================================

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required libraries
if [[ -f "$_LIB_DIR/platform-compat.sh" ]]; then
    # shellcheck source=lib/platform-compat.sh
    source "$_LIB_DIR/platform-compat.sh"
else
    echo "ERROR: Cannot find platform-compat.sh in $_LIB_DIR" >&2
    exit 1
fi

if [[ -f "$_LIB_DIR/validation.sh" ]]; then
    # shellcheck source=lib/validation.sh
    source "$_LIB_DIR/validation.sh"
else
    echo "ERROR: Cannot find validation.sh in $_LIB_DIR" >&2
    exit 1
fi

if [[ -f "$_LIB_DIR/logging.sh" ]]; then
    # shellcheck source=lib/logging.sh
    source "$_LIB_DIR/logging.sh"
else
    echo "ERROR: Cannot find logging.sh in $_LIB_DIR" >&2
    exit 1
fi

if [[ -f "$_LIB_DIR/file-ops.sh" ]]; then
    # shellcheck source=lib/file-ops.sh
    source "$_LIB_DIR/file-ops.sh"
else
    echo "ERROR: Cannot find file-ops.sh in $_LIB_DIR" >&2
    exit 1
fi

# ============================================================================
# CONSTANTS
# ============================================================================

# Backup types
readonly BACKUP_TYPE_SNAPSHOT="snapshot"
readonly BACKUP_TYPE_SAFETY="safety"
readonly BACKUP_TYPE_INCREMENTAL="incremental"
readonly BACKUP_TYPE_ARCHIVE="archive"
readonly BACKUP_TYPE_MIGRATION="migration"

# Default configuration values
readonly DEFAULT_BACKUP_ENABLED=true
readonly DEFAULT_BACKUP_DIR=".claude/backups"
readonly DEFAULT_MAX_SNAPSHOTS=10
readonly DEFAULT_MAX_SAFETY_BACKUPS=5
readonly DEFAULT_MAX_INCREMENTAL=10
readonly DEFAULT_MAX_ARCHIVE_BACKUPS=3
readonly DEFAULT_SAFETY_RETENTION_DAYS=7

# ============================================================================
# INTERNAL FUNCTIONS
# ============================================================================

# Ensure backup type subdirectory exists
# Args: $1 = backup type
# Returns: 0 on success, 1 on error
_ensure_backup_type_dir() {
    local backup_type="$1"
    local backup_dir="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    local type_dir="$backup_dir/$backup_type"

    if [[ ! -d "$type_dir" ]]; then
        mkdir -p "$type_dir" || {
            echo "ERROR: Failed to create backup type directory: $type_dir" >&2
            return 1
        }
    fi

    return 0
}

# Load backup configuration from todo-config.json or use defaults
# Args: $1 = config file path (optional)
# Returns: 0 on success, 1 on error
_load_backup_config() {
    local config_file="${1:-${CLAUDE_TODO_DIR:-.claude}/todo-config.json}"

    # Initialize with defaults
    BACKUP_ENABLED="$DEFAULT_BACKUP_ENABLED"
    BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    MAX_SNAPSHOTS="$DEFAULT_MAX_SNAPSHOTS"
    MAX_SAFETY_BACKUPS="$DEFAULT_MAX_SAFETY_BACKUPS"
    MAX_INCREMENTAL="$DEFAULT_MAX_INCREMENTAL"
    MAX_ARCHIVE_BACKUPS="$DEFAULT_MAX_ARCHIVE_BACKUPS"
    SAFETY_RETENTION_DAYS="$DEFAULT_SAFETY_RETENTION_DAYS"

    # Override with config file values if available
    if [[ -f "$config_file" ]]; then
        BACKUP_ENABLED=$(jq -r '.backup.enabled // true' "$config_file" 2>/dev/null || echo "$DEFAULT_BACKUP_ENABLED")
        BACKUP_DIR=$(jq -r '.backup.directory // ".claude/backups"' "$config_file" 2>/dev/null || echo "$DEFAULT_BACKUP_DIR")
        MAX_SNAPSHOTS=$(jq -r '.backup.maxSnapshots // 10' "$config_file" 2>/dev/null || echo "$DEFAULT_MAX_SNAPSHOTS")
        MAX_SAFETY_BACKUPS=$(jq -r '.backup.maxSafetyBackups // 5' "$config_file" 2>/dev/null || echo "$DEFAULT_MAX_SAFETY_BACKUPS")
        MAX_INCREMENTAL=$(jq -r '.backup.maxIncremental // 10' "$config_file" 2>/dev/null || echo "$DEFAULT_MAX_INCREMENTAL")
        MAX_ARCHIVE_BACKUPS=$(jq -r '.backup.maxArchiveBackups // 3' "$config_file" 2>/dev/null || echo "$DEFAULT_MAX_ARCHIVE_BACKUPS")
        SAFETY_RETENTION_DAYS=$(jq -r '.backup.safetyRetentionDays // 7' "$config_file" 2>/dev/null || echo "$DEFAULT_SAFETY_RETENTION_DAYS")
    fi

    return 0
}

# Create backup metadata JSON
# Args: $1 = backup type, $2 = trigger, $3 = operation, $4 = files array (JSON), $5 = total size
# Output: metadata JSON object
_create_backup_metadata() {
    local backup_type="$1"
    local trigger="$2"
    local operation="$3"
    local files_json="$4"
    local total_size="$5"
    local timestamp
    local version

    timestamp=$(get_iso_timestamp)
    version="${CLAUDE_TODO_VERSION:-0.9.8}"

    jq -n \
        --arg type "$backup_type" \
        --arg ts "$timestamp" \
        --arg ver "$version" \
        --arg trigger "$trigger" \
        --arg op "$operation" \
        --argjson files "$files_json" \
        --argjson size "$total_size" \
        '{
            backupType: $type,
            timestamp: $ts,
            version: $ver,
            trigger: $trigger,
            operation: $op,
            files: $files,
            totalSize: $size
        }'
}

# Validate backup integrity
# Args: $1 = backup directory path
# Returns: 0 if valid, 1 if invalid
_validate_backup() {
    local backup_dir="$1"
    local errors=0

    if [[ ! -d "$backup_dir" ]]; then
        echo "ERROR: Backup directory not found: $backup_dir" >&2
        return 1
    fi

    # Check metadata exists
    if [[ ! -f "$backup_dir/metadata.json" ]]; then
        echo "ERROR: Backup metadata not found: $backup_dir/metadata.json" >&2
        ((errors++))
    fi

    # Validate all backed up files have valid JSON
    local file
    for file in "$backup_dir"/*.json; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "metadata.json" ]] && continue

        if ! jq empty "$file" 2>/dev/null; then
            echo "ERROR: Invalid JSON in backup file: $file" >&2
            ((errors++))
        fi
    done

    [[ $errors -eq 0 ]]
}

# Calculate total backup size in bytes
# Args: $1 = backup directory path
# Output: total size in bytes
_calculate_backup_size() {
    local backup_dir="$1"
    local total_size=0
    local file

    if [[ ! -d "$backup_dir" ]]; then
        echo "0"
        return 0
    fi

    for file in "$backup_dir"/*.json; do
        [[ ! -f "$file" ]] && continue
        local file_size
        file_size=$(get_file_size "$file")
        total_size=$((total_size + file_size))
    done

    echo "$total_size"
}

# ============================================================================
# CORE BACKUP FUNCTIONS
# ============================================================================

# Create full system snapshot backup
# Args: $1 = custom name (optional)
# Returns: 0 on success, 1 on error
# Output: backup directory path
create_snapshot_backup() {
    local custom_name="${1:-}"
    local timestamp
    local backup_id
    local backup_path
    local files_backed_up=()
    local total_size=0

    # Load config
    _load_backup_config

    # Check if backups are enabled
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        echo "WARNING: Backups are disabled in configuration" >&2
        return 1
    fi

    # Generate backup ID
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_id="snapshot_${timestamp}"
    if [[ -n "$custom_name" ]]; then
        backup_id="${backup_id}_${custom_name}"
    fi

    # Ensure backup type directory exists
    _ensure_backup_type_dir "$BACKUP_TYPE_SNAPSHOT" || return 1

    # Create backup directory structure
    backup_path="$BACKUP_DIR/$BACKUP_TYPE_SNAPSHOT/$backup_id"
    ensure_directory "$backup_path" || return 1

    # Backup all system files
    local source_dir="${CLAUDE_TODO_DIR:-.claude}"
    local files=("todo.json" "todo-archive.json" "todo-config.json" "todo-log.json")
    local file

    for file in "${files[@]}"; do
        local source_file="$source_dir/$file"
        local dest_file="$backup_path/$file"

        if [[ -f "$source_file" ]]; then
            # Validate source file
            if jq empty "$source_file" 2>/dev/null; then
                cp "$source_file" "$dest_file" || {
                    echo "ERROR: Failed to backup $file" >&2
                    return 1
                }

                local file_size
                file_size=$(get_file_size "$dest_file")
                local checksum
                checksum=$(safe_checksum "$dest_file")

                files_backed_up+=("$(jq -n \
                    --arg src "$file" \
                    --arg backup "$file" \
                    --argjson size "$file_size" \
                    --arg checksum "$checksum" \
                    '{source: $src, backup: $backup, size: $size, checksum: $checksum}')")

                total_size=$((total_size + file_size))
            else
                echo "WARNING: Skipping invalid JSON file: $file" >&2
            fi
        fi
    done

    # Create files array JSON
    local files_json
    files_json=$(printf '%s\n' "${files_backed_up[@]}" | jq -s '.')

    # Create metadata
    local metadata
    metadata=$(_create_backup_metadata \
        "$BACKUP_TYPE_SNAPSHOT" \
        "manual" \
        "backup" \
        "$files_json" \
        "$total_size")

    echo "$metadata" > "$backup_path/metadata.json"

    # Validate backup
    if ! _validate_backup "$backup_path"; then
        echo "ERROR: Backup validation failed" >&2
        return 1
    fi

    # Log backup creation
    log_operation "backup_created" "system" "null" "null" "null" \
        "$(jq -n --arg type "$BACKUP_TYPE_SNAPSHOT" --arg path "$backup_path" '{type: $type, path: $path}')" \
        "null" 2>/dev/null || true

    # Rotate old backups
    rotate_backups "$BACKUP_TYPE_SNAPSHOT"

    echo "$backup_path"
    return 0
}

# Create safety backup before operation
# Args: $1 = file path, $2 = operation name
# Returns: 0 on success, 1 on error
# Output: backup directory path
create_safety_backup() {
    local file="$1"
    local operation="${2:-unknown}"
    local timestamp
    local backup_id
    local backup_path

    if [[ -z "$file" ]]; then
        echo "ERROR: File path required for safety backup" >&2
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    # Load config
    _load_backup_config

    # Check if backups are enabled
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return 0  # Silently skip if disabled
    fi

    # Generate backup ID
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename
    filename=$(basename "$file")
    backup_id="safety_${timestamp}_${operation}_${filename}"

    # Ensure backup type directory exists
    _ensure_backup_type_dir "$BACKUP_TYPE_SAFETY" || return 1

    # Create backup directory
    backup_path="$BACKUP_DIR/$BACKUP_TYPE_SAFETY/$backup_id"
    ensure_directory "$backup_path" || return 1

    # Backup file
    local dest_file="$backup_path/$filename"
    cp "$file" "$dest_file" || {
        echo "ERROR: Failed to create safety backup" >&2
        return 1
    }

    # Calculate metadata
    local file_size
    file_size=$(get_file_size "$dest_file")
    local checksum
    checksum=$(safe_checksum "$dest_file")

    local files_json
    files_json=$(jq -n \
        --arg src "$filename" \
        --arg backup "$filename" \
        --argjson size "$file_size" \
        --arg checksum "$checksum" \
        '[{source: $src, backup: $backup, size: $size, checksum: $checksum}]')

    # Create metadata
    local metadata
    metadata=$(_create_backup_metadata \
        "$BACKUP_TYPE_SAFETY" \
        "auto" \
        "$operation" \
        "$files_json" \
        "$file_size")

    echo "$metadata" > "$backup_path/metadata.json"

    echo "$backup_path"
    return 0
}

# Create incremental backup for file versioning
# Args: $1 = file path
# Returns: 0 on success, 1 on error
# Output: backup directory path
create_incremental_backup() {
    local file="$1"
    local timestamp
    local backup_id
    local backup_path

    if [[ -z "$file" ]]; then
        echo "ERROR: File path required for incremental backup" >&2
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    # Load config
    _load_backup_config

    # Check if backups are enabled
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return 0  # Silently skip if disabled
    fi

    # Generate backup ID
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename
    filename=$(basename "$file")
    backup_id="incremental_${timestamp}_${filename}"

    # Ensure backup type directory exists
    _ensure_backup_type_dir "$BACKUP_TYPE_INCREMENTAL" || return 1

    # Create backup directory
    backup_path="$BACKUP_DIR/$BACKUP_TYPE_INCREMENTAL/$backup_id"
    ensure_directory "$backup_path" || return 1

    # Backup file
    local dest_file="$backup_path/$filename"
    cp "$file" "$dest_file" || {
        echo "ERROR: Failed to create incremental backup" >&2
        return 1
    }

    # Calculate metadata
    local file_size
    file_size=$(get_file_size "$dest_file")
    local checksum
    checksum=$(safe_checksum "$dest_file")

    local files_json
    files_json=$(jq -n \
        --arg src "$filename" \
        --arg backup "$filename" \
        --argjson size "$file_size" \
        --arg checksum "$checksum" \
        '[{source: $src, backup: $backup, size: $size, checksum: $checksum}]')

    # Create metadata
    local metadata
    metadata=$(_create_backup_metadata \
        "$BACKUP_TYPE_INCREMENTAL" \
        "auto" \
        "version" \
        "$files_json" \
        "$file_size")

    echo "$metadata" > "$backup_path/metadata.json"

    # Rotate old incremental backups
    rotate_backups "$BACKUP_TYPE_INCREMENTAL"

    echo "$backup_path"
    return 0
}

# Create archive backup before archiving tasks
# Args: none
# Returns: 0 on success, 1 on error
# Output: backup directory path
create_archive_backup() {
    local timestamp
    local backup_id
    local backup_path
    local files_backed_up=()
    local total_size=0

    # Load config
    _load_backup_config

    # Check if backups are enabled
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return 0  # Silently skip if disabled
    fi

    # Generate backup ID
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_id="archive_${timestamp}"

    # Ensure backup type directory exists
    _ensure_backup_type_dir "$BACKUP_TYPE_ARCHIVE" || return 1

    # Create backup directory
    backup_path="$BACKUP_DIR/$BACKUP_TYPE_ARCHIVE/$backup_id"
    ensure_directory "$backup_path" || return 1

    # Backup relevant files
    local source_dir="${CLAUDE_TODO_DIR:-.claude}"
    local files=("todo.json" "todo-archive.json")
    local file

    for file in "${files[@]}"; do
        local source_file="$source_dir/$file"
        local dest_file="$backup_path/$file"

        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file" || {
                echo "ERROR: Failed to backup $file" >&2
                return 1
            }

            local file_size
            file_size=$(get_file_size "$dest_file")
            local checksum
            checksum=$(safe_checksum "$dest_file")

            files_backed_up+=("$(jq -n \
                --arg src "$file" \
                --arg backup "$file" \
                --argjson size "$file_size" \
                --arg checksum "$checksum" \
                '{source: $src, backup: $backup, size: $size, checksum: $checksum}')")

            total_size=$((total_size + file_size))
        fi
    done

    # Create files array JSON
    local files_json
    files_json=$(printf '%s\n' "${files_backed_up[@]}" | jq -s '.')

    # Create metadata
    local metadata
    metadata=$(_create_backup_metadata \
        "$BACKUP_TYPE_ARCHIVE" \
        "auto" \
        "archive" \
        "$files_json" \
        "$total_size")

    echo "$metadata" > "$backup_path/metadata.json"

    # Rotate old archive backups
    rotate_backups "$BACKUP_TYPE_ARCHIVE"

    echo "$backup_path"
    return 0
}

# Create migration backup before schema migration
# Args: $1 = version string
# Returns: 0 on success, 1 on error
# Output: backup directory path
create_migration_backup() {
    local version="${1:-unknown}"
    local timestamp
    local backup_id
    local backup_path
    local files_backed_up=()
    local total_size=0

    # Load config
    _load_backup_config

    # Migration backups are ALWAYS created (ignore BACKUP_ENABLED)

    # Generate backup ID
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_id="migration_v${version}_${timestamp}"

    # Ensure backup type directory exists
    _ensure_backup_type_dir "$BACKUP_TYPE_MIGRATION" || return 1

    # Create backup directory
    backup_path="$BACKUP_DIR/$BACKUP_TYPE_MIGRATION/$backup_id"
    ensure_directory "$backup_path" || return 1

    # Backup all system files
    local source_dir="${CLAUDE_TODO_DIR:-.claude}"
    local files=("todo.json" "todo-archive.json" "todo-config.json" "todo-log.json")
    local file

    for file in "${files[@]}"; do
        local source_file="$source_dir/$file"
        local dest_file="$backup_path/$file"

        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file" || {
                echo "ERROR: Failed to backup $file" >&2
                return 1
            }

            local file_size
            file_size=$(get_file_size "$dest_file")
            local checksum
            checksum=$(safe_checksum "$dest_file")

            files_backed_up+=("$(jq -n \
                --arg src "$file" \
                --arg backup "$file" \
                --argjson size "$file_size" \
                --arg checksum "$checksum" \
                '{source: $src, backup: $backup, size: $size, checksum: $checksum}')")

            total_size=$((total_size + file_size))
        fi
    done

    # Create files array JSON
    local files_json
    files_json=$(printf '%s\n' "${files_backed_up[@]}" | jq -s '.')

    # Create metadata with neverDelete flag
    local metadata
    metadata=$(_create_backup_metadata \
        "$BACKUP_TYPE_MIGRATION" \
        "auto" \
        "migrate" \
        "$files_json" \
        "$total_size")

    # Add neverDelete flag
    metadata=$(echo "$metadata" | jq '. + {neverDelete: true}')

    echo "$metadata" > "$backup_path/metadata.json"

    # Migration backups are NEVER rotated

    echo "$backup_path"
    return 0
}

# ============================================================================
# BACKUP MANAGEMENT FUNCTIONS
# ============================================================================

# Rotate backups by type
# Args: $1 = backup type
# Returns: 0 on success
rotate_backups() {
    local backup_type="$1"
    local max_backups

    # Load config
    _load_backup_config

    # Determine max backups for this type
    case "$backup_type" in
        "$BACKUP_TYPE_SNAPSHOT")
            max_backups="$MAX_SNAPSHOTS"
            ;;
        "$BACKUP_TYPE_SAFETY")
            max_backups="$MAX_SAFETY_BACKUPS"
            ;;
        "$BACKUP_TYPE_INCREMENTAL")
            max_backups="$MAX_INCREMENTAL"
            ;;
        "$BACKUP_TYPE_ARCHIVE")
            max_backups="$MAX_ARCHIVE_BACKUPS"
            ;;
        "$BACKUP_TYPE_MIGRATION")
            # Migration backups are never deleted
            return 0
            ;;
        *)
            echo "ERROR: Unknown backup type: $backup_type" >&2
            return 1
            ;;
    esac

    # Skip rotation if max_backups is 0 (unlimited)
    if [[ "$max_backups" -eq 0 ]]; then
        return 0
    fi

    local backup_dir="$BACKUP_DIR/$backup_type"

    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi

    # Count existing backups
    local backup_count
    backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "${backup_type}_*" 2>/dev/null | wc -l)

    if [[ $backup_count -le $max_backups ]]; then
        return 0
    fi

    # Calculate how many to delete
    local delete_count=$((backup_count - max_backups))

    # Delete oldest backups using mtime-based sorting (directories)
    # Use find directly since safe_find_sorted_by_mtime is for files
    find "$backup_dir" -maxdepth 1 -name "${backup_type}_*" -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2- | head -n "$delete_count" | while read -r old_backup; do
        rm -rf "$old_backup" 2>/dev/null || true
    done || {
        # Fallback for BSD find (macOS)
        find "$backup_dir" -maxdepth 1 -name "${backup_type}_*" -type d 2>/dev/null | while read -r backup; do
            local mtime
            mtime=$(get_file_mtime "$backup")
            echo "$mtime $backup"
        done | sort -n | cut -d' ' -f2- | head -n "$delete_count" | while read -r old_backup; do
            rm -rf "$old_backup" 2>/dev/null || true
        done
    }

    return 0
}

# List backups with optional type filter
# Args: $1 = backup type (optional, defaults to all)
# Output: backup directory paths, one per line
list_backups() {
    local filter_type="${1:-all}"

    # Load config
    _load_backup_config

    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi

    if [[ "$filter_type" == "all" ]]; then
        # List all backup types
        local type
        for type in "$BACKUP_TYPE_SNAPSHOT" "$BACKUP_TYPE_SAFETY" "$BACKUP_TYPE_INCREMENTAL" "$BACKUP_TYPE_ARCHIVE" "$BACKUP_TYPE_MIGRATION"; do
            local type_dir="$BACKUP_DIR/$type"
            if [[ -d "$type_dir" ]]; then
                # List directories sorted by mtime
                find "$type_dir" -maxdepth 1 -name "${type}_*" -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2- || \
                find "$type_dir" -maxdepth 1 -name "${type}_*" -type d 2>/dev/null | while read -r backup; do
                    local mtime
                    mtime=$(get_file_mtime "$backup")
                    echo "$mtime $backup"
                done | sort -n | cut -d' ' -f2-
            fi
        done
    else
        # List specific type
        local type_dir="$BACKUP_DIR/$filter_type"
        if [[ -d "$type_dir" ]]; then
            # List directories sorted by mtime
            find "$type_dir" -maxdepth 1 -name "${filter_type}_*" -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2- || \
            find "$type_dir" -maxdepth 1 -name "${filter_type}_*" -type d 2>/dev/null | while read -r backup; do
                local mtime
                mtime=$(get_file_mtime "$backup")
                echo "$mtime $backup"
            done | sort -n | cut -d' ' -f2-
        fi
    fi
}

# Restore from backup
# Args: $1 = backup directory path or ID
# Returns: 0 on success, 1 on error
restore_backup() {
    local backup_id="$1"
    local backup_path

    if [[ -z "$backup_id" ]]; then
        echo "ERROR: Backup ID or path required" >&2
        return 1
    fi

    # Load config
    _load_backup_config

    # Resolve backup path
    if [[ -d "$backup_id" ]]; then
        backup_path="$backup_id"
    else
        # Search for backup ID in all types
        backup_path=$(list_backups | grep -F "$backup_id" | head -1)

        if [[ -z "$backup_path" ]]; then
            echo "ERROR: Backup not found: $backup_id" >&2
            return 1
        fi
    fi

    # Validate backup
    if ! _validate_backup "$backup_path"; then
        echo "ERROR: Backup validation failed: $backup_path" >&2
        return 1
    fi

    # Read metadata
    local metadata_file="$backup_path/metadata.json"
    local files
    files=$(jq -r '.files[].backup' "$metadata_file")

    # Restore each file
    local dest_dir="${CLAUDE_TODO_DIR:-.claude}"
    local file

    while IFS= read -r file; do
        local source_file="$backup_path/$file"
        local dest_file="$dest_dir/$file"

        if [[ -f "$source_file" ]]; then
            # Create safety backup of current file before restoring
            if [[ -f "$dest_file" ]]; then
                create_safety_backup "$dest_file" "restore" >/dev/null 2>&1 || true
            fi

            # Restore file
            cp "$source_file" "$dest_file" || {
                echo "ERROR: Failed to restore $file" >&2
                return 1
            }

            echo "Restored: $file" >&2
        fi
    done <<< "$files"

    # Log restore operation
    log_operation "backup_restored" "system" "null" "null" "null" \
        "$(jq -n --arg path "$backup_path" '{path: $path}')" \
        "null" 2>/dev/null || true

    return 0
}

# Get backup metadata
# Args: $1 = backup directory path
# Output: metadata JSON
get_backup_metadata() {
    local backup_path="$1"

    if [[ -z "$backup_path" ]]; then
        echo "ERROR: Backup path required" >&2
        return 1
    fi

    local metadata_file="$backup_path/metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        echo "ERROR: Metadata not found: $metadata_file" >&2
        return 1
    fi

    cat "$metadata_file"
}

# Prune old backups based on retention policies
# Args: none
# Returns: 0 on success
prune_backups() {
    # Load config
    _load_backup_config

    # Rotate each backup type
    rotate_backups "$BACKUP_TYPE_SNAPSHOT"
    rotate_backups "$BACKUP_TYPE_SAFETY"
    rotate_backups "$BACKUP_TYPE_INCREMENTAL"
    rotate_backups "$BACKUP_TYPE_ARCHIVE"

    # Prune safety backups by retention days
    if [[ "$SAFETY_RETENTION_DAYS" -gt 0 ]]; then
        local safety_dir="$BACKUP_DIR/$BACKUP_TYPE_SAFETY"

        if [[ -d "$safety_dir" ]]; then
            local cutoff_timestamp
            cutoff_timestamp=$(date_days_ago "$SAFETY_RETENTION_DAYS")
            local cutoff_epoch
            cutoff_epoch=$(iso_to_epoch "$cutoff_timestamp")

            safe_find_sorted_by_mtime "$safety_dir" "${BACKUP_TYPE_SAFETY}_*" \
                | while read -r backup; do
                    local backup_mtime
                    backup_mtime=$(get_file_mtime "$backup")

                    if [[ "$backup_mtime" -lt "$cutoff_epoch" ]]; then
                        rm -rf "$backup" 2>/dev/null || true
                    fi
                done
        fi
    fi

    return 0
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f create_snapshot_backup
export -f create_safety_backup
export -f create_incremental_backup
export -f create_archive_backup
export -f create_migration_backup
export -f rotate_backups
export -f list_backups
export -f restore_backup
export -f get_backup_metadata
export -f prune_backups
