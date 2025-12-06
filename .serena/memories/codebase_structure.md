# Codebase Structure

## Directory Organization

```
claude-todo/
│
├── Root Files (Documentation & Build)
│   ├── README.md                 # User-facing documentation
│   ├── ARCHITECTURE.md           # System architecture (THIS IS KEY)
│   ├── DATA-FLOW-DIAGRAMS.md    # Visual data flows
│   ├── LICENSE                   # MIT License
│   ├── .gitignore               # Exclude user data files
│   ├── install.sh               # Global installation script
│   └── CHANGELOG.md             # Version history (future)
│
├── schemas/                      # JSON Schema Definitions
│   ├── todo.schema.json         # Main task list schema
│   ├── archive.schema.json # Archive schema
│   ├── config.schema.json  # Configuration schema
│   └── log.schema.json     # Change log schema
│
├── templates/                    # Starter Templates
│   ├── todo.template.json       # Empty task list with examples
│   ├── config.template.json # Default configuration
│   └── archive.template.json # Empty archive
│
├── scripts/                      # User-Facing Scripts
│   ├── init.sh                  # Initialize project
│   ├── add-task.sh              # Add new task
│   ├── complete-task.sh         # Mark task complete
│   ├── archive.sh               # Archive completed tasks
│   ├── list-tasks.sh            # Display tasks
│   ├── stats.sh                 # Statistics and reporting
│   ├── validate.sh              # Validate all files
│   ├── backup.sh                # Backup tasks
│   ├── restore.sh               # Restore from backup
│   └── health-check.sh          # System health check
│
├── lib/                          # Shared Library Functions
│   ├── validation.sh            # Schema validation functions
│   ├── logging.sh               # Change log functions
│   └── file-ops.sh              # Atomic file operations
│
├── docs/                         # Detailed Documentation
│   ├── installation.md          # Installation guide
│   ├── usage.md                 # Usage examples
│   ├── configuration.md         # Configuration reference
│   ├── schema-reference.md      # Schema documentation
│   └── troubleshooting.md       # Common issues and solutions
│
└── tests/                        # Test Suite
    ├── run-all-tests.sh         # Test runner
    ├── test-validation.sh       # Schema validation tests
    ├── test-archive.sh          # Archive operation tests
    ├── test-add-task.sh         # Task creation tests
    ├── test-complete-task.sh    # Task completion tests
    └── fixtures/                # Test Data
        ├── valid-todo.json
        ├── invalid-todo.json
        ├── duplicate-ids.json
        └── large-dataset.json
```

## Per-Project Files (NOT in Repository)

These are created in each project's `.claude/` directory by `init.sh`:

```
your-project/.claude/
├── todo.json              # Current active tasks
├── todo-archive.json      # Completed/cancelled tasks
├── todo-config.json       # Project-specific configuration
├── todo-log.json          # Change history log
└── .backups/              # Automatic backups
    ├── todo.json.1        # Most recent backup
    ├── todo.json.2
    ├── ...
    └── todo.json.10       # Oldest backup (configurable)
```

## Global Installation (~/.claude-todo/)

After running `install.sh`, this structure exists:

```
~/.claude-todo/
├── schemas/               # Copied from repo
├── templates/             # Copied from repo
├── scripts/               # Copied from repo (executable)
├── lib/                   # Copied from repo
└── config.json           # Optional global configuration
```

## File Responsibilities

### Schema Files (schemas/)
**Purpose**: Define structure and validation rules for all JSON files

- **todo.schema.json**: 
  - Validates task structure
  - Enforces status enum
  - Requires content/activeForm pairing
  
- **archive.schema.json**: 
  - Same as todo.schema.json but for archived tasks
  - Additional archive-specific metadata
  
- **config.schema.json**: 
  - Configuration options validation
  - Default value definitions
  - Type constraints
  
- **log.schema.json**: 
  - Log entry structure
  - Operation type validation
  - Timestamp requirements

### Template Files (templates/)
**Purpose**: Provide starter files for new projects

- **todo.template.json**: Empty todos array with example tasks (commented out)
- **config.template.json**: All configuration options with sensible defaults
- **archive.template.json**: Empty archive with structure

### Script Files (scripts/)
**Purpose**: User-facing operations

#### Core Operations
- **init.sh**: Set up .claude/ directory, copy templates, create backups dir
- **add-task.sh**: Create new task with validation
- **complete-task.sh**: Update task status, trigger archive if configured
- **archive.sh**: Move completed tasks to archive based on policy

#### Query Operations
- **list-tasks.sh**: Display tasks with filtering and formatting options
- **stats.sh**: Generate statistics and reports

#### Maintenance Operations
- **validate.sh**: Run all validation checks, optionally fix issues
- **backup.sh**: Create manual backup
- **restore.sh**: Restore from backup
- **health-check.sh**: Verify system integrity

### Library Files (lib/)
**Purpose**: Shared functions used by multiple scripts

- **validation.sh**:
  - `validate_schema()`: JSON Schema validation
  - `validate_anti_hallucination()`: Semantic checks
  - `validate_task_object()`: Single task validation
  - `check_duplicate_ids()`: Cross-file ID uniqueness
  
- **logging.sh**:
  - `log_operation()`: Append to todo-log.json
  - `create_log_entry()`: Generate log entry object
  - `rotate_log()`: Manage log file size
  
- **file-ops.sh**:
  - `atomic_write()`: Safe file writing with temp files
  - `backup_file()`: Create versioned backup
  - `rotate_backups()`: Manage backup retention
  - `restore_backup()`: Restore from backup file

**Note**: Configuration management (lib/config.sh) is NOT YET IMPLEMENTED. Scripts currently use hardcoded defaults and direct JSON parsing.

### Documentation Files (docs/)
**Purpose**: Comprehensive user and developer documentation

- **installation.md**: Step-by-step installation instructions
- **usage.md**: Examples for all common operations
- **configuration.md**: All config options explained
- **schema-reference.md**: Schema structure and validation rules
- **troubleshooting.md**: Common errors and solutions

### Test Files (tests/)
**Purpose**: Automated testing and validation

- **run-all-tests.sh**: Execute full test suite
- **test-*.sh**: Individual test suites for each component
- **fixtures/**: Known-good and known-bad test data

## Data Flow Through Structure

### Task Creation Flow
```
User → scripts/add-task.sh 
     → lib/validation.sh (validate input)
     → lib/file-ops.sh (atomic write)
     → lib/logging.sh (log operation)
     → .claude/todo.json (updated)
     → .claude/todo-log.json (appended)
     → .claude/.backups/todo.json.N (backup created)
```

### Validation Flow
```
User → scripts/validate.sh
     → schemas/*.schema.json (load schemas)
     → lib/validation.sh (validate against schemas)
     → lib/validation.sh (anti-hallucination checks)
     → .claude/todo*.json (all data files checked)
     → Report to user
```

### Archive Flow
```
User OR Auto-trigger → scripts/archive.sh
                     → lib/validation.sh (validate tasks)
                     → lib/file-ops.sh (atomic multi-file update)
                     → lib/logging.sh (log archive operation)
                     → .claude/todo.json (tasks removed)
                     → .claude/todo-archive.json (tasks added)
                     → .claude/.backups/ (both files backed up)
```

**Note**: Config loading currently done directly in scripts, not via lib/config.sh (not implemented).

## Import/Dependency Graph

### scripts/ dependencies
```
All scripts:
├── lib/validation.sh (validation functions)
├── lib/logging.sh (logging functions)
└── lib/file-ops.sh (file operations)

add-task.sh:
├── lib/validation.sh (validate new task)
├── lib/file-ops.sh (atomic write)
└── lib/logging.sh (log creation)

archive.sh:
├── lib/validation.sh (validate tasks)
├── lib/file-ops.sh (multi-file atomic update)
└── lib/logging.sh (log archive)
```

**Note**: lib/config.sh is referenced in architecture docs but NOT YET IMPLEMENTED. Configuration currently handled in scripts directly.

### lib/ dependencies
```
validation.sh:
├── schemas/*.schema.json (validation rules)
└── External: jq, ajv/jsonschema (JSON processing)

file-ops.sh:
├── lib/validation.sh (validate before commit)
└── External: mv, cp (atomic operations)

logging.sh:
├── lib/file-ops.sh (atomic log append)
└── schemas/log.schema.json (log validation)
```

**Note**: lib/config.sh dependencies listed in architecture docs but file NOT YET IMPLEMENTED.

## Key Architecture Files

The most important files for understanding the system:

1. **ARCHITECTURE.md** - Complete system design and rationale
2. **DATA-FLOW-DIAGRAMS.md** - Visual representation of all flows
3. **schemas/todo.schema.json** - Core data structure definition
4. **lib/validation.sh** - Anti-hallucination implementation
5. **lib/file-ops.sh** - Atomic operation implementation

## Naming Conventions

### Files
- Scripts: `kebab-case.sh` (verb-noun pattern)
- Libraries: `noun.sh` (domain-based)
- Schemas: `filename.schema.json` (explicit schema suffix)
- Templates: `filename.template.json` (explicit template suffix)
- Data files: `todo-*.json` (todo prefix for all task data)

### Functions
- Public API: `verb_noun()` (e.g., `validate_schema`)
- Private/helper: `_verb_noun()` (underscore prefix)
- Boolean: `is_valid()`, `has_tasks()` (predicate pattern)
