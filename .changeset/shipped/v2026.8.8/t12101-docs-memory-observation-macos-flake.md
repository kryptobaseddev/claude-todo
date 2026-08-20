---
id: t12101-docs-memory-observation-macos-flake
tasks: [T12101]
kind: fix
summary: "T9976 docs-memory-observation macOS CI flake fixed: FTS5 init is keyed by DB handle identity (not a process-wide boolean), and test teardown drains fire-and-forget brain writes before rmdir"
---

Three consecutive PRs failed macOS shard 1 identically. Root cause had two halves: (1) a process-wide `_fts5Initialized` boolean meant vitest retries (same process, fresh temp DB) skipped the FTS rebuild, so `memory.find` deterministically missed the observation on attempts 2-3 — also a real production bug for any multi-project process searching project B after project A; the flag is now keyed by handle identity. (2) The test's `rmSync` raced fire-and-forget observation/retrieval tails still writing `.cleo/cleo.db`; teardown now drains pending writes, closes handles, and retries the removal only on ENOTEMPTY/EBUSY/EPERM.
