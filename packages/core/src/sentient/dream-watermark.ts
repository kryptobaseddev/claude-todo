/**
 * Incremental + adaptive consolidation policy for the dream cycle (T12088).
 *
 * ## What was fixed
 *
 * The collector was a fixed window with no memory of its own progress:
 *
 * ```sql
 * WHERE created_at >= (now - 24h) ORDER BY created_at ASC LIMIT 2000
 * ```
 *
 * Three consequences, all observed live on 2026-08-06:
 *
 * 1. **Every run redid the previous run's work.** Consecutive cycles collected
 *    25 → 28 → 30 → 36 → 37 observations — the same material re-clustered and
 *    re-sent to the LLM each time. Dedup at the storage gate hid it, so the
 *    waste was invisible while consuming the entire LLM budget of every pass.
 *
 * 2. **Anything older than the window was consolidated NEVER.** Not "later" —
 *    never. The sentient loop was dead for three months; every observation from
 *    that period aged out of the 24 h window unread and became permanently
 *    invisible to consolidation. A memory system whose intake silently expires
 *    is not an "ever-growing memory".
 *
 * 3. **A fixed `clusterMinSize: 5` meant a new project could not learn.** A
 *    freshly dropped-in CLEO has a handful of observations, never 5 similar
 *    ones, so the cycle completed with `memoriesStored: 0` indefinitely. The
 *    goal is that CLEO learns "like an infant to expert"; the threshold was set
 *    for the expert end and blocked the infant end entirely.
 *
 * ## The policy
 *
 * - **Watermark.** Consolidation records the newest `createdAt` it processed.
 *   The next run starts there, so work is never repeated.
 * - **The watermark widens, never narrows.** When it is older than the nominal
 *   lookback (daemon was off), the window reaches back to it instead of
 *   clamping to `now - 24h`. A gap is caught up, not dropped.
 * - **First run has no watermark**, so it uses the nominal lookback — existing
 *   behaviour, unchanged.
 * - **Adaptive minimum cluster size** scales with how much the project has
 *   actually observed, so a young project consolidates pairs while a mature one
 *   still demands real repetition before promoting a memory.
 *
 * @task T12088
 */

/** Nominal lookback when no watermark exists yet (24 h). */
export const DEFAULT_NOMINAL_LOOKBACK_MS = 24 * 60 * 60 * 1000;

/**
 * Hard ceiling on how far back a catch-up pass will reach (30 days).
 *
 * Without a bound, a watermark from months ago would pull an entire corpus into
 * one pass and spend the whole LLM budget on the first tick after a long
 * outage. Older material belongs to an explicit backfill, not a background tick.
 */
export const MAX_CATCHUP_LOOKBACK_MS = 30 * 24 * 60 * 60 * 1000;

/** Smallest cluster the adaptive policy will ever synthesise. */
export const MIN_ADAPTIVE_CLUSTER_SIZE = 2;

/** Largest cluster minimum the adaptive policy will ever demand. */
export const MAX_ADAPTIVE_CLUSTER_SIZE = 5;

/**
 * Observations per unit of required cluster size.
 *
 * At 20 observations the minimum is 2 (a young project can pair things up); by
 * 50 it reaches the mature default of 5, where a memory must be backed by real
 * repetition.
 */
export const ADAPTIVE_CLUSTER_DIVISOR = 10;

/**
 * Resolve the effective lookback for this pass.
 *
 * @param watermark - ISO timestamp of the newest observation already
 *   consolidated, or `null` on a first run.
 * @param nominalMs - the configured window (default 24 h).
 * @param nowMs - current time in ms (injected for determinism in tests).
 * @returns the lookback to use, always ≥ `nominalMs` and ≤
 *   {@link MAX_CATCHUP_LOOKBACK_MS}.
 *
 * @example
 * ```ts
 * // Daemon off for 5 days → widen to 5 days rather than losing 4 of them.
 * resolveLookbackMs('2026-08-01T00:00:00Z', DAY, Date.parse('2026-08-06T00:00:00Z'));
 * // → 5 * DAY
 * ```
 *
 * @task T12088
 */
export function resolveLookbackMs(
  watermark: string | null,
  nominalMs: number = DEFAULT_NOMINAL_LOOKBACK_MS,
  nowMs: number = Date.now(),
): number {
  if (watermark === null) return nominalMs;

  const marked = Date.parse(watermark);
  if (Number.isNaN(marked)) return nominalMs;

  // Never NARROW below the nominal window: a very recent watermark must not
  // shrink the pass to seconds and starve clustering of context.
  const widened = Math.max(nominalMs, nowMs - marked);
  return Math.min(widened, MAX_CATCHUP_LOOKBACK_MS);
}

/**
 * Minimum cluster size appropriate to the size of the observation corpus.
 *
 * @param totalObservations - how many observations exist in the window.
 * @returns a value in `[MIN_ADAPTIVE_CLUSTER_SIZE, MAX_ADAPTIVE_CLUSTER_SIZE]`.
 *
 * @example
 * ```ts
 * adaptiveClusterMinSize(6);   // → 2  (a young project can still learn)
 * adaptiveClusterMinSize(30);  // → 3
 * adaptiveClusterMinSize(500); // → 5  (mature: demand real repetition)
 * ```
 *
 * @task T12088
 */
export function adaptiveClusterMinSize(totalObservations: number): number {
  if (totalObservations <= 0) return MAX_ADAPTIVE_CLUSTER_SIZE;
  const scaled = Math.floor(totalObservations / ADAPTIVE_CLUSTER_DIVISOR);
  return Math.min(MAX_ADAPTIVE_CLUSTER_SIZE, Math.max(MIN_ADAPTIVE_CLUSTER_SIZE, scaled));
}

/**
 * Drop observations at or before the watermark.
 *
 * Applied AFTER collection so the widened window still supplies clustering
 * context, while synthesis effort concentrates on what is genuinely new. The
 * comparison is on the ISO `createdAt` string, which sorts lexicographically
 * for a fixed format — the same ordering the collector's `ORDER BY` relies on.
 *
 * @param observations - collected observations, any order.
 * @param watermark - ISO timestamp already consolidated, or `null`.
 * @returns observations strictly newer than the watermark.
 *
 * @task T12088
 */
export function selectUnconsolidated<T extends { createdAt: string }>(
  observations: readonly T[],
  watermark: string | null,
): T[] {
  if (watermark === null) return [...observations];
  return observations.filter((o) => o.createdAt > watermark);
}

/**
 * The newest `createdAt` in a batch — the watermark to persist after a pass.
 *
 * @param observations - observations processed in this pass.
 * @returns the max ISO timestamp, or `null` for an empty batch, leaving any
 *   existing watermark untouched so a no-op pass cannot advance progress past
 *   material it never read.
 *
 * @task T12088
 */
export function nextWatermark(observations: readonly { createdAt: string }[]): string | null {
  let max: string | null = null;
  for (const o of observations) {
    if (max === null || o.createdAt > max) max = o.createdAt;
  }
  return max;
}
