/**
 * Tests for the targeted BRAIN stub prune (T12073).
 *
 * The behaviour that matters is not "it deletes rows" — it is that it deletes
 * ONLY the content-free ones, defaults to not deleting at all, and cannot
 * reach a substantive record that merely quotes one of the junk strings.
 *
 * @task T12073
 */

import { DatabaseSync } from 'node:sqlite';
import { describe, expect, it } from 'vitest';
import {
  MAX_STUB_NARRATIVE,
  pruneObservationStubs,
  STUB_PRUNE_RULES,
} from '../brain-stub-prune.js';

/** Minimal in-memory `brain_observations` with the columns the prune reads. */
function makeDb(): DatabaseSync {
  const db = new DatabaseSync(':memory:'); // db-open-allowed: in-memory test fixture
  db.exec(`
    CREATE TABLE brain_observations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      narrative TEXT,
      verified INTEGER
    )
  `);
  return db;
}

/** Insert one observation row. */
function insert(
  db: DatabaseSync,
  id: string,
  title: string,
  narrative: string | null,
  verified = 0,
): void {
  db.prepare(
    'INSERT INTO brain_observations (id, title, narrative, verified) VALUES (?,?,?,?)',
  ).run(id, title, narrative, verified);
}

describe('pruneObservationStubs (T12073)', () => {
  it('does NOT delete on a dry run', () => {
    const db = makeDb();
    insert(db, 'O-1', 'Task complete: T100', 'Task T100 completed with status: undefined');

    const result = pruneObservationStubs(db, false);

    expect(result.applied).toBe(false);
    expect(result.matched).toBe(1);
    expect(result.before).toBe(1);
    expect(result.after).toBe(1); // unchanged
  });

  it('deletes the status:undefined artefact when applied', () => {
    const db = makeDb();
    insert(db, 'O-1', 'Task complete: T100', 'Task T100 completed with status: undefined');
    insert(db, 'O-2', 'Task complete: T101', 'Task T101 completed with status: undefined');

    const result = pruneObservationStubs(db, true);

    expect(result.applied).toBe(true);
    expect(result.matched).toBe(2);
    expect(result.after).toBe(0);
    expect(result.byRule['status-undefined']).toBe(2);
  });

  it('PRESERVES a substantive record that merely quotes the junk string', () => {
    // The exact hazard: a post-mortem describing the bug contains the literal
    // "status: undefined". It must survive, and the length guard is what
    // guarantees that.
    const db = makeDb();
    const postMortem = `Root-caused the BRAIN corpus problem. Every completion wrote "status: undefined" because dispatch was generic over T extends HookPayload and inferred T from the argument, so the event and the payload were never related at the type level. ${'x'.repeat(300)}`;
    expect(postMortem.length).toBeGreaterThan(MAX_STUB_NARRATIVE);
    insert(db, 'O-keep', 'hook-dispatch-root-cause', postMortem);
    insert(db, 'O-junk', 'Task complete: T100', 'Task T100 completed with status: undefined');

    const result = pruneObservationStubs(db, true);

    expect(result.matched).toBe(1);
    const remaining = db.prepare('SELECT id FROM brain_observations').all() as Array<{
      id: string;
    }>;
    expect(remaining.map((r) => r.id)).toEqual(['O-keep']);
  });

  it('never deletes a verified record, however short', () => {
    const db = makeDb();
    insert(db, 'O-v', 'Task complete: T100', 'Task T100 completed with status: undefined', 1);

    const result = pruneObservationStubs(db, true);

    expect(result.matched).toBe(0);
    expect(result.after).toBe(1);
  });

  it('leaves ordinary observations untouched', () => {
    const db = makeDb();
    insert(db, 'O-real', 'nexus-analyze-destroys-index', 'Short but genuine finding.');
    insert(db, 'O-start', 'Task start: T100', 'Started work on T100: do the thing');

    const result = pruneObservationStubs(db, true);

    expect(result.byRule['task-start-stub']).toBe(1);
    const remaining = db.prepare('SELECT id FROM brain_observations').all() as Array<{
      id: string;
    }>;
    expect(remaining.map((r) => r.id)).toEqual(['O-real']);
  });

  it('tolerates a NULL narrative', () => {
    const db = makeDb();
    insert(db, 'O-null', 'some title', null);
    expect(() => pruneObservationStubs(db, true)).not.toThrow();
    expect(pruneObservationStubs(db, false).after).toBe(1);
  });

  it('reports a sample so a dry run shows what would go', () => {
    const db = makeDb();
    for (let i = 0; i < 8; i++) {
      insert(db, `O-${i}`, `Task complete: T${i}`, `Task T${i} completed with status: undefined`);
    }
    const result = pruneObservationStubs(db, false);
    expect(result.matched).toBe(8);
    expect(result.sample).toHaveLength(5); // capped
    expect(result.sample[0]?.rule).toBe('status-undefined');
  });

  it('every rule carries a stated reason', () => {
    for (const rule of STUB_PRUNE_RULES) {
      expect(rule.reason.length).toBeGreaterThan(40);
      expect(rule.id).toMatch(/^[a-z][a-z-]*$/);
    }
  });
});
