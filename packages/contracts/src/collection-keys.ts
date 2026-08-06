/**
 * The keys under which CLEO payloads carry a list of records.
 *
 * ## Why this is a shared constant (T12077)
 *
 * Different operations name their collection differently — `tasks.list` emits
 * `tasks`, the SDK's generic list emits `items`, `tasks.find` emits `results`,
 * and `tasks.next` emits `suggestions`. Each consumer that wants "the rows"
 * has historically inlined its own guess, and each wrong guess fails SILENTLY,
 * because an absent key is indistinguishable from an empty result set.
 *
 * Three separate outages traced to exactly this:
 *
 * 1. **T12067** — `output-mode.ts` knew only `tasks`/`items`, in three
 *    separately-inlined lists. `cleo find … --output count` reported 1626
 *    while `--output id` reported `No ids.` against the same payload.
 * 2. **T12077 (this)** — `cleo next --output id` / `--output count` reported
 *    nothing and zero while the envelope held 836 candidates, because
 *    `suggestions` was in nobody's list.
 * 3. **T12077 (the severe one)** — `defaultPickTask` in the sentient loop read
 *    `response.data.tasks` from `cleo.tasks.find()`, which returns
 *    `{results, total}` *unwrapped*. The key was wrong AND the `data` envelope
 *    it was reaching through does not exist on the SDK surface, so
 *    `allCandidates` was **always `[]`**. The autonomous loop therefore
 *    returned `no-task` on every tick it had ever run — 24 ticks, 0 tasks
 *    picked, across three months — and looked exactly like "there is no work
 *    to do" rather than like a bug.
 *
 * The lesson those three share is that this list must exist in ONE place that
 * both the render layer and the SDK consumers import. Adding an operation with
 * a new collection key now means adding it here, once.
 *
 * @task T12077
 */

/**
 * Collection keys in resolution order.
 *
 * Order matters only when a payload carries more than one (it should not);
 * earlier keys win, which keeps the canonical `tasks` shape authoritative.
 */
export const COLLECTION_KEYS = ['tasks', 'items', 'results', 'suggestions'] as const;

/** A key under which a payload may carry its rows. */
export type CollectionKey = (typeof COLLECTION_KEYS)[number];
