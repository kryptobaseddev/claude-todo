#!/usr/bin/env bash
# CLAUDE-TODO Backup Script
# Create backups of all todo system files
set -euo pipefail

TODO_FILE="${TODO_FILE:-.claude/todo.json}"
ARCHIVE_FILE="${ARCHIVE_FILE:-.claude/todo-archive.json}"
CONFIG_FILE="${CONFIG_FILE:-.claude/todo-config.json}"
LOG_FILE="${LOG_FILE:-.claude/todo-log.json}"
BACKUP_DIR="${BACKUP_DIR:-.claude/.backups}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
DESTINATION=""
COMPRESS=false
VERBOSE=false

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create timestamped backup of all todo system files.

Options:
  --destination DIR   Custom backup location (default: .claude/.backups)
  --compress          Create compressed tarball of backup
  --verbose           Show detailed output
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
EOF
  exit 0
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_debug() { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $1" || true; }

# Check dependencies
check_deps() {
  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
  fi

  if [[ "$COMPRESS" == true ]] && ! command -v tar &> /dev/null; then
    log_error "tar is required for compression but not installed"
    exit 1
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
    log_error "$name has invalid JSON syntax"
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
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      log_error "Unknown option: $1"
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

check_deps

# Set backup directory
if [[ -n "$DESTINATION" ]]; then
  BACKUP_DIR="$DESTINATION"
fi

# Create timestamped backup directory
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="backup_${TIMESTAMP}"
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
  log_error "No files were backed up"
  rmdir "$BACKUP_PATH" 2>/dev/null || true
  exit 1
fi

# Create metadata file
METADATA_FILE="${BACKUP_PATH}/backup-metadata.json"
cat > "$METADATA_FILE" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "backupName": "$BACKUP_NAME",
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
      log_error "Backup validation failed for $(basename "$file")"
      ((BACKUP_VALIDATION_ERRORS++))
    fi
  fi
done

if [[ $BACKUP_VALIDATION_ERRORS -gt 0 ]]; then
  log_error "Backup validation failed with $BACKUP_VALIDATION_ERRORS errors"
  exit 1
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
    log_error "Failed to create compressed archive"
    exit 1
  fi
fi

# Calculate total size in human-readable format
if command -v numfmt &> /dev/null; then
  TOTAL_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$TOTAL_SIZE")
else
  TOTAL_SIZE_HUMAN="${TOTAL_SIZE}B"
fi

# Summary
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
