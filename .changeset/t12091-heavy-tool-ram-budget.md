---
id: t12091-heavy-tool-ram-budget
tasks: [T12091]
kind: fix
summary: two independently-bounded concurrency caps composed to 144 GiB of permitted heap on a 62 GiB machine — heavy tool budgets are now derived from RAM, not core count
---

`cleo` runs a project's own test command to satisfy `tool:test` evidence. Two separate caps governed that, and both were core-derived:

- `defaultMaxConcurrent('test', cpus)` = `floor(cpus/4)` → **6** concurrent full suites on a 24-core box
- `computeClassBudget('test-run')` = `max(1, floor(cpus/4))` → the same 6

Each of those runs is itself permitted 6 vitest forks × a 4 GiB heap cap by `vitest.memory-safe.ts` (T12087). Multiplied out: **6 × 6 × 4 = 144 GiB on 62 GiB of RAM.** No single bound was ever violated, which is exactly why the machine froze with every guard reporting healthy.

The dimensional error is the root cause: what limits a test run is memory, and core count says nothing about memory — a 24-core/16 GiB VM was handed the same 6 slots as a 24-core/256 GiB server. Both sites now divide available RAM by the worst-case per-run footprint and take the lower of that and the core budget. `agent-session` in the governor had this shape correct already; `test-run` did not.

Reactive PSI scaling is not a substitute and is kept only as a second line: `some avg10` is a ten-second average, and a fork fleet exhausts RAM faster than that window can report it.
