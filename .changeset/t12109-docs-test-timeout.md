---
id: t12109-docs-test-timeout
tasks: [T12109]
kind: test
summary: "docs-canonical-surface integration test — raise the spawned-CLI timeout from 30s to 120s and retry once on a timeout kill, so a loaded CI runner no longer fails the whole shard"
---

The 30s `spawnSync` cap in `runCli` was exceeded on ubuntu CI under full-shard load (PR #1203, run 32334556443) — the spawned `docs fetch` CLI returned status null and failed the shard while main stayed green. The cap is now 120s with a single retry when the child was killed by the timeout.
