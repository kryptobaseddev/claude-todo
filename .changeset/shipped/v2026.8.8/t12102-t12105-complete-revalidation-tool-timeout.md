---
id: t12102-t12105-complete-revalidation-tool-timeout
tasks: [T12102, T12105]
kind: fix
summary: "cleo complete caches commit-atom re-validation, emits stderr progress, and is idempotent on done tasks; CLEO_TOOL_TIMEOUT_<TOOL> makes the tool: evidence deadline configurable"
---

gh#1196: profiling showed evidence re-validation is ~60ms of a multi-second complete (bootstrap, hooks, and worktree tails dominate), but complete still re-ran immutable git checks and, worse, reported a timeout for operations that had already succeeded server-side. Commit-atom re-validation is now cached keyed on (commitSha, headSha) under `.cleo/cache/evidence/` (successes only); per-atom progress goes to stderr; and completing an already-done task exits 0 with `alreadyDone: true` so post-timeout recovery is just "run it again". `files:`/`test-run:` re-validation is deliberately NOT cached — the sha256 re-read is the E_EVIDENCE_STALE guarantee. gh#1193: the fixed ~300s `tool:` spawn deadline is now `CLEO_TOOL_TIMEOUT_<TOOL>` (same convention as the concurrency var), documented in CLEO-INJECTION.md.
