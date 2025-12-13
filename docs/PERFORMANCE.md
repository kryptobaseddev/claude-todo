# Performance Characteristics

## Performance Targets

The claude-todo system is optimized for datasets up to 10,000 tasks:

- **list command**: < 100ms for 1000+ tasks (JSON format)
- **stats command**: < 1s for 1000+ tasks
- **add/update/complete**: < 50ms for any dataset size
- **cache operations**: O(1) lookups for labels and phases

## Benchmark Results

### List Command (1000 tasks)

| Format | Time | Status |
|--------|------|--------|
| JSON | ~70ms | ✅ PASS |
| JSONL | ~75ms | ✅ PASS |
| Text (default) | ~130ms | ⚠️ Above target |
| Markdown | ~140ms | ⚠️ Above target |
| Table | ~145ms | ⚠️ Above target |

**Note**: Text-based formats (text, markdown, table) include rendering overhead for colors, Unicode symbols, and formatting. For programmatic use or performance-critical scenarios, use JSON/JSONL formats.

### Stats Command (1000 tasks)

| Operation | Time | Status |
|-----------|------|--------|
| Full statistics | ~150ms | ✅ PASS |
| With archive | ~180ms | ✅ PASS |

### Cache Performance

| Operation | Complexity | Typical Time |
|-----------|-----------|--------------|
| Label lookup | O(1) | < 1ms |
| Phase lookup | O(1) | < 1ms |
| Cache rebuild | O(n) | ~50ms for 1000 tasks |
| Staleness check | O(1) | < 1ms |

## Optimization Strategies

### For Large Datasets (1000+ tasks)

1. **Use JSON format for programmatic access**:
   ```bash
   claude-todo list -f json | jq '.tasks[] | select(.status == "pending")'
   ```

2. **Apply filters early** (reduces dataset before rendering):
   ```bash
   claude-todo list -s pending -p high  # Filters before formatting
   ```

3. **Use pagination** for text output:
   ```bash
   claude-todo list --limit 50                # First 50 tasks
   claude-todo list --limit 50 --offset 50    # Next 50 tasks
   ```

4. **Leverage cache for label/phase queries**:
   ```bash
   claude-todo labels show bug    # O(1) lookup via cache
   claude-todo phases show core   # O(1) lookup via cache
   ```

### Performance Tips

#### Fastest Operations
- **Label filtering**: Uses O(1) cache lookups when available
- **Phase filtering**: Uses O(1) cache lookups when available
- **JSON output**: Minimal formatting overhead
- **Status filtering**: Early filtering in jq reduces memory usage

#### Slower Operations
- **Text rendering**: Unicode, colors, and multi-line formatting adds overhead
- **Archive inclusion**: Doubles dataset size
- **Verbose mode**: Includes notes, files, and acceptance criteria
- **Sorting by title**: Requires string comparison vs. enum sorting

## Implementation Details

### Early Filtering

The list command applies filters during JSON parsing rather than after loading all tasks into memory:

```bash
# Bad: Load all tasks, then filter
all_tasks=$(jq '.tasks[]' todo.json)
filtered=$(echo "$all_tasks" | jq 'select(.status == "pending")')

# Good: Filter during load (current implementation)
filtered=$(jq '.tasks[] | select(.status == "pending")' todo.json)
```

### Single-Pass jq Operations

Multiple jq operations are combined into single invocations:

```bash
# Bad: Multiple jq calls
tasks=$(echo "$tasks" | jq 'map(.)')
tasks=$(echo "$tasks" | jq 'sort_by(.priority)')
tasks=$(echo "$tasks" | jq '.[:50]')

# Good: Single jq call (current implementation)
tasks=$(echo "$tasks" | jq 'map(.) | sort_by(.priority) | .[:50]')
```

### Cache Architecture

The cache system (`lib/cache.sh`) provides:

- **In-memory hash maps**: Bash associative arrays for O(1) lookups
- **File-based persistence**: `.claude/.cache/` directory with JSON indices
- **Checksum validation**: SHA256-based staleness detection
- **Lazy regeneration**: Rebuild only when todo.json changes

```bash
# Cache structure
.claude/.cache/
├── labels.index.json      # {"bug": ["T001", "T005"], ...}
├── phases.index.json      # {"core": ["T002", "T003"], ...}
├── checksum.txt           # SHA256 of todo.json
└── metadata.json          # Cache metadata
```

## Scaling Limits

### Tested Configurations

| Task Count | list (JSON) | list (text) | stats | Notes |
|-----------|-------------|-------------|-------|-------|
| 100 | 30ms | 60ms | 50ms | Excellent |
| 500 | 50ms | 90ms | 80ms | Very good |
| 1,000 | 70ms | 130ms | 150ms | Good |
| 2,000 | 120ms | 250ms | 280ms | Acceptable |
| 5,000 | 280ms | 600ms | 650ms | Use pagination |

### Recommended Practices

**For > 1,000 tasks**:
- Use JSON format for listing
- Apply filters (status, priority, labels)
- Use pagination (--limit/--offset)
- Leverage cache for label/phase queries

**For > 5,000 tasks**:
- Consider archiving completed tasks regularly
- Use focused filters (avoid listing all tasks)
- Batch operations via scripts
- Monitor cache performance

**For > 10,000 tasks**:
- Archive aggressively (keep active tasks < 2,000)
- Use label-based filtering exclusively
- Consider splitting into multiple projects
- Implement custom indexing if needed

## Profiling Tools

### Built-in Execution Metrics

The list command includes execution time in JSON metadata:

```bash
claude-todo list -f json | jq '._meta.execution_ms'
# Output: 75 (milliseconds)
```

### Benchmark Script

Run comprehensive performance tests:

```bash
./scripts/benchmark-performance.sh --sizes "100 500 1000 2000"
./scripts/benchmark-performance.sh --runs 5 --output benchmark.txt
```

### Manual Profiling

```bash
# Time a specific operation
time claude-todo list -s pending -f json > /dev/null

# Profile jq operations
time jq '.tasks[] | select(.status == "pending")' .claude/todo.json > /dev/null

# Check cache effectiveness
claude-todo labels  # Should be instant if cache valid
```

## Future Optimizations

### Potential Improvements

1. **Streaming JSON parsing**: Use `jq --stream` for very large files
2. **Binary indices**: Replace JSON cache files with binary format
3. **Incremental updates**: Update cache without full rebuild
4. **Parallel processing**: Use GNU parallel for batch operations
5. **SQLite backend**: Optional database backend for > 10k tasks

### Known Limitations

- **jq memory usage**: Linear with dataset size (acceptable up to 10k tasks)
- **Bash string operations**: Not optimized for massive datasets
- **File I/O**: Sequential reads (could benefit from mmap for large files)
- **Text rendering**: Subshell overhead for color/symbol functions

## Performance History

### v0.8.2 (2025-12-13)
- ✅ Added early filtering to reduce memory footprint
- ✅ Combined multiple jq operations into single pass
- ✅ Implemented pagination (--offset/--limit)
- ✅ Cache system for O(1) label/phase lookups
- 📊 list (JSON): 70ms for 1000 tasks
- 📊 stats: 150ms for 1000 tasks

### Baseline (v0.6.0)
- 📊 list (JSON): 132ms for 1000 tasks
- 📊 stats: 147ms for 1000 tasks
- ⚠️ No pagination support
- ⚠️ Filters applied after full load

**Performance Improvement**: ~47% faster for list command with JSON format
