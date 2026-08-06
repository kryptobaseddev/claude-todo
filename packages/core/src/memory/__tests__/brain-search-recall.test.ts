/**
 * Recall-quality regressions for BRAIN search (T12073).
 *
 * These lock the two independent defects that made `cleo memory find` return
 * plausible-but-wrong results for anything except an exact rare token:
 *
 *   1. exact-match terms, so morphological variants were invisible; and
 *   2. a fixed table concatenation, so the largest store was structurally
 *      unreachable regardless of relevance.
 *
 * @task T12073
 */

import { describe, expect, it } from 'vitest';
import {
  buildFts5Queries,
  escapeFts5Query,
  interleaveRanked,
  matchConjunctiveFirst,
} from '../brain-search.js';

describe('buildFts5Queries (T12073)', () => {
  it('emits prefix-matching terms so morphological variants are reachable', () => {
    // Measured on the live corpus: `orphan` matched 113 documents while
    // `orphan*` matched 189. Seventy-six documents saying "orphaned" could not
    // be found by searching for "orphan". FTS5's unicode61 tokenizer has no
    // stemmer, so the prefix operator is the substitute.
    const q = buildFts5Queries('orphan');
    expect(q.and).toBe('"orphan"*');
    expect(q.or).toBe('"orphan"*');
  });

  it('produces both a conjunctive and a disjunctive form', () => {
    const q = buildFts5Queries('nexus orphan');
    expect(q.and).toBe('"nexus"* AND "orphan"*');
    expect(q.or).toBe('"nexus"* OR "orphan"*');
    expect(q.termCount).toBe(2);
  });

  it('drops punctuation-only tokens rather than zeroing the query (T553)', () => {
    // The original reason OR semantics were introduced: an em dash or a bare
    // colon cannot be indexed, and under implicit AND that guaranteed zero
    // matches for the whole query.
    const q = buildFts5Queries('EPIC: — auth');
    expect(q.and).toBe('"EPIC"* AND "auth"*');
  });

  it('deduplicates case-insensitively', () => {
    expect(buildFts5Queries('Auth auth AUTH').termCount).toBe(1);
  });

  it('escapes embedded quotes so a query cannot break out of the term', () => {
    const q = buildFts5Queries('say"hi');
    expect(q.and).toBe('"say""hi"*');
  });

  it('returns a safe empty match for an all-punctuation query', () => {
    expect(buildFts5Queries('— :: !').and).toBe('""');
    expect(buildFts5Queries('').termCount).toBe(0);
  });

  it('keeps escapeFts5Query as the disjunctive form for existing callers', () => {
    expect(escapeFts5Query('nexus orphan')).toBe('"nexus"* OR "orphan"*');
  });
});

describe('matchConjunctiveFirst (T12073)', () => {
  it('prefers the conjunctive result when it is non-empty', () => {
    const seen: string[] = [];
    const rows = matchConjunctiveFirst((expr) => {
      seen.push(expr);
      return expr.includes('AND') ? ['precise'] : ['noisy'];
    }, buildFts5Queries('nexus orphan'));
    expect(rows).toEqual(['precise']);
    expect(seen).toHaveLength(1); // OR never ran
  });

  it('falls back to disjunctive only when the conjunction finds nothing', () => {
    const seen: string[] = [];
    const rows = matchConjunctiveFirst((expr) => {
      seen.push(expr);
      return expr.includes('AND') ? [] : ['fallback'];
    }, buildFts5Queries('nexus orphan'));
    expect(rows).toEqual(['fallback']);
    expect(seen).toEqual(['"nexus"* AND "orphan"*', '"nexus"* OR "orphan"*']);
  });

  it('does not double-run a single-term query (AND and OR are identical)', () => {
    let calls = 0;
    matchConjunctiveFirst(() => {
      calls++;
      return [];
    }, buildFts5Queries('orphan'));
    expect(calls).toBe(1);
  });
});

describe('interleaveRanked (T12073)', () => {
  it('round-robins so no source is systematically last', () => {
    expect(interleaveRanked([['a1', 'a2'], ['b1'], ['c1', 'c2', 'c3']])).toEqual([
      'a1',
      'b1',
      'c1',
      'a2',
      'c2',
      'c3',
    ]);
  });

  it('preserves each source internal ordering', () => {
    const out = interleaveRanked([
      ['a1', 'a2', 'a3'],
      ['b1', 'b2', 'b3'],
    ]);
    expect(out.filter((x) => x.startsWith('a'))).toEqual(['a1', 'a2', 'a3']);
    expect(out.filter((x) => x.startsWith('b'))).toEqual(['b1', 'b2', 'b3']);
  });

  it('reaches the LAST source within the first round — the regression', () => {
    // Concatenation put observations after decisions+patterns+learnings, so
    // with those three saturating the result window an observation could never
    // place, however relevant. With 128 decisions and ~5,000 observations that
    // made the largest store the least reachable.
    const decisions = Array.from({ length: 10 }, (_, i) => `D${i}`);
    const patterns = Array.from({ length: 10 }, (_, i) => `P${i}`);
    const learnings = Array.from({ length: 10 }, (_, i) => `L${i}`);
    const observations = ['O-relevant'];

    const concatenated = [...decisions, ...patterns, ...learnings, ...observations];
    expect(concatenated.slice(0, 10)).not.toContain('O-relevant');

    const interleaved = interleaveRanked([decisions, patterns, learnings, observations]);
    expect(interleaved.slice(0, 10)).toContain('O-relevant');
  });

  it('handles empty and single-source inputs', () => {
    expect(interleaveRanked([])).toEqual([]);
    expect(interleaveRanked([[], []])).toEqual([]);
    expect(interleaveRanked([['only']])).toEqual(['only']);
  });
});
