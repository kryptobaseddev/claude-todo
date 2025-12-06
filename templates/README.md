# Template Files

Template files used by `init.sh` to initialize new projects.

## Placeholder Contract

Templates use placeholders that are replaced during initialization:

| Placeholder | Replaced With | Example |
|-------------|---------------|---------|
| `{{PROJECT_NAME}}` | Directory name or CLI argument | `my-project` |
| `{{TIMESTAMP}}` | Current ISO 8601 timestamp | `2025-12-06T10:00:00Z` |
| `{{CHECKSUM}}` | SHA-256 hash of tasks array (first 16 chars) | `a1b2c3d4e5f6g7h8` |

## Template Files

| File | Description |
|------|-------------|
| `todo.template.json` | Active tasks storage with focus management |
| `archive.template.json` | Completed tasks archive (immutable after archival) |
| `log.template.json` | Append-only change log |
| `config.template.json` | Project configuration |
| `CLAUDE.todo.md` | CLAUDE.md section for claude-todo integration |

## Placeholder Processing

During `init.sh`:

```bash
# 1. Read template
template=$(cat todo.template.json)

# 2. Replace placeholders
template=${template//\{\{PROJECT_NAME\}\}/$project_name}
template=${template//\{\{TIMESTAMP\}\}/$(date -u +%Y-%m-%dT%H:%M:%SZ)}
template=${template//\{\{CHECKSUM\}\}/$(echo -n '[]' | sha256sum | cut -c1-16)}

# 3. Write to .claude/todo.json
echo "$template" > .claude/todo.json
```

## Adding New Templates

1. Create file with `.template.json` extension
2. Use `{{PLACEHOLDER}}` syntax for dynamic values
3. Add placeholder to processing in `scripts/init.sh`
4. Document placeholder in this file

## Validation

Templates must validate against their respective schemas after placeholder replacement.
