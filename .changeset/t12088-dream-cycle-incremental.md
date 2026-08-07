---
id: t12088-dream-cycle-incremental
tasks: [T12088]
kind: fix
summary: the dream cycle re-processed its own window every pass, lost anything older than 24h forever, and could never start learning on a new project
---

The observation collector was a fixed window with no record of its own progress:

```sql
WHERE created_at >= (now - 24h) ORDER BY created_at ASC LIMIT 2000
```

Three consequences, all measured:

1. **Every pass redid the previous pass's work.** Consecutive runs collected 25 → 28 → 30 → 36 → 37 observations — the same material re-clustered and re-sent to the LLM each time. Dedup at the storage gate hid the waste while it consumed the entire LLM budget of every pass.
2. **Anything older than the window was consolidated NEVER, not later.** The sentient loop was dead for three months (T12077); every observation from that period aged out unread and became permanently invisible to consolidation. A memory system whose intake silently expires is not an "ever-growing memory".
3. **A fixed `clusterMinSize: 5` meant a new project could not learn at all.** A freshly dropped-in CLEO never has 5 similar observations, so the cycle completed `memoriesStored: 0` indefinitely. The goal is "infant to expert"; the threshold was set for the expert end and blocked the infant end.

Now: a persisted `SentientState.dreamWatermark` makes intake incremental; the watermark **widens** the window to catch up after an outage and never narrows below the nominal 24 h (clustering still needs context), capped at 30 days so one tick cannot swallow an entire corpus; and the minimum cluster size scales 2 → 5 with the size of the corpus.

Proven live: watermark absent → run 1 collected 38 observations; run 2 collected **1** (only the new digest). The watermark advances solely on the `completed` path, so a failed pass re-reads its material rather than skipping it, and an empty batch never advances progress past something it did not read.
