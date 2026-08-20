/**
 * Tests for the `cleo complete` commit-atom revalidation cache
 * (T12102 / gh#1196).
 *
 * Covers:
 *   - Key derivation: deterministic, case-insensitive, head-sensitive.
 *   - Entry IO: write/read roundtrip, corrupt + foreign entries rejected.
 *   - Integration via {@link revalidateEvidence}: first call validates and
 *     caches; second call hits the cache (progress line says so); a HEAD
 *     move invalidates; `files:` atoms are NEVER cached (staleness check
 *     still re-reads content).
 *
 * @task T12102
 */

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { revalidateEvidence } from '../evidence.js';
import {
  computeCommitRevalidationKey,
  readCommitRevalidationEntry,
  writeCommitRevalidationEntry,
} from '../revalidation-cache.js';

function git(dir: string, args: string[]): string {
  return execFileSync('git', args, { cwd: dir }).toString();
}

function initRepo(dir: string): string {
  git(dir, ['init', '-q']);
  git(dir, ['config', 'user.name', 'Test']);
  git(dir, ['config', 'user.email', 'test@example.com']);
  writeFileSync(join(dir, 'a.txt'), 'one\n');
  git(dir, ['add', 'a.txt']);
  git(dir, ['commit', '-q', '-m', 'first']);
  return git(dir, ['rev-parse', 'HEAD']).trim();
}

describe('computeCommitRevalidationKey (T12102)', () => {
  it('is deterministic and case-insensitive', () => {
    const a = computeCommitRevalidationKey('ABC123', 'DEF456');
    const b = computeCommitRevalidationKey('abc123', 'def456');
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{32}$/);
  });

  it('changes when HEAD moves', () => {
    const a = computeCommitRevalidationKey('abc123', 'head1');
    const b = computeCommitRevalidationKey('abc123', 'head2');
    expect(a).not.toBe(b);
  });
});

describe('commit-revalidation entry IO (T12102)', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'reval-cache-'));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('round-trips a written entry', () => {
    const key = computeCommitRevalidationKey('a'.repeat(40), 'b'.repeat(40));
    writeCommitRevalidationEntry(tmpDir, {
      schemaVersion: 1,
      kind: 'commit-revalidation',
      key,
      sha: 'a'.repeat(40),
      shortSha: 'aaaaaaa',
      head: 'b'.repeat(40),
      capturedAt: new Date().toISOString(),
    });
    const read = readCommitRevalidationEntry(tmpDir, key);
    expect(read?.sha).toBe('a'.repeat(40));
    expect(read?.shortSha).toBe('aaaaaaa');
  });

  it('returns null for a missing entry', () => {
    expect(readCommitRevalidationEntry(tmpDir, 'f'.repeat(32))).toBeNull();
  });

  it('returns null for a corrupt entry', () => {
    const key = 'e'.repeat(32);
    // ensureCacheDir is only created by the writer — create it manually here.
    const dir = join(tmpDir, '.cleo', 'cache', 'evidence');
    execFileSync('mkdir', ['-p', dir]);
    writeFileSync(join(dir, `reval-commit-${key}.json`), 'not json{');
    expect(readCommitRevalidationEntry(tmpDir, key)).toBeNull();
  });

  it('returns null when the embedded key does not match the requested key', () => {
    const key = computeCommitRevalidationKey('a'.repeat(40), 'b'.repeat(40));
    writeCommitRevalidationEntry(tmpDir, {
      schemaVersion: 1,
      kind: 'commit-revalidation',
      key,
      sha: 'a'.repeat(40),
      shortSha: 'aaaaaaa',
      head: 'b'.repeat(40),
      capturedAt: new Date().toISOString(),
    });
    expect(readCommitRevalidationEntry(tmpDir, '0'.repeat(32))).toBeNull();
  });
});

describe('revalidateEvidence commit caching (T12102)', () => {
  let tmpDir: string;
  let headSha: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'reval-evidence-'));
    headSha = initRepo(tmpDir);
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  function cacheFiles(): string[] {
    const dir = join(tmpDir, '.cleo', 'cache', 'evidence');
    return existsSync(dir) ? readdirSync(dir).filter((f) => f.startsWith('reval-commit-')) : [];
  }

  it('validates + caches on first call, hits cache on second (progress reports it)', async () => {
    const evidence = {
      atoms: [{ kind: 'commit' as const, sha: headSha, shortSha: headSha.slice(0, 7) }],
      capturedAt: new Date().toISOString(),
      capturedBy: 'test',
    };

    const first: string[] = [];
    const r1 = await revalidateEvidence(evidence, tmpDir, undefined, undefined, {
      onProgress: (m) => first.push(m),
    });
    expect(r1.stillValid).toBe(true);
    expect(cacheFiles()).toHaveLength(1);
    expect(first.join('\n')).toContain(`commit:${headSha.slice(0, 7)} ok`);
    expect(first.join('\n')).not.toContain('(cached)');

    const second: string[] = [];
    const r2 = await revalidateEvidence(evidence, tmpDir, undefined, undefined, {
      onProgress: (m) => second.push(m),
    });
    expect(r2.stillValid).toBe(true);
    expect(second.join('\n')).toContain('(cached)');
  });

  it('re-validates when HEAD moves (key includes headSha)', async () => {
    const evidence = {
      atoms: [{ kind: 'commit' as const, sha: headSha, shortSha: headSha.slice(0, 7) }],
      capturedAt: new Date().toISOString(),
      capturedBy: 'test',
    };
    const r1 = await revalidateEvidence(evidence, tmpDir);
    expect(r1.stillValid).toBe(true);
    expect(cacheFiles()).toHaveLength(1);

    // Move HEAD — the old entry's key no longer matches.
    writeFileSync(join(tmpDir, 'b.txt'), 'two\n');
    git(tmpDir, ['add', 'b.txt']);
    git(tmpDir, ['commit', '-q', '-m', 'second']);

    const progress: string[] = [];
    const r2 = await revalidateEvidence(evidence, tmpDir, undefined, undefined, {
      onProgress: (m) => progress.push(m),
    });
    expect(r2.stillValid).toBe(true);
    expect(progress.join('\n')).not.toContain('(cached)');
    expect(cacheFiles()).toHaveLength(2);
  });

  it('does not cache failures (a missing commit re-runs validation)', async () => {
    const missing = 'f'.repeat(40);
    const evidence = {
      atoms: [{ kind: 'commit' as const, sha: missing, shortSha: missing.slice(0, 7) }],
      capturedAt: new Date().toISOString(),
      capturedBy: 'test',
    };
    const r1 = await revalidateEvidence(evidence, tmpDir);
    expect(r1.stillValid).toBe(false);
    expect(cacheFiles()).toHaveLength(0);
  });

  it('never caches files: atoms — content is re-read on every call', async () => {
    const path = 'watched.txt';
    writeFileSync(join(tmpDir, path), 'original');
    const sha = createHash('sha256').update('original').digest('hex');
    const evidence = {
      atoms: [{ kind: 'files' as const, files: [{ path, sha256: sha }] }],
      capturedAt: new Date().toISOString(),
      capturedBy: 'test',
    };
    const ok = await revalidateEvidence(evidence, tmpDir);
    expect(ok.stillValid).toBe(true);

    // Tamper after "validation" — the very next revalidation MUST catch it.
    // A cache would be exactly what lets this slip through.
    writeFileSync(join(tmpDir, path), 'tampered');
    const progress: string[] = [];
    const stale = await revalidateEvidence(evidence, tmpDir, undefined, undefined, {
      onProgress: (m) => progress.push(m),
    });
    expect(stale.stillValid).toBe(false);
    expect(stale.failedAtoms[0]?.reason).toMatch(/modified/);
    expect(progress.join('\n')).toContain('files:1 path(s) FAILED');
  });
});
