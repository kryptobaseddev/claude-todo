---
id: t12087-vitest-memory-safe-ssot
tasks: [T12087]
kind: fix
summary: the vitest OOM guard was both misplaced AND dead since Vitest 4 — bounds now live in one SSoT every config spreads, enforced by gate 8
---

`pool: 'forks'` at vitest's default `maxWorkers` (CPU-1) spawns ~23 forks on a 24-core box, each loading the `@cleocode/core` graph (~2.7 GB). ~62 GB → kernel OOM → the machine freezes and the session dies. It happened twice on 2026-08-06.

**Defect A — the guard was only on the path nobody types.** T11839 fixed this in the ROOT `vitest.config.ts` and relied on `test.extends: true` to propagate. That covers `pnpm run test`, but not `vitest run --root packages/core` or `pnpm run test:pkg <name>` — that package IS the root, so there is nothing to extend. Measured: **0 of 19** per-package configs declared `maxWorkers` or a heap cap.

**Defect B — and the heap cap was a no-op anyway.** Vitest 4 **removed** `test.poolOptions` ("All previous poolOptions are now top-level options") and ignores the old shape with only a stderr deprecation. T11839 wrote `poolOptions.forks.execArgv`, so from the Vitest 4 upgrade onward the fork COUNT was still bounded (`maxWorkers` is top-level) while the per-fork V8 ceiling silently evaporated — which is why the machine kept freezing behind a fix that read as present in the config. **A silently-ignored config option is worse than a missing one: it passes review and is absent at runtime.**

Bounds now live in `vitest.memory-safe.ts` as an SSoT that all 20 configs import and spread **directly** — no inheritance, no dependence on which directory vitest considers the root — in the correct Vitest 4 shape (top-level `execArgv`). Verified three ways: every resolved config reports `pool=forks maxWorkers=6 execArgv=["--max-old-space-size=4096"]`, live forks carry the flag, and the deprecation warning is gone. 6 forks × 4 GB = a 24 GB ceiling on a 24-core/62 GB box; 1 fork on a 2-core CI runner.

**New gate 8** (`cleo check arch`), zero-tolerance with no baseline: rejects a missing spread, a post-spread `maxWorkers`/`execArgv` override, a `pool` switched away from `forks` (per-worker V8 flags do not apply to worker_threads), and any `poolOptions:` usage at all. Verified against both a `maxWorkers: 23` and a reintroduced `poolOptions` regression.

An unbounded fork pool is a machine-freezing default that only ever bites locally — CI runners have 2-4 cores, so it passes there and takes down the developer instead.
