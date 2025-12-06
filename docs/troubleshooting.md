# Troubleshooting Guide

This guide covers common issues, their causes, and step-by-step solutions for the claude-todo system.

## Quick Diagnostic Commands

```bash
# Check system health
~/.claude-todo/scripts/validate.sh --verbose

# Verify installation
ls -la ~/.claude-todo/scripts/
which validate.sh  # If added to PATH

# Check current project status
cd /path/to/project
~/.claude-todo/scripts/validate.sh
~/.claude-todo/scripts/list-tasks.sh
```

---

## Common Errors

### 1. Permission Denied Errors

**Symptom:**
```
Error: Cannot write to file
File: .claude/todo.json
Reason: Permission denied
```

**Causes:**
- File permissions too restrictive
- Directory permissions incorrect
- File owned by different user

**Solutions:**

```bash
# Check current permissions
ls -la .claude/

# Fix file permissions (readable by all, writable by owner)
chmod 644 .claude/todo.json
chmod 644 .claude/todo-config.json
chmod 644 .claude/todo-archive.json
chmod 644 .claude/todo-log.json

# Fix directory permissions
chmod 755 .claude/

# Fix backup directory permissions (owner only)
chmod 700 .claude/.backups/
chmod 600 .claude/.backups/*.json

# Check file ownership
ls -la .claude/
# If owned by wrong user:
sudo chown $USER:$USER .claude/todo*.json
```

**Prevention:**
- Run init.sh from project directory as your user
- Don't use sudo with todo scripts
- Verify permissions after manual file edits

---

### 2. Invalid JSON Errors

**Symptom:**
```
Error: Invalid JSON format
File: .claude/todo.json
Line: 23
Issue: Unexpected token ','
```

**Causes:**
- Manual editing introduced syntax errors
- Trailing commas in JSON
- Missing quotes around strings
- Unclosed brackets or braces
- Special characters not escaped

**Solutions:**

**Step 1: Validate JSON syntax**
```bash
# Check if jq can parse the file
jq . .claude/todo.json

# If error, jq will show line number
# Common issues:
# - Trailing comma in last object
# - Missing closing bracket/brace
# - Unescaped quotes in strings
```

**Step 2: Find the exact issue**
```bash
# Use verbose validation
~/.claude-todo/scripts/validate.sh --verbose

# Or manually inspect around error line
sed -n '20,30p' .claude/todo.json  # Show lines 20-30
```

**Step 3: Fix the issue**
```bash
# Common fixes:
# 1. Remove trailing commas
sed -i 's/,\s*}/}/g' .claude/todo.json
sed -i 's/,\s*]/]/g' .claude/todo.json

# 2. Fix unescaped quotes
# Edit manually with: nano .claude/todo.json
# Replace: "title": "He said "hello""
# With:    "title": "He said \"hello\""

# 3. Restore from backup if heavily corrupted
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

**Step 4: Verify fix**
```bash
~/.claude-todo/scripts/validate.sh
```

**Prevention:**
- Use provided scripts instead of manual editing
- Always validate after manual edits
- Enable JSON linting in your editor
- Use jq for manual JSON operations

---

### 3. Schema Validation Failures

**Symptom:**
```
Error: Invalid JSON Schema
File: .claude/todo.json
Issue: Missing required field "title" in task ID: task-123456
```

**Common Schema Errors:**

#### Missing Required Fields

**Error:** `Missing required field "title"`
```json
// WRONG
{
  "id": "task-123",
  "status": "pending"
}

// CORRECT
{
  "id": "task-123",
  "title": "Fix bug",
  "status": "pending",
  "priority": "medium",
  "createdAt": "2024-12-05T10:00:00Z"
}
```

**Fix:**
```bash
# Add missing field manually
nano .claude/todo.json

# Or restore from backup
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1
```

#### Invalid Status Value

**Error:** `Invalid status value: "done"`
```json
// WRONG - "done" is not valid
{
  "status": "done"
}

// CORRECT - Must be: pending, active, blocked, or done
{
  "status": "done"
}
```

**Fix:**
```bash
# Use jq to fix invalid statuses
jq '.tasks = [.tasks[] | if .status == "completed" then .status = "done" else . end]' \
  .claude/todo.json > .claude/todo.json.tmp && mv .claude/todo.json.tmp .claude/todo.json

# Validate fix
~/.claude-todo/scripts/validate.sh
```

#### Invalid Type

**Error:** `Expected string, got number`
```json
// WRONG
{
  "title": 123
}

// CORRECT
{
  "title": "Task number 123"
}
```

**Fix:**
```bash
# Edit manually to correct types
nano .claude/todo.json

# Validate
~/.claude-todo/scripts/validate.sh
```

**Solutions for All Schema Errors:**

1. **Read error message carefully** - tells you exact field and issue
2. **Check schema reference** - see `/docs/schema-reference.md`
3. **Compare with template** - `~/.claude-todo/templates/todo.template.json`
4. **Restore from backup** - if too many errors

---

### 4. Duplicate ID Errors

**Symptom:**
```
Error: Duplicate task ID detected
File: .claude/todo.json
Duplicate ID: task-1733395200-xyz789
Location: Line 15 and Line 42
Fix: Regenerate unique ID for one task
```

**Causes:**
- Copy-paste task without changing ID
- Manual editing error
- Script bug (rare)
- Corruption during concurrent access

**Solutions:**

**Step 1: Locate duplicates**
```bash
# Find all task IDs and count occurrences
jq -r '.tasks[].id' .claude/todo.json | sort | uniq -d

# Show full tasks with duplicate IDs
jq '.tasks[] | select(.id == "task-1733395200-xyz789")' .claude/todo.json
```

**Step 2: Regenerate unique ID**
```bash
# Generate new unique ID
NEW_ID="task-$(date +%s)-$(openssl rand -hex 3)"
echo "New ID: $NEW_ID"

# Manually edit and replace ONE instance
nano .claude/todo.json

# Or use sed (careful!)
# This replaces only FIRST occurrence
sed -i "0,/task-1733395200-xyz789/s//$NEW_ID/" .claude/todo.json
```

**Step 3: Verify fix**
```bash
# Check no more duplicates
~/.claude-todo/scripts/validate.sh

# Verify task count unchanged
jq '.tasks | length' .claude/todo.json
```

**Prevention:**
- Always use add-task.sh to create tasks
- Don't copy-paste tasks manually
- Run validation after manual edits

---

### 5. Missing Required Fields

**Symptom:**
```
Error: Task missing required field
Field: title
Task ID: task-456789
```

**Solutions:**

**Step 1: Identify affected tasks**
```bash
# Find tasks missing title
jq '.tasks[] | select(.title == null or .title == "") | .id' .claude/todo.json

# Show full task details
jq '.tasks[] | select(.title == null)' .claude/todo.json
```

**Step 2: Add missing field**
```bash
# Option 1: Manual edit
nano .claude/todo.json
# Add: "title": "Task title"

# Option 2: Generate placeholder titles
jq '.tasks = [.tasks[] |
  if (.title == null or .title == "")
  then .title = "Task \(.id)"
  else . end]' \
  .claude/todo.json > .claude/todo.json.tmp && \
  mv .claude/todo.json.tmp .claude/todo.json
```

**Step 3: Validate**
```bash
~/.claude-todo/scripts/validate.sh
```

---

## Installation Issues

### 1. Script Not Found

**Symptom:**
```
bash: add-task.sh: command not found
```

**Causes:**
- Installation not completed
- Scripts not in PATH
- Wrong directory

**Solutions:**

**Step 1: Verify installation**
```bash
# Check if installed
ls -la ~/.claude-todo/scripts/

# Should see: add-task.sh, complete-task.sh, etc.
```

**Step 2: If not installed**
```bash
cd /path/to/claude-todo
./install.sh
```

**Step 3: Add to PATH or use full path**
```bash
# Option 1: Use full path
~/.claude-todo/scripts/add-task.sh "My task"

# Option 2: Add to PATH (permanent)
echo 'export PATH="$HOME/.claude-todo/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Now you can use:
add-task.sh "My task"
```

**Step 4: Create alias (alternative)**
```bash
# Add to ~/.bashrc or ~/.zshrc
alias todo-add='~/.claude-todo/scripts/add-task.sh'
alias todo-list='~/.claude-todo/scripts/list-tasks.sh'
alias todo-complete='~/.claude-todo/scripts/complete-task.sh'
alias todo-validate='~/.claude-todo/scripts/validate.sh'

source ~/.bashrc
```

---

### 2. jq Not Installed

**Symptom:**
```
Error: jq command not found
Required for JSON processing
```

**Solutions:**

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install jq

# macOS
brew install jq

# Fedora/RHEL
sudo dnf install jq

# Arch Linux
sudo pacman -S jq

# Verify installation
jq --version
```

---

### 3. PATH Not Configured

**Symptom:**
Scripts work with full path but not with short names.

**Solutions:**

```bash
# Check current PATH
echo $PATH

# Add to PATH temporarily (current session)
export PATH="$HOME/.claude-todo/scripts:$PATH"

# Add to PATH permanently
# For bash:
echo 'export PATH="$HOME/.claude-todo/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc

# For zsh:
echo 'export PATH="$HOME/.claude-todo/scripts:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Verify
which add-task.sh
```

---

## Data Recovery

### 1. Restoring from Backups

**Scenario:** Corrupted todo.json file

**Step 1: List available backups**
```bash
ls -lah .claude/.backups/
# Shows: todo.json.1, todo.json.2, etc.
# Most recent = highest number
```

**Step 2: Validate backup integrity**
```bash
~/.claude-todo/scripts/validate.sh .claude/.backups/todo.json.1
```

**Step 3: Restore backup**
```bash
# Option 1: Use restore script
~/.claude-todo/scripts/restore.sh .claude/.backups/todo.json.1

# Option 2: Manual restore
cp .claude/todo.json .claude/todo.json.corrupted  # Backup corrupted file
cp .claude/.backups/todo.json.1 .claude/todo.json
```

**Step 4: Verify restoration**
```bash
~/.claude-todo/scripts/validate.sh
~/.claude-todo/scripts/list-tasks.sh
```

**Step 5: Reconcile lost changes (if needed)**
```bash
# Compare corrupted file with restored version
jq . .claude/todo.json.corrupted > /tmp/corrupted.formatted.json
jq . .claude/todo.json > /tmp/restored.formatted.json
diff /tmp/corrupted.formatted.json /tmp/restored.formatted.json

# Manually re-add any lost tasks if needed
```

---

### 2. Fixing Corrupted JSON

**Scenario:** JSON file is malformed but contains valuable data

**Step 1: Backup corrupted file**
```bash
cp .claude/todo.json .claude/todo.json.corrupted
```

**Step 2: Attempt automated fixes**
```bash
# Try jq formatting (fixes many issues)
jq . .claude/todo.json.corrupted > .claude/todo.json.fixed

# If successful, replace
mv .claude/todo.json.fixed .claude/todo.json
```

**Step 3: Manual recovery if automated fails**
```bash
# Extract just the tasks array
jq '.tasks' .claude/todo.json.corrupted > /tmp/tasks-only.json

# Create new valid structure
cat > .claude/todo.json << 'EOF'
{
  "version": "1.0.0",
  "tasks": []
}
EOF

# Merge tasks back
jq --slurpfile tasks /tmp/tasks-only.json '.tasks = $tasks[0]' \
  .claude/todo.json > .claude/todo.json.tmp && \
  mv .claude/todo.json.tmp .claude/todo.json
```

**Step 4: Validate**
```bash
~/.claude-todo/scripts/validate.sh
```

**Step 5: If still corrupted, start fresh**
```bash
# Save corrupted file for manual data extraction
mv .claude/todo.json .claude/todo.json.backup

# Initialize fresh file
cp ~/.claude-todo/templates/todo.template.json .claude/todo.json

# Manually extract and re-add tasks from backup
cat .claude/todo.json.backup
# Use add-task.sh to recreate each task
```

---

### 3. Regenerating IDs

**Scenario:** Multiple tasks have duplicate or invalid IDs

**Step 1: Backup current file**
```bash
cp .claude/todo.json .claude/todo.json.before-id-fix
```

**Step 2: Regenerate all IDs**
```bash
# Create script to regenerate IDs
cat > /tmp/regenerate-ids.sh << 'EOF'
#!/bin/bash
INPUT_FILE="$1"
OUTPUT_FILE="$2"

jq '.tasks = [.tasks[] | .id = "task-" + (now | tostring | split(".")[0]) + "-" + (env.RANDOM)]' \
  "$INPUT_FILE" > "$OUTPUT_FILE"

# Add small delay to ensure unique timestamps
sleep 1
EOF

chmod +x /tmp/regenerate-ids.sh

# Run regeneration
/tmp/regenerate-ids.sh .claude/todo.json .claude/todo.json.new-ids
```

**Step 3: Validate**
```bash
~/.claude-todo/scripts/validate.sh .claude/todo.json.new-ids
```

**Step 4: Replace if valid**
```bash
mv .claude/todo.json.new-ids .claude/todo.json
```

**Note:** This breaks log references. Only use as last resort.

---

## Validation Errors Explained

### Schema Validation Messages

#### "Missing required field"
**Meaning:** Task object lacks a mandatory field.
**Required fields:** `id`, `title`, `status`, `priority`, `createdAt`

**Fix:**
```bash
# Add missing field manually
nano .claude/todo.json
```

#### "Invalid type"
**Meaning:** Field has wrong data type (e.g., number instead of string).

**Example:**
```json
// WRONG
{"status": 123}

// CORRECT
{"status": "pending"}
```

#### "Invalid enum value"
**Meaning:** Status field has value not in allowed list.
**Valid values:** `"pending"`, `"active"`, `"blocked"`, `"done"`

**Fix:**
```bash
# Replace invalid status
jq '.tasks = [.tasks[] |
  if .status == "todo" then .status = "pending"
  elif .status == "completed" then .status = "done"
  elif .status == "in_progress" then .status = "active"
  else . end]' \
  .claude/todo.json > .claude/todo.json.tmp && \
  mv .claude/todo.json.tmp .claude/todo.json
```

---

### Anti-Hallucination Check Failures

#### Duplicate ID Detection
**Error:** `Duplicate task ID: task-xyz`

**Fix:** See [Duplicate ID Errors](#4-duplicate-id-errors) section above.

#### Title/Description Pairing
**Error:** `Task has description but missing title`

**Meaning:** Tasks must have a title. Description is optional but provides additional context.

**Example:**
```json
// WRONG - Missing title
{
  "description": "Fix authentication bug in login flow",
  "status": "pending"
}

// CORRECT
{
  "title": "Fix authentication bug",
  "description": "Fix authentication bug in login flow",
  "status": "pending",
  "priority": "high",
  "createdAt": "2024-12-05T10:00:00Z"
}
```

**Fix:**
```bash
# Generate titles from descriptions if title is missing
jq '.tasks = [.tasks[] |
  if (.title == "" or .title == null)
  then .title = (.description // "Untitled Task")
  else . end]' \
  .claude/todo.json > .claude/todo.json.tmp && \
  mv .claude/todo.json.tmp .claude/todo.json
```

#### Timestamp Sanity Check
**Error:** `Task createdAt is in the future`

**Meaning:** Timestamp validation failed (likely manual editing error).

**Fix:**
```bash
# Set current timestamp for invalid tasks
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.tasks = [.tasks[] |
  if (.createdAt > $now)
  then .createdAt = $now
  else . end]' \
  .claude/todo.json > .claude/todo.json.tmp && \
  mv .claude/todo.json.tmp .claude/todo.json
```

#### Duplicate Content Warning
**Error:** `Warning: Similar task titles detected`

**Meaning:** Multiple tasks have identical or very similar titles.

**This is a WARNING, not an error.** Review tasks to check if duplicates are intentional.

**Fix (if unintentional):**
```bash
# List tasks with identical titles
jq -r '.tasks[] | .title' .claude/todo.json | sort | uniq -d

# Manually review and remove duplicates
~/.claude-todo/scripts/list-tasks.sh
# Note ID of duplicate task
# Manually edit to remove
nano .claude/todo.json
```

---

## Performance Issues

### 1. Large File Handling

**Symptom:** Scripts slow with many tasks (>500)

**Solutions:**

**Step 1: Check file sizes**
```bash
du -h .claude/todo*.json

# If todo.json > 500KB, consider archiving
```

**Step 2: Archive old completed tasks**
```bash
# Archive tasks completed more than 7 days ago
~/.claude-todo/scripts/archive.sh --days 7

# Or force immediate archive of ALL completed
~/.claude-todo/scripts/archive.sh --force
```

**Step 3: Verify performance improvement**
```bash
time ~/.claude-todo/scripts/list-tasks.sh
```

**Step 4: Configure automatic archiving**
```bash
# Edit config
nano .claude/todo-config.json

# Set:
{
  "archive": {
    "enabled": true,
    "archive_after_days": 7,
    "auto_archive_on_complete": true
  }
}
```

---

### 2. Archive Recommendations

**When to archive:**
- todo.json has >200 tasks
- Most tasks are completed
- List operations feel slow
- After major project milestones

**Archive best practices:**
```bash
# Regular archiving (weekly)
~/.claude-todo/scripts/archive.sh --days 7

# Keep archive size manageable
jq '.tasks | length' .claude/todo-archive.json
# If >1000, consider:
# 1. Exporting to external file
# 2. Compressing old archives
# 3. Creating yearly archives

# Create yearly archive snapshot
cp .claude/todo-archive.json \
   .claude/archive-backup-$(date +%Y).json
```

**Archive maintenance:**
```bash
# Compress old archives
gzip .claude/archive-backup-2024.json

# Clear very old archives (optional)
# Only if you don't need historical data
rm .claude/archive-backup-2023.json.gz
```

---

## Debug Commands

### 1. Verbose Validation

**Basic validation:**
```bash
~/.claude-todo/scripts/validate.sh
```

**Verbose output (shows all checks):**
```bash
~/.claude-todo/scripts/validate.sh --verbose
```

**Expected output:**
```
Validating: .claude/todo.json
✓ File exists
✓ JSON syntax valid
✓ Schema validation passed
✓ All task IDs unique
✓ All statuses valid (pending|active|blocked|done)
✓ All timestamps valid
✓ All required fields present (id, title, status, priority, createdAt)
✓ No duplicate titles

Validating: .claude/todo-archive.json
✓ File exists
✓ JSON syntax valid
✓ Schema validation passed
✓ All archived tasks have status=done
✓ No ID conflicts with todo.json

Validating: .claude/todo-config.json
✓ File exists
✓ JSON syntax valid
✓ Schema validation passed
✓ All required fields present
✓ All values in valid ranges

Validating: .claude/todo-log.json
✓ File exists
✓ JSON syntax valid
✓ Schema validation passed
✓ All log entries chronological
✓ All referenced task IDs exist

All validations passed!
```

---

### 2. Checking File Integrity

**Comprehensive integrity check:**
```bash
# Create integrity check script
cat > /tmp/integrity-check.sh << 'EOF'
#!/bin/bash

echo "=== File Integrity Check ==="

# Check file existence
for file in todo.json todo-config.json todo-archive.json todo-log.json; do
  if [ -f ".claude/$file" ]; then
    echo "✓ $file exists"
  else
    echo "✗ $file missing"
  fi
done

# Check JSON syntax
echo ""
echo "=== JSON Syntax Check ==="
for file in .claude/todo*.json; do
  if jq empty "$file" 2>/dev/null; then
    echo "✓ $(basename $file) valid JSON"
  else
    echo "✗ $(basename $file) invalid JSON"
  fi
done

# Check file sizes
echo ""
echo "=== File Sizes ==="
du -h .claude/todo*.json

# Check backup status
echo ""
echo "=== Backup Status ==="
if [ -d ".claude/.backups" ]; then
  BACKUP_COUNT=$(ls .claude/.backups/ 2>/dev/null | wc -l)
  echo "Backups available: $BACKUP_COUNT"
  ls -lh .claude/.backups/ | tail -5
else
  echo "No backups directory"
fi

# Check task counts
echo ""
echo "=== Task Counts ==="
echo "Active tasks: $(jq '.tasks | length' .claude/todo.json 2>/dev/null || echo 0)"
echo "Archived tasks: $(jq '.tasks | length' .claude/todo-archive.json 2>/dev/null || echo 0)"
echo "Log entries: $(jq '.entries | length' .claude/todo-log.json 2>/dev/null || echo 0)"

# Check for permission issues
echo ""
echo "=== File Permissions ==="
ls -la .claude/todo*.json
EOF

chmod +x /tmp/integrity-check.sh
/tmp/integrity-check.sh
```

---

### 3. Log Analysis

**View recent operations:**
```bash
# Last 10 log entries
jq '.entries | .[-10:]' .claude/todo-log.json

# Last 5 with pretty printing
jq '.entries | .[-5:] | .[] |
  {timestamp, operation, task_id, details}' \
  .claude/todo-log.json
```

**Search for specific task history:**
```bash
# All operations for task
TASK_ID="task-1733395200-xyz789"
jq --arg id "$TASK_ID" \
  '.entries[] | select(.task_id == $id)' \
  .claude/todo-log.json
```

**Operations by type:**
```bash
# Count operations by type
jq -r '.entries[] | .operation' .claude/todo-log.json | sort | uniq -c

# Show all archive operations
jq '.entries[] | select(.operation == "archive")' .claude/todo-log.json
```

**Date range analysis:**
```bash
# Operations in last 7 days
WEEK_AGO=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
jq --arg date "$WEEK_AGO" \
  '.entries[] | select(.timestamp >= $date)' \
  .claude/todo-log.json
```

---

## Emergency Recovery Procedures

### Complete System Corruption

**If all validation fails and backups are corrupted:**

**Step 1: Save what you can**
```bash
# Create emergency backup
mkdir -p ~/todo-emergency-backup
cp -r .claude ~/todo-emergency-backup/
```

**Step 2: Reinitialize system**
```bash
# Move corrupted directory
mv .claude .claude.corrupted

# Reinitialize
~/.claude-todo/scripts/init.sh
```

**Step 3: Manually extract and recreate tasks**
```bash
# Try to extract task data from corrupted files
jq -r '.tasks[] | .title' .claude.corrupted/todo.json 2>/dev/null > /tmp/task-titles.txt

# Recreate each task
while IFS= read -r title; do
  ~/.claude-todo/scripts/add-task.sh "$title"
done < /tmp/task-titles.txt
```

**Step 4: Verify new system**
```bash
~/.claude-todo/scripts/validate.sh
~/.claude-todo/scripts/list-tasks.sh
```

---

## Getting Help

### Collect diagnostic information:
```bash
# System info
echo "OS: $(uname -a)"
echo "Shell: $SHELL"
echo "jq version: $(jq --version)"

# Installation status
ls -la ~/.claude-todo/

# File status
~/.claude-todo/scripts/validate.sh --verbose

# Recent errors
tail -50 .claude/todo-log.json | jq '.entries[] | select(.details.error != null)'
```

### Report issues:
Include the diagnostic output above when reporting issues to help troubleshoot faster.

---

## Prevention Best Practices

1. **Always use provided scripts** - Don't manually edit JSON files unless necessary
2. **Validate regularly** - Run `validate.sh` weekly or after manual edits
3. **Monitor backups** - Check backup directory has recent files
4. **Archive periodically** - Keep active task list under 200 tasks
5. **Check permissions** - Ensure files are readable/writable
6. **Use version control** - Git commit after major task milestones (optional)
7. **Test changes** - Use `validate.sh` after configuration changes

---

## Quick Reference

| Issue | Quick Fix |
|-------|-----------|
| Permission denied | `chmod 644 .claude/todo.json` |
| Invalid JSON | `jq . .claude/todo.json` to validate |
| Duplicate IDs | Regenerate with timestamp + random |
| Missing field | Add required field manually |
| Script not found | Use full path: `~/.claude-todo/scripts/...` |
| Slow performance | Archive old completed tasks |
| Corrupted file | Restore from `.claude/.backups/` |
| No backups | Check `.backups/` directory exists |

---

**Last Updated:** 2025-12-05
