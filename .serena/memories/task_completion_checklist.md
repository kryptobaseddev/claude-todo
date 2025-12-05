# Task Completion Checklist

When completing any development task in the claude-todo project, follow this systematic checklist:

## 1. Code Quality

### Bash Scripts
- [ ] Set proper shebang: `#!/usr/bin/env bash`
- [ ] Enable strict mode: `set -euo pipefail`
- [ ] Set safe IFS: `IFS=$'\n\t'`
- [ ] All functions documented with comments
- [ ] Error handling for all operations
- [ ] Input validation for all parameters
- [ ] Proper quoting of variables: `"$var"` not `$var`
- [ ] Use `readonly` for constants
- [ ] Local variables declared with `local`

### JSON Files
- [ ] Valid JSON syntax (no trailing commas)
- [ ] Proper UTF-8 encoding
- [ ] Consistent indentation (2 spaces)
- [ ] ISO 8601 timestamps
- [ ] Schema reference included (`$schema` field)

## 2. Validation

### Schema Validation
- [ ] JSON Schema file exists in schemas/
- [ ] Schema version documented
- [ ] All required fields specified
- [ ] Enum constraints defined where applicable
- [ ] Type constraints correct

### Anti-Hallucination Checks
- [ ] ID uniqueness verified
- [ ] Status enum validation implemented
- [ ] Timestamp sanity checks added
- [ ] Content/activeForm pairing enforced
- [ ] Duplicate content detection active

### Testing
- [ ] Unit tests written for new functions
- [ ] Integration tests for workflows
- [ ] Edge cases covered
- [ ] Test fixtures created/updated
- [ ] All tests passing: `./tests/run-all-tests.sh`

## 3. Documentation

### Code Documentation
- [ ] Function comments include purpose, args, returns
- [ ] Complex logic explained with inline comments
- [ ] Script usage documented in header
- [ ] Example usage provided

### User Documentation
- [ ] README.md updated if behavior changes
- [ ] docs/usage.md updated for new features
- [ ] docs/configuration.md updated for new config options
- [ ] ARCHITECTURE.md updated for structural changes

### Schema Documentation
- [ ] docs/schema-reference.md updated
- [ ] Schema changes documented with migration notes
- [ ] Breaking changes highlighted

## 4. Data Integrity

### Atomic Operations
- [ ] Temp file pattern used for writes
- [ ] Validation before commit
- [ ] Backup created before modification
- [ ] Atomic rename operation
- [ ] Rollback on failure implemented

### File Operations
- [ ] Proper file permissions set (644 for data, 755 for scripts)
- [ ] Directory creation checked/handled
- [ ] Concurrent access considered
- [ ] Lock files used if needed

## 5. Configuration

### Default Values
- [ ] Sensible defaults provided
- [ ] Defaults documented in code
- [ ] Template files include all options
- [ ] Config schema updated

### Override Hierarchy
- [ ] Respects override order: defaults → global → project → env → CLI
- [ ] Environment variables documented
- [ ] CLI flags added to help text

## 6. Error Handling

### Error Detection
- [ ] All error conditions checked
- [ ] Meaningful error messages
- [ ] Error output to stderr
- [ ] Proper exit codes (0=success, 1+=error)

### Recovery
- [ ] Backup restoration on failure
- [ ] Cleanup of temp files on error
- [ ] User-friendly error messages with fix suggestions
- [ ] Log entry for errors

## 7. Logging

### Operation Logging
- [ ] All state changes logged to todo-log.json
- [ ] Log entries include timestamp
- [ ] Operation type recorded
- [ ] Before/after state captured
- [ ] Log schema validated

### Debug Logging
- [ ] Debug messages available (controlled by log level)
- [ ] Verbose mode supported
- [ ] Log rotation considered

## 8. Performance

### Efficiency
- [ ] jq used for JSON processing (not bash loops)
- [ ] Files read once per operation
- [ ] No unnecessary validations
- [ ] Batch operations where possible

### Resource Management
- [ ] Large file handling considered
- [ ] Memory usage reasonable
- [ ] Temp file cleanup guaranteed

## 9. Security

### Input Sanitization
- [ ] Command injection prevented
- [ ] Special characters escaped
- [ ] Path traversal prevented
- [ ] Input length limits enforced

### File Security
- [ ] Proper file permissions
- [ ] No sensitive data exposure
- [ ] Secure temp file creation
- [ ] Backup files protected

## 10. Integration

### Compatibility
- [ ] Works on Linux
- [ ] Works on macOS (if applicable)
- [ ] Bash 4.0+ features only
- [ ] Dependencies documented

### Git Integration
- [ ] .gitignore updated appropriately
- [ ] Only system files committed (not user data)
- [ ] Commit messages follow convention

## 11. Installation & Upgrade

### Installation
- [ ] install.sh handles new files
- [ ] Permissions set correctly
- [ ] Dependencies checked
- [ ] Installation validated

### Upgrade Path
- [ ] Migration script created (if needed)
- [ ] Backward compatibility maintained
- [ ] Version bump documented
- [ ] Breaking changes documented

## 12. Final Checks

### Manual Testing
- [ ] Manually test happy path
- [ ] Test error conditions
- [ ] Test with invalid inputs
- [ ] Test recovery procedures

### Code Review Checklist
- [ ] Code follows style guide
- [ ] No hardcoded paths (use variables)
- [ ] No debug statements left in code
- [ ] All TODOs resolved or documented

### Before Commit
- [ ] All tests passing
- [ ] All validation passing
- [ ] Documentation complete
- [ ] ARCHITECTURE.md reflects current design
- [ ] CHANGELOG updated (if applicable)

## Automation

This checklist can be partially automated:

```bash
# Run before commit
./scripts/pre-commit-check.sh

# Which runs:
# 1. ./tests/run-all-tests.sh
# 2. ./scripts/validate.sh --all
# 3. shellcheck scripts/*.sh lib/*.sh
# 4. Check documentation completeness
# 5. Verify git status (no uncommitted changes to user data files)
```
