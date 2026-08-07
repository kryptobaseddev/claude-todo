---
id: t12084-t12085-selfimprove-execute-and-model-pinning
tasks: [T12084, T12085]
kind: fix
summary: selfimprove --execute reported the wrong reason, fix-gen had no failover, and failover asked every substitute for the first provider's model
---

**T12084** — `--execute` had never been exercised, and was broken three ways:

1. **It reported a file nobody writes.** `E_NOT_FOUND: Patch file not found at …selfimprove-<scenario>.patch` — fix-gen is that file's only writer and is gated behind `CLEO_PI_RUNNER_ENABLED=1`. The loop had done its whole job (detected the regression, filed the DHQ) and then reported a failure naming a path the operator cannot create. The module docs already specified *"no patch ⇒ the egress guard skips the PR"* and the test was **named** `egress is a no-patch skip` while asserting `error`/`E_NOT_FOUND` — the assertion encoded the defect while the title stated the contract. Now a first-class `DraftPrSkipped { kind, reason }` naming the next action. The PR budget is still charged before the check, so `maxPrs = 0` still halts pre-flight.
2. **Fix-gen had no failover.** It does not route through `executeForRole`, so T12082's failover never reached it — it resolves via `resolveLLMForSystem` → `ModelRunner.build` → `session.send`. One chokepoint gaining failover does not help the callers of the other one. `excludeProviders` now threads through `resolveLLMForSystem`; fix-gen fails over up to 2 providers and logs provider/model/attempt.
3. **The candidate patch was written to the repo ROOT.** An untracked file there is exactly what T12007 swept onto a public branch via `git add -A`. Patches now live under `.cleo/selfimprove/<scenario>.patch` — gitignored, inspectable, not sweepable.

**T12085** — surfaced the moment a real anthropic credential existed:

```
anthropic  claude-fable-5 → 429     openai  claude-fable-5 → 400
ollama     claude-fable-5 → 404 model not found
```

A model id belongs to one provider. Carrying the caller's `modelOverride` across a failover asks each substitute for a model it has never heard of, so failover was guaranteed to fail for exactly the callers who pin a model — the ones who most need it. After a failover the substitute's own resolved model wins; the override applies only to the caller's first-choice provider.

Proven live end to end: `anthropic 429 → openai 400 → ollama/qwen2.5-coder:3b` authored a unified diff, `git apply` rejected it, and the egress refused to cut a PR — the designed guard working, `main` untouched.
