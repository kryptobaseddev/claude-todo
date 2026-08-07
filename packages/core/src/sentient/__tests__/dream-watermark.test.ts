/**
 * Incremental + adaptive consolidation policy (T12088).
 *
 * Three measured defects motivate these:
 *
 * 1. Consecutive dream cycles collected 25 → 28 → 30 → 36 → 37 observations —
 *    re-clustering and re-sending the SAME material every pass. Dedup at the
 *    storage gate hid the waste while it consumed the whole LLM budget.
 * 2. The sentient loop was dead for three months; every observation from that
 *    period aged past the 24 h window and was consolidated NEVER, not later.
 * 3. A fixed `clusterMinSize: 5` meant a freshly dropped-in CLEO — which never
 *    has 5 similar observations — completed with `memoriesStored: 0`
 *    indefinitely, so it could not begin learning at all.
 *
 * @task T12088
 */

import { describe, expect, it } from 'vitest';
import {
  ADAPTIVE_CLUSTER_DIVISOR,
  adaptiveClusterMinSize,
  DEFAULT_NOMINAL_LOOKBACK_MS,
  MAX_ADAPTIVE_CLUSTER_SIZE,
  MAX_CATCHUP_LOOKBACK_MS,
  MIN_ADAPTIVE_CLUSTER_SIZE,
  nextWatermark,
  resolveLookbackMs,
  selectUnconsolidated,
} from '../dream-watermark.js';

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.parse('2026-08-06T12:00:00.000Z');

describe('resolveLookbackMs (T12088)', () => {
  it('uses the nominal window on a first run (no watermark)', () => {
    // Unchanged behaviour: a brand-new project has nothing consolidated.
    expect(resolveLookbackMs(null, DAY, NOW)).toBe(DAY);
  });

  it('WIDENS the window to cover a gap while the daemon was off', () => {
    // The three-month-dead-loop case: without this, everything older than 24 h
    // is skipped permanently rather than caught up.
    const fiveDaysAgo = new Date(NOW - 5 * DAY).toISOString();
    expect(resolveLookbackMs(fiveDaysAgo, DAY, NOW)).toBe(5 * DAY);
  });

  it('never NARROWS below the nominal window', () => {
    // A watermark from a minute ago must not shrink the pass to 60 s and starve
    // clustering of the context it needs to group anything.
    const aMinuteAgo = new Date(NOW - 60_000).toISOString();
    expect(resolveLookbackMs(aMinuteAgo, DAY, NOW)).toBe(DAY);
  });

  it('caps catch-up so one tick cannot pull in an entire corpus', () => {
    const ancient = new Date(NOW - 400 * DAY).toISOString();
    expect(resolveLookbackMs(ancient, DAY, NOW)).toBe(MAX_CATCHUP_LOOKBACK_MS);
  });

  it('falls back to nominal on an unparseable watermark', () => {
    // Corrupt state must degrade to the old behaviour, never to "no work".
    expect(resolveLookbackMs('not-a-date', DAY, NOW)).toBe(DAY);
  });

  it('defaults the nominal window to 24 h', () => {
    expect(resolveLookbackMs(null)).toBe(DEFAULT_NOMINAL_LOOKBACK_MS);
  });
});

describe('adaptiveClusterMinSize (T12088)', () => {
  it('lets a YOUNG project consolidate pairs', () => {
    // The drop-in case. At the old fixed 5 this returned nothing, forever.
    expect(adaptiveClusterMinSize(6)).toBe(MIN_ADAPTIVE_CLUSTER_SIZE);
    expect(adaptiveClusterMinSize(15)).toBe(MIN_ADAPTIVE_CLUSTER_SIZE);
  });

  it('scales with the corpus', () => {
    expect(adaptiveClusterMinSize(30)).toBe(3);
    expect(adaptiveClusterMinSize(40)).toBe(4);
  });

  it('demands real repetition once the project is MATURE', () => {
    expect(adaptiveClusterMinSize(50)).toBe(MAX_ADAPTIVE_CLUSTER_SIZE);
    expect(adaptiveClusterMinSize(5000)).toBe(MAX_ADAPTIVE_CLUSTER_SIZE);
  });

  it('never returns below the floor or above the ceiling', () => {
    for (const n of [0, 1, 3, 9, 10, 11, 49, 51, 1_000_000]) {
      const v = adaptiveClusterMinSize(n);
      expect(v).toBeGreaterThanOrEqual(MIN_ADAPTIVE_CLUSTER_SIZE);
      expect(v).toBeLessThanOrEqual(MAX_ADAPTIVE_CLUSTER_SIZE);
    }
  });

  it('treats an empty corpus as mature rather than trivially clusterable', () => {
    // 0 observations must not imply "minimum 2" — there is nothing to cluster,
    // and returning the floor would invite synthesising from noise.
    expect(adaptiveClusterMinSize(0)).toBe(MAX_ADAPTIVE_CLUSTER_SIZE);
  });

  it('crosses each threshold exactly at the divisor boundary', () => {
    expect(adaptiveClusterMinSize(3 * ADAPTIVE_CLUSTER_DIVISOR)).toBe(3);
    expect(adaptiveClusterMinSize(3 * ADAPTIVE_CLUSTER_DIVISOR - 1)).toBe(2);
  });
});

describe('selectUnconsolidated (T12088)', () => {
  const obs = [
    { id: 'a', createdAt: '2026-08-05 10:00:00' },
    { id: 'b', createdAt: '2026-08-06 09:00:00' },
    { id: 'c', createdAt: '2026-08-06 11:00:00' },
  ];

  it('returns everything when there is no watermark', () => {
    expect(selectUnconsolidated(obs, null)).toHaveLength(3);
  });

  it('drops what was already consolidated', () => {
    // This is the 25 → 28 → 30 → 36 → 37 waste, eliminated.
    expect(selectUnconsolidated(obs, '2026-08-06 09:00:00').map((o) => o.id)).toEqual(['c']);
  });

  it('is exclusive at the boundary — the watermark itself is NOT reprocessed', () => {
    expect(selectUnconsolidated(obs, '2026-08-06 11:00:00')).toEqual([]);
  });

  it('does not mutate its input', () => {
    const copy = [...obs];
    selectUnconsolidated(obs, '2026-08-05 10:00:00');
    expect(obs).toEqual(copy);
  });
});

describe('nextWatermark (T12088)', () => {
  it('returns the newest createdAt regardless of input order', () => {
    expect(
      nextWatermark([
        { createdAt: '2026-08-06 11:00:00' },
        { createdAt: '2026-08-06 12:00:00' },
        { createdAt: '2026-08-05 10:00:00' },
      ]),
    ).toBe('2026-08-06 12:00:00');
  });

  it('returns null for an empty batch so progress cannot skip unread material', () => {
    // A no-op pass must leave the existing watermark alone.
    expect(nextWatermark([])).toBeNull();
  });
});
