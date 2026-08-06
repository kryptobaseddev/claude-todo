/**
 * Locks the SpawnResult → SubagentStop status mapping (T12071).
 *
 * These are two DIFFERENT vocabularies that were being passed through as if
 * they were one: spawn reports `pending|running|completed|failed|cancelled`,
 * the hook payload admits `complete|partial|blocked|failed`. Note in
 * particular `completed` vs `complete` — a one-character difference that made
 * every spawn emit a status outside its declared union.
 *
 * @task T12071
 */

import { describe, expect, it } from 'vitest';
import { toSubagentStopStatus } from '../spawn-ops.js';

describe('toSubagentStopStatus (T12071)', () => {
  it("maps 'completed' to 'complete' — the one-character mismatch", () => {
    expect(toSubagentStopStatus('completed')).toBe('complete');
  });

  it("passes 'failed' through — the only shared member", () => {
    expect(toSubagentStopStatus('failed')).toBe('failed');
  });

  it("maps 'cancelled' to 'blocked' — terminal, but neither success nor error", () => {
    expect(toSubagentStopStatus('cancelled')).toBe('blocked');
  });

  it("maps non-terminal states to 'partial'", () => {
    expect(toSubagentStopStatus('pending')).toBe('partial');
    expect(toSubagentStopStatus('running')).toBe('partial');
  });

  it("maps an absent status to 'partial' rather than leaking undefined", () => {
    // CLEOSpawnResult.status is optional; before T12071 an absent value flowed
    // straight into the payload, which is how BRAIN accumulated 2012 rows
    // reading "status: undefined".
    expect(toSubagentStopStatus(undefined)).toBe('partial');
  });

  it('only ever returns a member of the SubagentStop union', () => {
    const allowed = new Set(['complete', 'partial', 'blocked', 'failed']);
    for (const s of [
      'pending',
      'running',
      'completed',
      'failed',
      'cancelled',
      undefined,
    ] as const) {
      expect(allowed.has(toSubagentStopStatus(s))).toBe(true);
    }
  });
});
