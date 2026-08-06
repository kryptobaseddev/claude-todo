/**
 * Tests for the shared collection resolver (T12077).
 *
 * The bug this exists to prevent is not "returns the wrong rows" — it is
 * "returns NO rows, silently, and the caller cannot tell that from an empty
 * result set". That is how the sentient loop reported "no unblocked tasks
 * available" on every tick for three months.
 *
 * @task T12077
 */

import { COLLECTION_KEYS } from '@cleocode/contracts';
import { describe, expect, it } from 'vitest';
import { collectionOf, pickCollection } from '../collection.js';

describe('pickCollection (T12077)', () => {
  it('resolves the BARE shape the SDK returns', () => {
    // `cleo.tasks.find()` returns `{results, total}` with NO `data` wrapper.
    // Reading `.data.tasks` from this — as the sentient picker did — yields
    // undefined twice over.
    const sdkResponse = { results: [{ id: 'T11191' }, { id: 'T11192' }], total: 2 };
    expect(pickCollection(sdkResponse)).toHaveLength(2);
  });

  it('resolves the ENVELOPED shape the dispatch surface returns', () => {
    expect(pickCollection({ data: { tasks: [{ id: 'T1' }] } })).toEqual([{ id: 'T1' }]);
  });

  it('resolves every declared collection key', () => {
    for (const key of COLLECTION_KEYS) {
      expect(pickCollection({ [key]: [{ id: 'X' }] }), `key: ${key}`).toEqual([{ id: 'X' }]);
    }
  });

  it('covers suggestions — the key `cleo next` emits', () => {
    // `cleo next --output id` reported "No ids." against an envelope holding
    // 836 candidates, because `suggestions` was in nobody's key list.
    const next = { suggestions: [{ id: 'T12034', score: 125 }], totalCandidates: 836 };
    expect(pickCollection(next)).toHaveLength(1);
  });

  it('prefers the canonical `tasks` key when several are present', () => {
    expect(pickCollection({ tasks: [{ id: 'A' }], results: [{ id: 'B' }] })).toEqual([{ id: 'A' }]);
  });

  it('returns undefined — not an empty array — when no collection exists', () => {
    // The distinction matters: `undefined` lets a caller detect "wrong shape",
    // which is exactly the signal that was missing.
    expect(pickCollection({ total: 0 })).toBeUndefined();
    expect(pickCollection(null)).toBeUndefined();
    expect(pickCollection('nope')).toBeUndefined();
    expect(pickCollection(undefined)).toBeUndefined();
  });

  it('does not treat a non-array value under a collection key as rows', () => {
    expect(pickCollection({ tasks: 42 })).toBeUndefined();
    expect(pickCollection({ results: { id: 'T1' } })).toBeUndefined();
  });

  it('does not recurse past one level of `data`', () => {
    expect(pickCollection({ data: { data: { tasks: [{ id: 'deep' }] } } })).toBeUndefined();
  });
});

describe('collectionOf (T12077)', () => {
  it('returns an empty array rather than undefined for ergonomic use', () => {
    expect(collectionOf({ total: 0 })).toEqual([]);
  });

  it('reproduces the sentient-loop regression end to end', () => {
    const sdkResponse = { results: [{ id: 'T1009' }, { id: 'T1010' }], total: 2 };

    // What the picker used to do — wrong key, through a wrapper that is not there.
    const old = Array.isArray((sdkResponse as { data?: { tasks?: unknown[] } })?.data?.tasks)
      ? (sdkResponse as unknown as { data: { tasks: unknown[] } }).data.tasks
      : [];
    expect(old).toEqual([]); // ← always empty ⇒ 'no unblocked tasks available'

    // What it does now.
    expect(collectionOf(sdkResponse)).toHaveLength(2);
  });
});
