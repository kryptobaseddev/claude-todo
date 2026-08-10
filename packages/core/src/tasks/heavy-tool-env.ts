/**
 * Hard memory ceiling injected into every heavy tool CLEO spawns (T12096).
 *
 * ## Why a cap at the spawn point, and not just a semaphore
 *
 * T12091 bounded how many `tool:test` INVOCATIONS run at once. It counts an
 * entire process tree as one slot — and in a workspace, one invocation is not
 * one test run. Measured 2026-08-09 in `/mnt/projects/PepsVida`:
 *
 *     cleo verify T1046 --gate testsPassed --evidence tool:test
 *       └─ npm test
 *           └─ pnpm -r --if-present run test     ← fans out
 *               └─ concurrent vitest in {apps,lib}/*   (15 packages have tests)
 *
 * CLEO's semaphore saw ONE slot in use. The project has 15 packages with a
 * `test` script and **none of its three vitest configs cap `maxWorkers` or
 * heap** — the memory-safe SSoT and its lint gate live in cleocode and protect
 * only cleocode. So a single evidence atom could expand to 15 concurrent
 * unbounded fork pools on a 62 GiB machine.
 *
 * A consuming project cannot be relied on to configure this. CLEO is the one
 * spawning the process, so CLEO sets the ceiling — and the child inherits it
 * whether or not the project has ever heard of `vitest.memory-safe.ts`.
 *
 * ## The three levers (each verified against the installed tool, not assumed)
 *
 * | Variable | Effect | Verified by |
 * |---|---|---|
 * | `NODE_OPTIONS=--max-old-space-size=N` | Heap ceiling for EVERY node process in the tree, inherited | node docs; appended, never clobbered |
 * | `VITEST_MAX_WORKERS=N` | `if (process.env.VITEST_MAX_WORKERS) resolved.maxWorkers = parseInt(...)` — overrides the resolved config, so it binds projects that set their own | read out of vitest 4.1.4 `dist/chunks/coverage.*.js` |
 * | `npm_config_workspace_concurrency=N` | Bounds `pnpm -r` fan-out across workspace packages | `npm_config_workspace_concurrency=1 pnpm config get workspace-concurrency` → `1` |
 *
 * Together these bound the product the semaphore could not see:
 * `packages in flight × workers per run × heap per worker`.
 *
 * Applied ONLY to `test` / `build`. Capping `lint` or `typecheck` would
 * serialise cheap single-process work for no benefit.
 *
 * A project that genuinely wants more can set any of these itself — an existing
 * value is always respected, because a deliberate setting beats our default.
 *
 * @task T12096
 */

import { totalmem } from 'node:os';
import type { CanonicalTool } from './tool-resolver.js';

/**
 * Heap ceiling per node process, in MiB.
 *
 * Matches `FORK_HEAP_MB` in `vitest.memory-safe.ts`. A worker that needs more
 * than 4 GiB of JS heap for a unit test has a leak, and the whole point is to
 * make that fail loudly in one worker rather than take the machine down.
 */
export const HEAVY_TOOL_HEAP_MB = 4096;

/** RAM assumed consumable per concurrent worker, in GiB, when sizing the pool. */
export const GIB_PER_WORKER = 6;

/** Never grant more than this many workers, however large the machine. */
export const MAX_HEAVY_WORKERS = 6;

/** Never grant fewer than this many — one worker must always be able to run. */
export const MIN_HEAVY_WORKERS = 1;

/**
 * Workspace packages allowed to run their test/build script concurrently.
 *
 * Deliberately 1. The fan-out is the multiplier the semaphore was blind to, and
 * a serialised workspace sweep is slower but finishes; a parallel one on a
 * memory-bound box does not finish at all.
 */
export const WORKSPACE_CONCURRENCY = 1;

/** Environment overlay to merge into a heavy tool's spawn env. */
export type HeavyToolEnv = Readonly<Record<string, string>>;

/**
 * Worker count this machine can hold, given {@link GIB_PER_WORKER}.
 *
 * @param totalRamGib - total RAM in GiB; defaults to a live reading.
 * @returns a value in `[MIN_HEAVY_WORKERS, MAX_HEAVY_WORKERS]`.
 */
export function heavyToolWorkers(totalRamGib: number = totalmem() / 1024 ** 3): number {
  const byRam = Math.floor(totalRamGib / GIB_PER_WORKER);
  return Math.min(MAX_HEAVY_WORKERS, Math.max(MIN_HEAVY_WORKERS, byRam));
}

/**
 * Append `--max-old-space-size` to an existing `NODE_OPTIONS`, or create it.
 *
 * Never clobbers: a project may legitimately set `--experimental-*` flags there,
 * and dropping them would break the very command we are trying to run. An
 * existing `--max-old-space-size` is left alone — an explicit choice outranks
 * our default.
 *
 * @param existing - current `NODE_OPTIONS`, if any.
 * @param heapMb - ceiling to apply.
 * @returns the merged value.
 */
export function mergeNodeOptions(existing: string | undefined, heapMb: number): string {
  const current = (existing ?? '').trim();
  if (/--max-old-space-size[= ]/.test(current)) return current;
  const flag = `--max-old-space-size=${heapMb}`;
  return current.length > 0 ? `${current} ${flag}` : flag;
}

/**
 * Build the environment overlay for a heavy tool spawn.
 *
 * Returns an empty object for non-heavy tools, so the caller can merge
 * unconditionally.
 *
 * @param canonical - the canonical tool about to be spawned.
 * @param env - the environment the child would otherwise inherit.
 * @param totalRamGib - total RAM in GiB; injectable for deterministic tests.
 * @returns variables to overlay; existing deliberate values are preserved.
 *
 * @example
 * ```ts
 * const overlay = heavyToolEnv('test', process.env, 62);
 * // { NODE_OPTIONS: '--max-old-space-size=4096',
 * //   VITEST_MAX_WORKERS: '6',
 * //   npm_config_workspace_concurrency: '1' }
 * heavyToolEnv('lint', process.env, 62); // → {}
 * ```
 *
 * @task T12096
 */
export function heavyToolEnv(
  canonical: CanonicalTool,
  env: NodeJS.ProcessEnv = process.env,
  totalRamGib: number = totalmem() / 1024 ** 3,
): HeavyToolEnv {
  if (canonical !== 'test' && canonical !== 'build') return {};

  const overlay: Record<string, string> = {
    NODE_OPTIONS: mergeNodeOptions(env.NODE_OPTIONS, HEAVY_TOOL_HEAP_MB),
  };

  // Respect a deliberate setting; supply one otherwise.
  if (!env.VITEST_MAX_WORKERS) {
    overlay.VITEST_MAX_WORKERS = String(heavyToolWorkers(totalRamGib));
  }
  if (!env.npm_config_workspace_concurrency) {
    overlay.npm_config_workspace_concurrency = String(WORKSPACE_CONCURRENCY);
  }

  return overlay;
}
