/**
 * Actionable "symbol not in the index" errors for the NEXUS code-graph
 * lookups (`cleo nexus impact` / `cleo nexus context`).
 *
 * ## Why this module exists (T12068)
 *
 * Both lookups used to throw a bare
 *
 * ```text
 * No symbol found matching 'normalizeMarkers' in project L21udC9wcm9q…
 * ```
 *
 * which is indistinguishable between the three causes an agent actually
 * cares about:
 *
 *   1. the symbol genuinely does not exist (typo / wrong name),
 *   2. the symbol exists but the index predates it — the common case, and
 *   3. the project was never indexed at all.
 *
 * Cases 2 and 3 are *repairable in one command*; case 1 is not. Collapsing
 * them into one opaque message means an agent that hits a stale index
 * reasonably concludes the whole subsystem is broken and silently falls back
 * to `grep` for the rest of the session — which is exactly what happened on
 * 2026-08-05 against an index whose newest entry was 92 days old while the
 * queried symbol had shipped that morning.
 *
 * The freshness signal is derived from node rows the caller has ALREADY
 * materialised for its own matching pass, so building the richer message
 * costs no extra query and nothing at all on the success path.
 *
 * @task T12068
 */

/** Minimum age, in days, before an index is called out as stale. */
const STALE_AFTER_DAYS = 7;

/** Milliseconds in a day. */
const MS_PER_DAY = 86_400_000;

/**
 * Structured detail attached to a symbol-miss error, so machine consumers
 * can branch on freshness without re-parsing the message text.
 */
export interface SymbolMissDetails {
  /** The symbol name that was searched for. */
  readonly symbol: string;
  /** Nexus project ID the lookup ran against. */
  readonly projectId: string;
  /** Number of symbol nodes present in the index. */
  readonly indexedSymbolCount: number;
  /** Most recent `indexed_at` across the index, or `null` when never indexed. */
  readonly lastIndexedAt: string | null;
  /**
   * MEDIAN `indexed_at` across the index — the age of the index *body*
   * rather than of its newest row. See {@link medianIndexedAt} for why the
   * maximum is not a usable freshness signal.
   */
  readonly medianIndexedAt: string | null;
  /** Whole days since {@link medianIndexedAt}, or `null` when never indexed. */
  readonly indexAgeDays: number | null;
  /** Coarse freshness classification, derived from {@link medianIndexedAt}. */
  readonly freshness: 'fresh' | 'stale' | 'never-indexed';
}

/** An `E_NOT_FOUND` error carrying {@link SymbolMissDetails}. */
export interface SymbolMissError extends Error {
  code: 'E_NOT_FOUND';
  details: SymbolMissDetails;
}

/**
 * Newest `indexed_at` across a set of node rows.
 *
 * Timestamps are stored as lexicographically-ordered ISO-ish strings
 * (`YYYY-MM-DD HH:MM:SS`), so a string comparison is a valid ordering and
 * avoids parsing every row.
 *
 * @param nodes - node rows already loaded by the caller.
 * @returns the maximum `indexed_at`, or `null` when no row carries one.
 *
 * @task T12068
 */
export function newestIndexedAt(nodes: ReadonlyArray<Record<string, unknown>>): string | null {
  let newest: string | null = null;
  for (const node of nodes) {
    const raw = node['indexedAt'] ?? node['indexed_at'];
    if (typeof raw !== 'string' || raw.length === 0) continue;
    if (newest === null || raw > newest) newest = raw;
  }
  return newest;
}

/**
 * MEDIAN `indexed_at` across a set of node rows.
 *
 * The **maximum** is not a usable freshness signal: an incremental run that
 * re-indexes a handful of touched files stamps a few rows with today's date
 * while the other 99% keep a months-old timestamp. Measured on this repo on
 * 2026-08-06 the newest row was 0 days old and the index still could not
 * resolve a symbol that had shipped the previous morning — because only 3 of
 * 24,095 rows carried the recent stamp and 14,151 were from three months
 * earlier.
 *
 * The median moves only once a real majority of the graph has been
 * re-indexed, which is the property a freshness claim needs.
 *
 * @param nodes - node rows already loaded by the caller.
 * @returns the median `indexed_at`, or `null` when no row carries one.
 *
 * @task T12068
 */
export function medianIndexedAt(nodes: ReadonlyArray<Record<string, unknown>>): string | null {
  const stamps: string[] = [];
  for (const node of nodes) {
    const raw = node['indexedAt'] ?? node['indexed_at'];
    if (typeof raw === 'string' && raw.length > 0) stamps.push(raw);
  }
  if (stamps.length === 0) return null;
  stamps.sort();
  return stamps[Math.floor(stamps.length / 2)] ?? null;
}

/**
 * Classify index freshness from a representative timestamp.
 *
 * Callers pass the MEDIAN (see {@link medianIndexedAt}), not the maximum.
 *
 * @param lastIndexedAt - representative `indexed_at`, or `null`.
 * @param now - current time in epoch ms (injectable for tests).
 * @returns freshness bucket and whole-day age (`null` age when never indexed).
 *
 * @task T12068
 */
export function classifyIndexFreshness(
  lastIndexedAt: string | null,
  now: number,
): { freshness: SymbolMissDetails['freshness']; indexAgeDays: number | null } {
  if (lastIndexedAt === null) return { freshness: 'never-indexed', indexAgeDays: null };
  // SQLite `datetime('now')` yields `YYYY-MM-DD HH:MM:SS` with no zone
  // designator; treat it as UTC rather than letting the host locale shift it.
  const normalized = lastIndexedAt.includes('T')
    ? lastIndexedAt
    : `${lastIndexedAt}Z`.replace(' ', 'T');
  const parsed = Date.parse(normalized);
  if (Number.isNaN(parsed)) return { freshness: 'stale', indexAgeDays: null };
  const indexAgeDays = Math.max(0, Math.floor((now - parsed) / MS_PER_DAY));
  return { freshness: indexAgeDays >= STALE_AFTER_DAYS ? 'stale' : 'fresh', indexAgeDays };
}

/**
 * Build the `E_NOT_FOUND` error thrown when a symbol lookup matches nothing.
 *
 * The message always names the repair command when one would help, so an
 * agent reading only the error text still knows what to do next.
 *
 * @param symbolName - the searched-for symbol.
 * @param projectId  - nexus project ID the lookup ran against.
 * @param nodes      - node rows the caller already loaded (used for freshness).
 * @param now        - current time in epoch ms (injectable for tests).
 * @returns an `Error` with `code = 'E_NOT_FOUND'` and {@link SymbolMissDetails}.
 *
 * @example
 * ```ts
 * if (matchingNodes.length === 0) {
 *   throw buildSymbolMissError(symbolName, projectId, projectSymbolNodes);
 * }
 * ```
 *
 * @task T12068
 */
export function buildSymbolMissError(
  symbolName: string,
  projectId: string,
  nodes: ReadonlyArray<Record<string, unknown>>,
  now: number = Date.now(),
): SymbolMissError {
  const lastIndexedAt = newestIndexedAt(nodes);
  const median = medianIndexedAt(nodes);
  const { freshness, indexAgeDays } = classifyIndexFreshness(median, now);

  const lines: string[] = [`No symbol found matching '${symbolName}' in project ${projectId}.`];

  if (freshness === 'never-indexed') {
    lines.push('This project has no code-intelligence index yet.', 'Fix: cleo nexus analyze');
  } else {
    const age =
      indexAgeDays === null ? `median entry ${median}` : `median entry ${indexAgeDays}d old`;
    lines.push(`Index holds ${nodes.length} symbols; ${age}, newest ${lastIndexedAt}.`);
    if (freshness === 'stale') {
      lines.push(
        `Most of this index is older than ${STALE_AFTER_DAYS}d, so a symbol added since then is MISSING from it — not absent from the code.`,
        'Fix: cleo nexus analyze   (check first with: cleo nexus status)',
      );
    } else {
      lines.push('The index is current — check the symbol spelling.');
    }
  }

  const err = new Error(lines.join('\n')) as SymbolMissError;
  err.code = 'E_NOT_FOUND';
  err.details = {
    symbol: symbolName,
    projectId,
    indexedSymbolCount: nodes.length,
    lastIndexedAt,
    medianIndexedAt: median,
    indexAgeDays,
    freshness,
  };
  return err;
}
