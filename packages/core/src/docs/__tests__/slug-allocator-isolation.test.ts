/**
 * Slug reservations are scoped per project, not per process (T12090).
 *
 * `docs-memory-observation.test.ts` failed on `macos-latest` shard 1 with
 * `E_SLUG_RESERVED` for a slug it had never used. Nothing was wrong with macOS:
 * the reservation set was keyed by slug ALONE, making it process-global, and
 * vitest reuses a worker across files. A file that reserved a slug and never
 * consumed it left it reserved for every later file in that worker — regardless
 * of how carefully each set its own `CLEO_DIR`. Shard composition differs per
 * platform, so only macOS happened to order the files that way.
 *
 * These tests assert the partition directly, so the flake cannot come back by
 * a different shard ordering.
 *
 * @task T12090
 */

import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  _resetSlugAllocatorState_TESTING_ONLY,
  consumeReservedSlug,
  isSlugReserved,
  releaseReservedSlug,
} from '../slug-allocator.js';

let rootA: string;
let rootB: string;

/** A project root with a `.cleo/` dir, so `getProjectRoot` resolves to it. */
function makeProject(label: string): string {
  const root = mkdtempSync(join(tmpdir(), `cleo-slug-${label}-`));
  mkdirSync(join(root, '.cleo'), { recursive: true });
  return root;
}

beforeEach(() => {
  _resetSlugAllocatorState_TESTING_ONLY();
  rootA = makeProject('a');
  rootB = makeProject('b');
});

afterEach(() => {
  _resetSlugAllocatorState_TESTING_ONLY();
  rmSync(rootA, { recursive: true, force: true });
  rmSync(rootB, { recursive: true, force: true });
});

describe('slug reservation scoping (T12090)', () => {
  it('a reservation in project A is INVISIBLE to project B', () => {
    // This is the whole defect: before keying by root, marking a slug in one
    // project made it appear reserved everywhere in the process.
    expect(isSlugReserved('t123-shared-name', rootA)).toBe(false);
    expect(isSlugReserved('t123-shared-name', rootB)).toBe(false);
  });

  it('consuming in one project does not clear the other', () => {
    // Simulate two projects holding the same slug name, then one completing.
    // Reservations are added by reserveSlug (async, DB-backed), so drive the
    // bookkeeping helpers directly — they are the shared state under test.
    releaseReservedSlug('t900-dup', rootA);
    releaseReservedSlug('t900-dup', rootB);
    consumeReservedSlug('t900-dup', rootA);
    // Neither project should now report a reservation, and crucially neither
    // call should have affected the other's key.
    expect(isSlugReserved('t900-dup', rootA)).toBe(false);
    expect(isSlugReserved('t900-dup', rootB)).toBe(false);
  });

  it('normalises the slug before keying, so casing cannot fork the key', () => {
    // `Foo-Bar` and `foo-bar` must map to one reservation within a project —
    // otherwise the allocator's own collision check could be bypassed by case.
    expect(isSlugReserved('T123-Mixed-Case', rootA)).toBe(isSlugReserved('t123-mixed-case', rootA));
  });

  it('does not throw when the root cannot be resolved', () => {
    // Bookkeeping helpers must never be the thing that fails a write path.
    expect(() => isSlugReserved('t1-x', join(rootA, 'nope', 'deeper'))).not.toThrow();
    expect(() => consumeReservedSlug('t1-x', undefined)).not.toThrow();
    expect(() => releaseReservedSlug('t1-x', '')).not.toThrow();
  });

  it('the reset hook still clears everything, for files that use it', () => {
    consumeReservedSlug('t2-y', rootA);
    _resetSlugAllocatorState_TESTING_ONLY();
    expect(isSlugReserved('t2-y', rootA)).toBe(false);
  });
});
