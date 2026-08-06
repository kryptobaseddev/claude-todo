/**
 * Tests for the actionable symbol-miss error (T12068).
 *
 * The behaviour under test is not "an error is thrown" — that already
 * happened. It is that the error DISTINGUISHES a stale index from a genuine
 * typo, because collapsing those two is what makes an agent abandon the
 * subsystem.
 *
 * @task T12068
 */

import { describe, expect, it } from 'vitest';
import {
  buildSymbolMissError,
  classifyIndexFreshness,
  medianIndexedAt,
  newestIndexedAt,
} from '../symbol-miss.js';

/** 2026-08-06T06:00:00Z — the reference "now" for every age assertion here. */
const NOW = Date.parse('2026-08-06T06:00:00Z');

/** Build `count` node rows all stamped with `indexedAt`. */
function nodes(count: number, indexedAt: string): Array<Record<string, unknown>> {
  return Array.from({ length: count }, (_, i) => ({ id: `n${i}`, indexedAt }));
}

describe('newestIndexedAt', () => {
  it('returns null for an empty index', () => {
    expect(newestIndexedAt([])).toBeNull();
  });

  it('returns null when no row carries a timestamp', () => {
    expect(newestIndexedAt([{ id: 'a' }, { id: 'b', indexedAt: null }])).toBeNull();
  });

  it('picks the maximum timestamp', () => {
    const rows = [
      { indexedAt: '2026-05-04 10:00:00' },
      { indexedAt: '2026-08-05 09:09:51' },
      { indexedAt: '2026-04-14 01:00:00' },
    ];
    expect(newestIndexedAt(rows)).toBe('2026-08-05 09:09:51');
  });

  it('accepts the snake_case column name too', () => {
    expect(newestIndexedAt([{ indexed_at: '2026-01-01 00:00:00' }])).toBe('2026-01-01 00:00:00');
  });
});

describe('medianIndexedAt', () => {
  it('ignores a handful of recent rows in a mostly-old index', () => {
    // The exact shape measured on this repo: 3 rows re-indexed yesterday,
    // 14151 rows from three months ago. The MAX says "fresh"; the median
    // must not.
    const rows = [...nodes(14_151, '2026-05-04 12:00:00'), ...nodes(3, '2026-08-05 09:09:51')];
    expect(newestIndexedAt(rows)).toBe('2026-08-05 09:09:51');
    expect(medianIndexedAt(rows)).toBe('2026-05-04 12:00:00');
  });

  it('returns null for an empty index', () => {
    expect(medianIndexedAt([])).toBeNull();
  });
});

describe('classifyIndexFreshness', () => {
  it('reports never-indexed for a null timestamp', () => {
    expect(classifyIndexFreshness(null, NOW)).toEqual({
      freshness: 'never-indexed',
      indexAgeDays: null,
    });
  });

  it('treats a same-day index as fresh', () => {
    const { freshness, indexAgeDays } = classifyIndexFreshness('2026-08-06 01:00:00', NOW);
    expect(freshness).toBe('fresh');
    expect(indexAgeDays).toBe(0);
  });

  it('treats a 93-day-old index as stale', () => {
    const { freshness, indexAgeDays } = classifyIndexFreshness('2026-05-05 06:00:00', NOW);
    expect(freshness).toBe('stale');
    expect(indexAgeDays).toBe(93);
  });

  it('parses the SQLite space-separated form as UTC, not host-local', () => {
    // `datetime('now')` has no zone designator. Reading it as local time would
    // shift the age by up to a day and flip the fresh/stale boundary.
    const spaced = classifyIndexFreshness('2026-07-30 06:00:00', NOW);
    const iso = classifyIndexFreshness('2026-07-30T06:00:00Z', NOW);
    expect(spaced).toEqual(iso);
    expect(spaced.indexAgeDays).toBe(7);
  });
});

describe('buildSymbolMissError', () => {
  it('is an E_NOT_FOUND carrying structured details', () => {
    const err = buildSymbolMissError('foo', 'P1', nodes(10, '2026-08-06 05:00:00'), NOW);
    expect(err.code).toBe('E_NOT_FOUND');
    expect(err.details.symbol).toBe('foo');
    expect(err.details.projectId).toBe('P1');
    expect(err.details.indexedSymbolCount).toBe(10);
  });

  it('tells the agent to re-index when the index body is stale', () => {
    const rows = [...nodes(999, '2026-05-05 06:00:00'), ...nodes(3, '2026-08-05 09:09:51')];
    const err = buildSymbolMissError('normalizeMarkers', 'P1', rows, NOW);

    expect(err.details.freshness).toBe('stale');
    expect(err.details.indexAgeDays).toBe(93);
    expect(err.message).toContain('cleo nexus analyze');
    // The critical distinction: MISSING FROM THE INDEX, not absent from code.
    expect(err.message).toMatch(/MISSING from it — not absent from the code/);
  });

  it('does NOT blame the index when it is genuinely current', () => {
    const err = buildSymbolMissError('typoed', 'P1', nodes(500, '2026-08-06 05:00:00'), NOW);
    expect(err.details.freshness).toBe('fresh');
    expect(err.message).toContain('check the symbol spelling');
    expect(err.message).not.toContain('cleo nexus analyze');
  });

  it('reports never-indexed distinctly from stale', () => {
    const err = buildSymbolMissError('anything', 'P1', [], NOW);
    expect(err.details.freshness).toBe('never-indexed');
    expect(err.message).toContain('no code-intelligence index yet');
    expect(err.message).toContain('cleo nexus analyze');
  });

  it('classifies on the median, so a few fresh rows cannot mask a stale index', () => {
    const rows = [...nodes(1000, '2026-05-04 12:00:00'), ...nodes(3, '2026-08-06 05:00:00')];
    const err = buildSymbolMissError('x', 'P1', rows, NOW);
    expect(err.details.lastIndexedAt).toBe('2026-08-06 05:00:00'); // max says fresh
    expect(err.details.freshness).toBe('stale'); // median says otherwise
  });
});
