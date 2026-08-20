/**
 * Revalidation cache for the `cleo complete` evidence staleness check
 * (T12102 / gh#1196).
 *
 * `cleo complete` re-validates every hard evidence atom recorded at
 * `cleo verify` time (ADR-051 Decision 8 — `E_EVIDENCE_STALE` catches
 * post-verify tampering). On large repos the per-atom git spawns make a
 * loop of completes slow enough to blow agent tool timeouts.
 *
 * ## What is cached, and why it is safe
 *
 * Only `commit:` atom revalidation is cached, keyed on
 * `(commitSha, headSha)`. Every check {@link validateCommit} performs on
 * the complete-time path (no `taskId`) is an IMMUTABLE fact of the git
 * object DAG once both SHAs are fixed:
 *
 *   - `git cat-file -e <sha>^{commit}` — object existence is immutable
 *     (objects are never removed from a live repo by ordinary work).
 *   - `git merge-base --is-ancestor <sha> <headSha>` — reachability
 *     between two fixed commits can never change.
 *   - `git rev-parse [--short] <sha>` — canonicalisation is immutable.
 *
 * A new commit moves `HEAD`, which changes the key, so post-verify
 * commits always force a fresh validation. Only successful validations
 * are cached: a "commit not found" failure is NOT immutable (a later
 * `git fetch` can make the object appear), so failures always re-run.
 *
 * ## What is deliberately NOT cached
 *
 *   - `files:` / `test-run:` — the staleness guarantee IS the
 *     read-the-file-and-compare-sha256 step. Any cheaper key (mtime +
 *     size) is forgeable and would silently weaken `E_EVIDENCE_STALE`,
 *     which is the entire point of re-validation. These atoms stay
 *     uncached; their cost is one read + one hash per path.
 *   - `tool:` — never re-executed at complete time by design (see
 *     {@link revalidateEvidence}); verify-time results are already
 *     memoised by the ADR-061 cache in tool-cache.ts.
 *
 * Entries live beside the ADR-061 tool cache under
 * `.cleo/cache/evidence/reval-commit-<key>.json` so `clearToolCache`
 * wipes them too — the cache is purely advisory.
 *
 * @task T12102 (gh#1196)
 * @adr ADR-051
 * @adr ADR-061
 */

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * One cached `commit:` atom revalidation. Success-only by design — see
 * the module docstring for the immutability argument.
 *
 * @task T12102
 */
export interface CommitRevalidationEntry {
  /** Schema version for forwards compatibility. */
  schemaVersion: 1;
  /** Discriminator so a foreign JSON blob is never trusted. */
  kind: 'commit-revalidation';
  /** Cache key (also encoded in the filename). */
  key: string;
  /** Canonical full commit SHA that validated successfully. */
  sha: string;
  /** Abbreviated SHA captured at validation time. */
  shortSha: string;
  /** `HEAD` SHA the reachability check ran against. */
  head: string;
  /** ISO 8601 wall-clock timestamp of the validation. */
  capturedAt: string;
}

/**
 * Compute the cache key for a `(commitSha, headSha)` pair.
 *
 * Mirrors the ADR-061 key style: sha256 of the JSON payload, truncated
 * to 32 hex chars — collision-resistant and bounded regardless of input.
 *
 * @task T12102
 */
export function computeCommitRevalidationKey(commitSha: string, headSha: string): string {
  const payload = JSON.stringify({
    kind: 'commit-revalidation',
    sha: commitSha.toLowerCase(),
    head: headSha.toLowerCase(),
  });
  return createHash('sha256').update(payload).digest('hex').slice(0, 32);
}

/**
 * Absolute path for a revalidation cache entry by key.
 *
 * @task T12102
 */
export function commitRevalidationPath(projectRoot: string, key: string): string {
  return join(projectRoot, '.cleo', 'cache', 'evidence', `reval-commit-${key}.json`);
}

/**
 * Read a cached commit-revalidation entry. Returns `null` when the entry
 * is missing, unreadable, schema-incompatible, or keyed differently
 * (defence against a poisoned cache directory).
 *
 * @task T12102
 */
export function readCommitRevalidationEntry(
  projectRoot: string,
  key: string,
): CommitRevalidationEntry | null {
  const path = commitRevalidationPath(projectRoot, key);
  if (!existsSync(path)) return null;
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf-8')) as Partial<CommitRevalidationEntry>;
    if (parsed.schemaVersion !== 1 || parsed.kind !== 'commit-revalidation') return null;
    if (parsed.key !== key) return null;
    if (typeof parsed.sha !== 'string' || typeof parsed.head !== 'string') return null;
    return parsed as CommitRevalidationEntry;
  } catch {
    return null;
  }
}

/**
 * Atomically write a cache entry: tmp-then-rename so concurrent readers
 * never observe a half-written file (same discipline as tool-cache.ts).
 *
 * @task T12102
 */
export function writeCommitRevalidationEntry(
  projectRoot: string,
  entry: CommitRevalidationEntry,
): void {
  const dir = join(projectRoot, '.cleo', 'cache', 'evidence');
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  const finalPath = commitRevalidationPath(projectRoot, entry.key);
  const tmpPath = `${finalPath}.${process.pid}.tmp`;
  writeFileSync(tmpPath, JSON.stringify(entry, null, 2), 'utf-8');
  renameSync(tmpPath, finalPath);
}
