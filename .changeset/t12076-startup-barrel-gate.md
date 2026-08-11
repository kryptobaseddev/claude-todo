---
id: t12076-startup-barrel-gate
tasks: [T12076]
kind: perf
summary: every cleo call paid 2.4s of startup — measured to the @cleocode/core barrel pulling all 1266 of core's dist modules; eager BPE table removed and a ratcheting gate added
---

Measured, not assumed: bare node 0.01s; `cleo version` 2.5-3.0s; importing the CLI entry graph alone 2.71s; importing `@cleocode/core` 2.54s; importing ONE deep module 0.12s. A CPU profile attributes ~1.8s to module machinery (V8 compile + package_json_reader) across core's **1266 dist files** — the cost is how much of core is reachable at load, and a barrel makes all of it reachable.

Two corrections to the task's stated cause: it is not specifically the contracts/zod graph (zod is 45ms), and an earlier timing that appeared to blame help-renderer for 2.77s was reading STALE pre-bundle artifacts.

Shipped here: the eager `getEncoding('cl100k_base')` BPE table build (156ms at module scope in core/llm/conversation.ts) is deferred to first use, keeping the API synchronous. Plus gate 10, which counts static core-barrel imports in the CLI (106 today) and fails when the number RISES — proven to catch a regression.

Deliberately NOT claimed: AC4 (<1s). Converting barrel imports one at a time caused an EnvironmentTeardownError and was reverted; the remaining 106 must move together.
