#!/usr/bin/env bash
# CLAUDE-TODO Backup Script
# Create backups of all todo system files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
ARCHIVE_FILE="${ARCHIVE_FILE:-.claude/todo-archive.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
LOG_FILE="${LOG_FILE:-.claude/todo-log.json}"
BACKUP_DIR="${BACKUP_DIR:-.claude/backups}"

# Source logging library for should_use_color function
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "$LIB_DIR/logging.sh" ]]; then
  # shellcheck source=../lib/logging.sh
  source "$LIB_DIR/logging.sh"
fi

# Source output formatting and error libraries
if [[ -f "$LIB_DIR/output-format.sh" ]]; then
  # shellcheck source=../lib/output-format.sh
  source "$LIB_DIR/output-format.sh"
fi
if [[ -f "$LIB_DIR/exit-codes.sh" ]]; then
  # shellcheck source=../lib/exit-codes.sh
  source "$LIB_DIR/exit-codes.sh"
fi
if [[ -f "$LIB_DIR/error-json.sh" ]]; then
  # shellcheck source=../lib/error-json.sh
  source "$LIB_DIR/error-json.sh"
fi

# Colors (respects NO_COLOR and FORCE_COLOR environment variables per https://no-color.org)
if declare -f should_use_color >/dev/null 2>&1 && should_use_color; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Defaults
DESTINATION=""
COMPRESS=false
VERBOSE=false
CUSTOM_NAME=""
LIST_MODE=false
FORMAT=""
QUIET=false
COMMAND_NAME="backup"

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create timestamped backup of all todo system files.

Options:
  --destination DIR   Custom backup location (default: .claude/backups)
  --compress          Create compressed tarball of backup
  --name NAME         Custom backup name (appended to timestamp)
  --list              List available backups
  --verbose           Show detailed output
  -f, --format FMT    Output format: text, json (default: auto-detect)
  --human             Force human-readable text output
  --json              Force JSON output
  -q, --quiet         Suppress non-essential output
  -h, --help          Show this help

Backs up:
  - todo.json
  - todo-archive.json
  - todo-config.json
  - todo-log.json

Output:
  - Backup location
  - Files included
  - Total size
  - Validation status

JSON Output:
  {
    "_meta": {"command": "backup", "timestamp": "..."},
    "success": true,
    "backup": {"path": "/path/to/backup", "size": 1234, "tasksCount": 15, "files": [...]}
  }

Examples:
  $(basename "$0")                              # Default timestamped backup
  $(basename "$0") --name "before-refactor"     # Named backup
  $(basename "$0") --compress                   # Compressed backup
  $(basename "$0") --list                       # List all backups
  $(basename "$0") --json                       # JSON output for scripting
EOF
  exit 0
}

log_info()  { [[ "$QUIET" != true && "$FORMAT" != "json" ]] && echo -e "${GREEN}[INFO]${NC} $1" || true; }
log_warn()  { [[ "$FORMAT" != "json" ]] && echo -e "${YELLOW}[WARN]${NC} $1" || true; }
log_error() { [[ "$FORMAT" != "json" ]] && echo -e "${RED}[ERROR]${NC} $1" >&2 || true; }
log_debug() { [[ "$VERBOSE" == true && "$FORMAT" != "json" ]] && echo -e "${BLUE}[DEBUG]${NC} $1" || true; }

# Check dependencies
check_deps() {
  if ! command -v jq &> /dev/null; then
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_DEPENDENCY_MISSING" "jq is required but not installed" "${EXIT_DEPENDENCY_ERROR:-5}" false "Install jq: apt install jq (Debian) or brew install jq (macOS)"
    else
      log_error "jq is required but not installed"
    fi
    exit "${EXIT_DEPENDENCY_ERROR:-1}"
  fi

  if [[ "$COMPRESS" == true ]] && ! command -v tar &> /dev/null; then
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_DEPENDENCY_MISSING" "tar is required for compression but not installed" "${EXIT_DEPENDENCY_ERROR:-5}" false "Install tar or use backup without --compress"
    else
      log_error "tar is required for compression but not installed"
    fi
    exit "${EXIT_DEPENDENCY_ERROR:-1}"
  fi
}

# Validate file integrity
validate_file() {
  local file="$1"
  local name="$2"

  if [[ ! -f "$file" ]]; then
    log_warn "$name not found, skipping"
    return 1
  fi

  if ! jq empty "$file" 2>/dev/null; then
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_VALIDATION_SCHEMA" "$name has invalid JSON syntax" "${EXIT_VALIDATION_ERROR:-2}" false "Fix the JSON syntax in $file"
    else
      log_error "$name has invalid JSON syntax"
    fi
    return 1
  fi

  log_debug "$name validated successfully"
  return 0
}

# Get file size in human-readable format
get_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    if command -v numfmt &> /dev/null; then
      numfmt --to=iec-i --suffix=B "$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)"
    else
      du -h "$file" 2>/dev/null | cut -f1 || echo "0B"
    fi
  else
    echo "0B"
  fi
}

# List available backups
list_backups() {
  local backup_dir="$1"
  local json_backups="[]"  # For JSON output

  if [[ ! -d "$backup_dir" ]]; then
    if [[ "$FORMAT" == "json" ]]; then
      jq -n \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg dir "$backup_dir" \
        '{
          "$schema": "https://claude-todo.dev/schemas/output.schema.json",
          "_meta": {
            "command": "backup",
            "subcommand": "list",
            "timestamp": $timestamp,
            "format": "json"
          },
          "success": true,
          "backups": [],
          "count": 0,
          "directory": $dir
        }'
    else
      echo "No backups found"
    fi
    return 0
  fi

  if [[ "$FORMAT" != "json" ]]; then
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                           AVAILABLE BACKUPS                                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi

  # Find all backup directories and tarballs
  local found_backups=0

  # List backups from new unified taxonomy structure first
  for backup_type in snapshot safety incremental archive migration; do
    local type_dir="$backup_dir/$backup_type"
    if [[ -d "$type_dir" ]]; then
      while IFS= read -r -d '' backup; do
        if [[ -d "$backup" ]]; then
          found_backups=1
          local backup_name
          backup_name=$(basename "$backup")

          # Get metadata (new format: metadata.json)
          local metadata_file="${backup}/metadata.json"
          if [[ -f "$metadata_file" ]]; then
            local timestamp
            timestamp=$(jq -r '.timestamp // "unknown"' "$metadata_file" 2>/dev/null || echo "unknown")
            local file_count
            file_count=$(jq -r '.files | length' "$metadata_file" 2>/dev/null || echo "0")
            local total_size
            total_size=$(jq -r '.totalSize' "$metadata_file" 2>/dev/null || echo "0")
            local backup_type_label
            backup_type_label=$(jq -r '.backupType // "unknown"' "$metadata_file" 2>/dev/null || echo "unknown")

            # Convert size to human readable
            local size_human
            if command -v numfmt &> /dev/null; then
              size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
            else
              size_human="${total_size}B"
            fi

            if [[ "$FORMAT" == "json" ]]; then
              json_backups=$(echo "$json_backups" | jq \
                --arg name "$backup_name" \
                --arg path "$backup" \
                --arg type "$backup_type_label" \
                --arg timestamp "$timestamp" \
                --argjson fileCount "$file_count" \
                --argjson size "$total_size" \
                --arg sizeHuman "$size_human" \
                --argjson compressed false \
                '. + [{
                  "name": $name,
                  "path": $path,
                  "type": $type,
                  "timestamp": $timestamp,
                  "fileCount": $fileCount,
                  "size": $size,
                  "sizeHuman": $sizeHuman,
                  "compressed": $compressed
                }]')
            else
              echo -e "  ${GREEN}▸${NC} ${BLUE}$backup_name${NC} [$backup_type_label]"
              echo -e "    Timestamp: $timestamp"
              echo -e "    Files: $file_count | Size: $size_human"
              echo -e "    Path: $backup"
              echo ""
            fi
          fi
        fi
      done < <(find "$type_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    fi
  done

  # Also check for legacy backup_* directories (backward compatibility)
  while IFS= read -r -d '' backup; do
    if [[ -d "$backup" ]]; then
      found_backups=1
      local backup_name
      backup_name=$(basename "$backup")

      # Get metadata if available (old format: backup-metadata.json)
      local metadata_file="${backup}/backup-metadata.json"
      if [[ -f "$metadata_file" ]]; then
        local timestamp
        timestamp=$(jq -r '.timestamp // "unknown"' "$metadata_file" 2>/dev/null || echo "unknown")
        local file_count
        file_count=$(jq -r '.files | length' "$metadata_file" 2>/dev/null || echo "0")
        local total_size
        total_size=$(jq -r '.totalSize' "$metadata_file" 2>/dev/null || echo "0")

        # Convert size to human readable
        local size_human
        if command -v numfmt &> /dev/null; then
          size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
        else
          size_human="${total_size}B"
        fi

        if [[ "$FORMAT" == "json" ]]; then
          json_backups=$(echo "$json_backups" | jq \
            --arg name "$backup_name" \
            --arg path "$backup" \
            --arg timestamp "$timestamp" \
            --argjson fileCount "$file_count" \
            --argjson size "$total_size" \
            --arg sizeHuman "$size_human" \
            --argjson compressed false \
            '. + [{
              "name": $name,
              "path": $path,
              "type": "legacy",
              "timestamp": $timestamp,
              "fileCount": $fileCount,
              "size": $size,
              "sizeHuman": $sizeHuman,
              "compressed": $compressed
            }]')
        else
          echo -e "  ${GREEN}▸${NC} ${BLUE}$backup_name${NC}"
          echo -e "    Timestamp: $timestamp"
          echo -e "    Files: $file_count | Size: $size_human"
          echo -e "    Path: $backup"
          echo ""
        fi
      else
        # No metadata, just show basic info
        local mtime
        if [[ "$(uname)" == "Darwin" ]]; then
          mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null || echo "unknown")
        else
          mtime=$(stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        fi

        if [[ "$FORMAT" == "json" ]]; then
          json_backups=$(echo "$json_backups" | jq \
            --arg name "$backup_name" \
            --arg path "$backup" \
            --arg modified "$mtime" \
            --argjson compressed false \
            '. + [{
              "name": $name,
              "path": $path,
              "type": "legacy",
              "modified": $modified,
              "compressed": $compressed
            }]')
        else
          echo -e "  ${GREEN}▸${NC} ${BLUE}$backup_name${NC}"
          echo -e "    Modified: $mtime"
          echo -e "    Path: $backup"
          echo ""
        fi
      fi
    fi
  done < <(find "$backup_dir" -maxdepth 1 -type d -name "backup_*" -print0 2>/dev/null | sort -z)

  # List tarballs
  while IFS= read -r -d '' tarball; do
    if [[ -f "$tarball" ]]; then
      found_backups=1
      local tarball_name
      tarball_name=$(basename "$tarball")
      local size
      size=$(get_size "$tarball")
      local size_bytes
      size_bytes=$(stat -c%s "$tarball" 2>/dev/null || stat -f%z "$tarball" 2>/dev/null || echo 0)

      local mtime
      if [[ "$(uname)" == "Darwin" ]]; then
        mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$tarball" 2>/dev/null || echo "unknown")
      else
        mtime=$(stat -c "%y" "$tarball" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
      fi

      if [[ "$FORMAT" == "json" ]]; then
        json_backups=$(echo "$json_backups" | jq \
          --arg name "$tarball_name" \
          --arg path "$tarball" \
          --arg modified "$mtime" \
          --argjson size "$size_bytes" \
          --arg sizeHuman "$size" \
          --argjson compressed true \
          '. + [{
            "name": $name,
            "path": $path,
            "type": "compressed",
            "modified": $modified,
            "size": $size,
            "sizeHuman": $sizeHuman,
            "compressed": $compressed
          }]')
      else
        echo -e "  ${GREEN}▸${NC} ${BLUE}$tarball_name${NC} (compressed)"
        echo -e "    Modified: $mtime"
        echo -e "    Size: $size"
        echo -e "    Path: $tarball"
        echo ""
      fi
    fi
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "backup_*.tar.gz" -print0 2>/dev/null | sort -z)

  if [[ "$FORMAT" == "json" ]]; then
    local count
    count=$(echo "$json_backups" | jq 'length')
    jq -n \
      --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg dir "$backup_dir" \
      --argjson backups "$json_backups" \
      --argjson count "$count" \
      '{
        "$schema": "https://claude-todo.dev/schemas/output.schema.json",
        "_meta": {
          "command": "backup",
          "subcommand": "list",
          "timestamp": $timestamp,
          "format": "json"
        },
        "success": true,
        "backups": $backups,
        "count": $count,
        "directory": $dir
      }'
  else
    if [[ $found_backups -eq 0 ]]; then
      echo "  No backups found in: $backup_dir"
      echo ""
    fi
  fi

  return 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --destination)
      DESTINATION="$2"
      shift 2
      ;;
    --compress)
      COMPRESS=true
      shift
      ;;
    --name|-n)
      CUSTOM_NAME="$2"
      shift 2
      ;;
    --list|-l)
      LIST_MODE=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -f|--format)
      FORMAT="$2"
      shift 2
      ;;
    --human)
      FORMAT="text"
      shift
      ;;
    --json)
      FORMAT="json"
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
        output_error "$E_INPUT_INVALID" "Unknown option: $1" "${EXIT_USAGE_ERROR:-64}" false "Run 'claude-todo backup --help' for usage"
      else
        log_error "Unknown option: $1"
      fi
      exit "${EXIT_USAGE_ERROR:-64}"
      ;;
    *)
      shift
      ;;
  esac
done

# Resolve output format (CLI > env > config > TTY-aware default)
if declare -f resolve_format &>/dev/null; then
  FORMAT=$(resolve_format "$FORMAT")
else
  FORMAT="${FORMAT:-text}"
fi

check_deps

# Set backup directory
if [[ -n "$DESTINATION" ]]; then
  BACKUP_DIR="$DESTINATION"
fi

# Handle --list mode
if [[ "$LIST_MODE" == true ]]; then
  list_backups "$BACKUP_DIR"
  exit 0
fi

# Create timestamped backup directory
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Build backup name with optional custom name
if [[ -n "$CUSTOM_NAME" ]]; then
  # Sanitize custom name (remove special chars, replace spaces with hyphens)
  SAFE_NAME=$(echo "$CUSTOM_NAME" | tr -cs '[:alnum:]-' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//;s/-$//')
  BACKUP_NAME="backup_${TIMESTAMP}_${SAFE_NAME}"
else
  BACKUP_NAME="backup_${TIMESTAMP}"
fi

BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

log_info "Creating backup: $BACKUP_NAME"

# Create backup directory if it doesn't exist
if [[ ! -d "$BACKUP_DIR" ]]; then
  mkdir -p "$BACKUP_DIR"
  log_debug "Created backup directory: $BACKUP_DIR"
fi

# Create timestamped subdirectory
mkdir -p "$BACKUP_PATH"
log_debug "Created backup path: $BACKUP_PATH"

# Track backed up files and total size
BACKED_UP_FILES=()
TOTAL_SIZE=0
VALIDATION_ERRORS=0

# Backup function
backup_file() {
  local source="$1"
  local name="$2"

  if validate_file "$source" "$name"; then
    cp "$source" "${BACKUP_PATH}/$(basename "$source")"
    BACKED_UP_FILES+=("$name")

    local size
    size=$(stat -c%s "$source" 2>/dev/null || stat -f%z "$source" 2>/dev/null || echo 0)
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    log_debug "Backed up $name ($(get_size "$source"))"
  else
    ((VALIDATION_ERRORS++))
  fi
}

# Backup all files
log_info "Backing up files..."
backup_file "$TODO_FILE" "todo.json"
backup_file "$ARCHIVE_FILE" "todo-archive.json"
backup_file "$CONFIG_FILE" "todo-config.json"
backup_file "$LOG_FILE" "todo-log.json"

# Check if any files were backed up
if [[ ${#BACKED_UP_FILES[@]} -eq 0 ]]; then
  if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
    output_error "$E_FILE_NOT_FOUND" "No files were backed up" "${EXIT_FILE_ERROR:-4}" true "Ensure todo files exist in .claude/ directory"
  else
    log_error "No files were backed up"
  fi
  rmdir "$BACKUP_PATH" 2>/dev/null || true
  exit "${EXIT_FILE_ERROR:-4}"
fi

# Create metadata file
METADATA_FILE="${BACKUP_PATH}/backup-metadata.json"

# Build JSON with optional customName field
if [[ -n "$CUSTOM_NAME" ]]; then
  CUSTOM_NAME_JSON="\"customName\": \"$CUSTOM_NAME\","
else
  CUSTOM_NAME_JSON=""
fi

cat > "$METADATA_FILE" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "backupName": "$BACKUP_NAME",
  ${CUSTOM_NAME_JSON}
  "files": $(printf '%s\n' "${BACKED_UP_FILES[@]}" | jq -R . | jq -s .),
  "totalSize": $TOTAL_SIZE,
  "validationErrors": $VALIDATION_ERRORS,
  "compressed": $COMPRESS,
  "hostname": "$(hostname)",
  "user": "${USER:-unknown}"
}
EOF

log_debug "Created metadata file"

# Validate all backed up files
log_info "Validating backup integrity..."
BACKUP_VALIDATION_ERRORS=0

for file in "${BACKUP_PATH}"/*.json; do
  if [[ "$(basename "$file")" != "backup-metadata.json" ]]; then
    if ! jq empty "$file" 2>/dev/null; then
      if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
        output_error "$E_VALIDATION_SCHEMA" "Backup validation failed for $(basename "$file")" "${EXIT_VALIDATION_ERROR:-2}" false "Fix JSON syntax before retry"
      else
        log_error "Backup validation failed for $(basename "$file")"
      fi
      ((BACKUP_VALIDATION_ERRORS++))
    fi
  fi
done

if [[ $BACKUP_VALIDATION_ERRORS -gt 0 ]]; then
  if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
    output_error "$E_VALIDATION_SCHEMA" "Backup validation failed with $BACKUP_VALIDATION_ERRORS errors" "${EXIT_VALIDATION_ERROR:-2}" false "Review and fix the corrupted backup files"
  else
    log_error "Backup validation failed with $BACKUP_VALIDATION_ERRORS errors"
  fi
  exit "${EXIT_VALIDATION_ERROR:-2}"
fi

log_info "Backup validation successful"

# Compress if requested
if [[ "$COMPRESS" == true ]]; then
  log_info "Compressing backup..."

  TARBALL="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
  tar -czf "$TARBALL" -C "$BACKUP_DIR" "$BACKUP_NAME"

  if [[ -f "$TARBALL" ]]; then
    TARBALL_SIZE=$(get_size "$TARBALL")
    log_info "Created compressed archive: $TARBALL ($TARBALL_SIZE)"

    # Remove uncompressed directory
    rm -rf "$BACKUP_PATH"
    BACKUP_PATH="$TARBALL"
  else
    if [[ "$FORMAT" == "json" ]] && declare -f output_error &>/dev/null; then
      output_error "$E_FILE_WRITE_ERROR" "Failed to create compressed archive" "${EXIT_FILE_ERROR:-4}" false "Check disk space and tar installation"
    else
      log_error "Failed to create compressed archive"
    fi
    exit "${EXIT_FILE_ERROR:-4}"
  fi
fi

# Calculate total size in human-readable format
if command -v numfmt &> /dev/null; then
  TOTAL_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$TOTAL_SIZE")
else
  TOTAL_SIZE_HUMAN="${TOTAL_SIZE}B"
fi

# Get tasks count from todo.json for JSON output
TASKS_COUNT=0
if [[ -f "$TODO_FILE" ]]; then
  TASKS_COUNT=$(jq '.tasks | length' "$TODO_FILE" 2>/dev/null || echo 0)
fi

# Summary
if [[ "$FORMAT" == "json" ]]; then
  # JSON output
  jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg path "$BACKUP_PATH" \
    --arg name "$BACKUP_NAME" \
    --argjson size "$TOTAL_SIZE" \
    --arg sizeHuman "$TOTAL_SIZE_HUMAN" \
    --argjson tasksCount "$TASKS_COUNT" \
    --argjson compressed "$COMPRESS" \
    --argjson validationWarnings "$VALIDATION_ERRORS" \
    --argjson files "$(printf '%s\n' "${BACKED_UP_FILES[@]}" | jq -R . | jq -s .)" \
    '{
      "$schema": "https://claude-todo.dev/schemas/output.schema.json",
      "_meta": {
        "command": "backup",
        "timestamp": $timestamp,
        "version": $version,
        "format": "json"
      },
      "success": true,
      "backup": {
        "path": $path,
        "name": $name,
        "size": $size,
        "sizeHuman": $sizeHuman,
        "tasksCount": $tasksCount,
        "files": $files,
        "compressed": $compressed,
        "validationWarnings": $validationWarnings
      }
    }'
else
  # Text output
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║              BACKUP COMPLETED SUCCESSFULLY               ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BLUE}Backup Location:${NC}"
  echo -e "    $BACKUP_PATH"
  echo ""
  echo -e "  ${BLUE}Files Included:${NC}"
  for file in "${BACKED_UP_FILES[@]}"; do
    echo -e "    ✓ $file"
  done
  echo ""
  echo -e "  ${BLUE}Total Size:${NC} $TOTAL_SIZE_HUMAN"
  echo ""

  if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    echo -e "  ${YELLOW}⚠  Warning:${NC} $VALIDATION_ERRORS file(s) had issues during backup"
    echo ""
  fi
fi

# Clean old backups if configured
if [[ -f "$CONFIG_FILE" ]]; then
  MAX_BACKUPS=$(jq -r '.backups.maxBackups // 10' "$CONFIG_FILE" 2>/dev/null || echo 10)

  if [[ "$MAX_BACKUPS" -gt 0 ]]; then
    log_debug "Checking backup retention (max: $MAX_BACKUPS)"

    # Count backups (both directories and tarballs)
    BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 \( -type d -name "backup_*" -o -type f -name "backup_*.tar.gz" \) | wc -l)

    if [[ $BACKUP_COUNT -gt $MAX_BACKUPS ]]; then
      REMOVE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
      log_info "Removing $REMOVE_COUNT old backup(s) (retention: $MAX_BACKUPS)"

      # Remove oldest backups
      find "$BACKUP_DIR" -maxdepth 1 \( -type d -name "backup_*" -o -type f -name "backup_*.tar.gz" \) -printf '%T+ %p\n' | \
        sort | \
        head -n "$REMOVE_COUNT" | \
        cut -d' ' -f2- | \
        while read -r old_backup; do
          rm -rf "$old_backup"
          log_debug "Removed old backup: $(basename "$old_backup")"
        done
    fi
  fi
fi

exit 0
