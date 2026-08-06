/**
 * Structural guards for the self-improvement dogfood scenarios (T12077).
 *
 * ## Why (measured 2026-08-06)
 *
 * `cleo selfimprove run --scenario dhq-replay-find` had **never** produced a
 * clean run. Two independent defects, both in the fixtures rather than the
 * engine:
 *
 * 1. **The golden encoded a shape the operation has never emitted.** It
 *    declared `data.tasks` + `data.count`; `tasks.find` returns `results` +
 *    `total`. Fourth instance of the collection-key confusion that also made
 *    `cleo find --output id` empty (T12067) and the sentient loop inert
 *    (T12077).
 * 2. **The scenario passed the wrong param name.** `tasks.show` takes
 *    `taskId`; the scenario sent `id`, so the op returned
 *    `E_MISSING_PARAMS` and *every* field under `data` diffed.
 *
 * The consequence is worse than a broken test. `envelope-diff.ts` documents
 * that its meta-stripping exists to prevent "a permanent phantom DHQ that
 * self-fires on every clean run" — and the fixture reintroduced exactly that
 * through the data channel. With `--execute`, this loop would open a DHQ row
 * and a draft PR on **every single run, forever**, against a regression that
 * does not exist.
 *
 * A golden is ground truth; when ground truth is wrong the loop cannot tell
 * "the product changed" from "the fixture was never right". These tests assert
 * the fixture agrees with the real operation contract.
 *
 * @task T12077
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/** Scenario directory under `src` (the build copies it to `dist`). */
const SCENARIO_DIR = join(import.meta.dirname, '..', 'scenarios', 'dhq-replay-find');

/** Read and parse a fixture file. */
function readJson(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(SCENARIO_DIR, name), 'utf-8')) as Record<string, unknown>;
}

interface ScenarioOp {
  gateway: string;
  domain: string;
  operation: string;
  params: Record<string, unknown>;
}

interface GoldenEntry {
  success: boolean;
  meta: Record<string, unknown>;
  data: Record<string, unknown>;
}

describe('dhq-replay-find fixture agrees with the operation contract (T12077)', () => {
  const scenario = readJson('scenario.json');
  const golden = readJson('golden.json');
  const ops = scenario['ops'] as ScenarioOp[];
  const envelopes = golden['envelopes'] as GoldenEntry[];

  it('has one golden envelope per scenario op', () => {
    // A length mismatch is itself reported as a regression by diffEnvelopes,
    // which would make the loop permanently red.
    expect(envelopes).toHaveLength(ops.length);
  });

  it('pairs each golden envelope with its op coordinates', () => {
    ops.forEach((op, i) => {
      const meta = envelopes[i]?.meta ?? {};
      expect(meta['domain'], `op ${i} domain`).toBe(op.domain);
      expect(meta['operation'], `op ${i} operation`).toBe(op.operation);
    });
  });

  it('calls tasks.show with `taskId`, not `id`', () => {
    // Sending `id` produced E_MISSING_PARAMS and diffed every field under data.
    const show = ops.find((o) => o.operation === 'show');
    expect(show, 'scenario must exercise tasks.show').toBeDefined();
    expect(Object.keys(show!.params)).toContain('taskId');
    expect(Object.keys(show!.params)).not.toContain('id');
  });

  it('expects the REAL tasks.find collection shape — results/total', () => {
    const findIndex = ops.findIndex((o) => o.operation === 'find');
    const data = envelopes[findIndex]?.data ?? {};

    expect(Object.keys(data)).toContain('results');
    expect(Object.keys(data)).toContain('total');
    // The shape the golden used to claim, which the operation never emitted.
    expect(Object.keys(data)).not.toContain('tasks');
    expect(Object.keys(data)).not.toContain('count');
  });

  it('every golden envelope is a success envelope', () => {
    // A golden that encodes `success: false` would pin an error as correct.
    for (const [i, env] of envelopes.entries()) {
      expect(env.success, `envelope ${i}`).toBe(true);
      expect(env).not.toHaveProperty('error');
    }
  });

  it('pins find to a single task id so the golden is deterministic', () => {
    // A free-text query pins whatever live rows happen to match into the
    // golden, so the loop goes red the moment anyone adds a task. The original
    // fixture used `{query: 'selfimprove'}` and matched 10 rows.
    const find = ops.find((o) => o.operation === 'find');
    expect(find?.params).toHaveProperty('id');
    expect(find?.params).not.toHaveProperty('query');

    const findIndex = ops.findIndex((o) => o.operation === 'find');
    const data = envelopes[findIndex]?.data as { results?: unknown[]; total?: number };
    expect(data.results).toHaveLength(1);
    expect(data.total).toBe(1);
  });

  it('is read-only — no mutate gateway in a dogfood replay', () => {
    for (const op of ops) expect(op.gateway).toBe('query');
  });
});
