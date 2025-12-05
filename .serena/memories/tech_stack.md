# Technology Stack

## Core Technologies

### Shell Scripting (Bash)
- **Primary Language**: All operational scripts written in Bash
- **Version**: Bash 4.0+ (for modern features like associative arrays)
- **Platform**: Linux/Unix/macOS compatible

### JSON Schema
- **Validation**: JSON Schema Draft-07 for all data files
- **Validators**: 
  - ajv (Node.js-based, preferred if available)
  - jsonschema (Python-based, fallback)
  - jq with manual schema validation (universal fallback)

### JSON Processing
- **Primary Tool**: jq (JSON query processor)
- **Usage**: Parsing, filtering, transforming JSON data
- **Version**: jq 1.5+

### File System
- **Data Storage**: Local JSON files in .claude/ directory
- **Backups**: Automatic versioned backups in .claude/.backups/
- **Atomicity**: OS-level atomic rename operations

## Dependencies

### Required
- bash (4.0+)
- jq (JSON processor)
- One JSON Schema validator (ajv OR jsonschema OR manual with jq)

### Optional
- git (for version control integration)
- cron (for automatic archival scheduling)
- dialog/whiptail (for interactive TUI interfaces)

## File Formats

### Data Files
- **Format**: JSON (RFC 8259)
- **Encoding**: UTF-8
- **Schema**: JSON Schema Draft-07
- **Validation**: Schema + semantic anti-hallucination checks

### Schema Files
- **todo.schema.json**: Main task list validation
- **todo-archive.schema.json**: Archive validation
- **todo-config.schema.json**: Configuration validation
- **todo-log.schema.json**: Change log validation

## Architecture Patterns

### Data Integrity
- **Atomic Writes**: Temp file → validate → rename pattern
- **Backup Before Modify**: Always backup before write operations
- **Validation Gates**: Schema + semantic checks before commit
- **Rollback on Error**: Restore from backup on failure

### Script Organization
- **Library Functions**: Shared code in lib/ directory
- **Operational Scripts**: User-facing scripts in scripts/ directory
- **Template Files**: Starter templates in templates/ directory
- **Schema Definitions**: Validation schemas in schemas/ directory
