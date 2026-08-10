---
id: t12096-heavy-tool-spawn-ceiling
tasks: [T12096]
kind: fix
summary: one tool:test atom could fan out to 15 unbounded vitest pools in a consuming project — CLEO now sets a hard memory ceiling at the spawn point
---

T12091 bounded how many `tool:test` INVOCATIONS run at once, but it counts an entire process tree as one slot. In a workspace that is not one test run. Measured in /mnt/projects/PepsVida:

    cleo verify T1046 --gate testsPassed --evidence tool:test
      └─ npm test → pnpm -r --if-present run test
          └─ concurrent vitest across {apps,lib}/*   (15 packages have test scripts)

CLEO's semaphore saw ONE slot. The project has no vitest config capping workers or heap — the memory-safe SSoT and its gate live in cleocode and protect only cleocode. A single evidence atom could therefore expand to 15 concurrent unbounded fork pools.

A consuming project cannot be relied on to bound its own runner, and CLEO is the process that starts it, so the ceiling belongs at the spawn point. Three levers, each verified against the installed tool rather than assumed: NODE_OPTIONS=--max-old-space-size (appended, never clobbering), VITEST_MAX_WORKERS (read out of vitest 4.1.4's dist — it OVERRIDES the resolved config, so it binds projects that set their own), and npm_config_workspace_concurrency (confirmed via `pnpm config get`). Applied to test/build only; any value the project set deliberately is preserved.

Worst case on a 62 GiB box goes from unbounded × unbounded × unbounded to 1 package × 6 workers × 4 GiB = 24 GiB.
