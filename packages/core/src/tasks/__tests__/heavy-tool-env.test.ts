/**
 * Heavy-tool spawn ceiling (T12096).
 *
 * The property that matters is that the ceiling BINDS a project which has no
 * memory-safe config of its own — that was the measured failure — while never
 * overriding a value the project set deliberately.
 *
 * @task T12096
 */

import { describe, expect, it } from 'vitest';
import {
  GIB_PER_WORKER,
  HEAVY_TOOL_HEAP_MB,
  heavyToolEnv,
  heavyToolWorkers,
  MAX_HEAVY_WORKERS,
  MIN_HEAVY_WORKERS,
  mergeNodeOptions,
  WORKSPACE_CONCURRENCY,
} from '../heavy-tool-env.js';

describe('heavyToolWorkers (T12096)', () => {
  it('scales with RAM and clamps at both ends', () => {
    expect(heavyToolWorkers(62)).toBe(MAX_HEAVY_WORKERS); // ⌊62/6⌋=10 → 6
    expect(heavyToolWorkers(24)).toBe(4);
    expect(heavyToolWorkers(12)).toBe(2);
    expect(heavyToolWorkers(4)).toBe(MIN_HEAVY_WORKERS); // ⌊4/6⌋=0 → 1
    expect(heavyToolWorkers(0)).toBe(MIN_HEAVY_WORKERS);
  });

  it('uses GIB_PER_WORKER as the divisor', () => {
    expect(heavyToolWorkers(GIB_PER_WORKER * 3)).toBe(3);
  });
});

describe('mergeNodeOptions (T12096)', () => {
  it('creates NODE_OPTIONS when absent', () => {
    expect(mergeNodeOptions(undefined, 4096)).toBe('--max-old-space-size=4096');
    expect(mergeNodeOptions('', 4096)).toBe('--max-old-space-size=4096');
  });

  it('APPENDS rather than clobbering — other flags must survive', () => {
    // Dropping a project's `--experimental-*` flags would break the very command
    // we are trying to bound.
    expect(mergeNodeOptions('--experimental-vm-modules', 4096)).toBe(
      '--experimental-vm-modules --max-old-space-size=4096',
    );
  });

  it('leaves an existing --max-old-space-size alone', () => {
    // A deliberate choice outranks our default, in either direction.
    expect(mergeNodeOptions('--max-old-space-size=8192', 4096)).toBe('--max-old-space-size=8192');
    expect(mergeNodeOptions('--max-old-space-size 8192', 4096)).toBe('--max-old-space-size 8192');
  });
});

describe('heavyToolEnv (T12096)', () => {
  it('bounds a test spawn on all three levers', () => {
    // The PepsVida case: 15 workspace packages with test scripts, no vitest
    // config capping anything.
    const env = heavyToolEnv('test', {}, 62);
    expect(env.NODE_OPTIONS).toBe(`--max-old-space-size=${HEAVY_TOOL_HEAP_MB}`);
    expect(env.VITEST_MAX_WORKERS).toBe(String(MAX_HEAVY_WORKERS));
    expect(env.npm_config_workspace_concurrency).toBe(String(WORKSPACE_CONCURRENCY));
  });

  it('bounds build the same way', () => {
    expect(heavyToolEnv('build', {}, 62).NODE_OPTIONS).toBeDefined();
  });

  it('leaves LIGHT tools completely alone', () => {
    // Serialising lint/typecheck would cost time and buy nothing — they are
    // single-process.
    for (const t of ['lint', 'typecheck', 'audit', 'security-scan'] as const) {
      expect(heavyToolEnv(t, {}, 62)).toEqual({});
    }
  });

  it('respects every value the project already set', () => {
    const env = heavyToolEnv(
      'test',
      {
        VITEST_MAX_WORKERS: '12',
        npm_config_workspace_concurrency: '4',
        NODE_OPTIONS: '--max-old-space-size=16384',
      },
      62,
    );
    expect(env.VITEST_MAX_WORKERS).toBeUndefined();
    expect(env.npm_config_workspace_concurrency).toBeUndefined();
    expect(env.NODE_OPTIONS).toBe('--max-old-space-size=16384');
  });

  it('still bounds workers on a small machine', () => {
    expect(heavyToolEnv('test', {}, 8).VITEST_MAX_WORKERS).toBe('1');
  });

  it('worst case is bounded by RAM, which is the whole point', () => {
    // packages-in-flight × workers × heap must not exceed the machine. The old
    // arrangement had no bound on the first factor at all.
    const env = heavyToolEnv('test', {}, 62);
    const workers = Number(env.VITEST_MAX_WORKERS);
    const packages = Number(env.npm_config_workspace_concurrency);
    const worstCaseGib = (packages * workers * HEAVY_TOOL_HEAP_MB) / 1024;
    expect(worstCaseGib).toBeLessThanOrEqual(62);
  });
});
