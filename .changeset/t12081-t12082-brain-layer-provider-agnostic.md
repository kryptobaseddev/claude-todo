---
id: t12081-t12082-brain-layer-provider-agnostic
tasks: [T12081, T12082]
kind: fix
summary: the brain layer runs on ANY machine — provider-agnostic dream cycle, cross-provider failover, keyless local-daemon admission
---

The entire background layer — consolidation, extraction, hygiene, the dream cycle — was dead on any machine whose first-choice provider failed, while free local inference answered on loopback in 24 ms.

**T12081** — `resolveDreamLlm` called `resolveAnthropicForRole`, which returns `null` for every non-anthropic provider: a provider-specific chokepoint inside an otherwise provider-agnostic system. It now falls through to the provider-agnostic `executeForRole`. Separately, the role executor rebuilt the endpoint from the provider default, rewriting every custom `baseUrl` (Ollama, LM Studio, vLLM, Azure) to the vendor's public API, which then rejected the local key with 401. The credential's own endpoint now wins, and `baseUrl` is carried through `CredentialResult` / `CredentialMetadataWire` instead of being dropped at the first hop.

**T12082** — four further defects, each individually sufficient to kill the layer:

1. **No failover.** `executeForRole` resolved ONE provider and returned `null` on any failure, so an openai Codex OAuth answering `400 'gpt-5.5-pro' is not supported when using Codex with a ChatGPT account` disabled everything. `classifyError` already computed `shouldFallback`; nothing read it. Now bounded failover (2 alternates) with the failed provider excluded from the retry resolution; a caller abort still gives up.
2. **A live local daemon could never be admitted.** `isProvisioned` is synchronous so it cannot probe, settling for "`OLLAMA_HOST` set OR a store entry"; liveness was then probed only for providers already in the provisioned set — circular. A provider that needs no key should not have to be declared, only to answer.
3. **The model was chosen from RAM alone.** 62 GB scored into the `gemma4:e4b` tier on a box holding `qwen2.5-coder:3b`, so the resolved tag 404s at the daemon — which reads as "local inference is broken" rather than "that tag is not pulled". The fit heuristic is now intersected with the installed set.
4. **A keyless provider could not produce a credential.** Every consumer gates on `credential != null`, so even once ollama won the scoring it died one step later advising `cleo llm login` — meaningless for a server accepting any bearer value. A `local-daemon` credential source is synthesised only when the daemon actually answers.

Also bounds the dream cycle's provider probe at 20 s: a dead credential does not fail fast, it retries, and an unbounded probe stalls the whole pass behind a chain that will never succeed.

Proven live with `llm.roles = {}` and no configuration: openai 400 → failover → `qwen2.5-coder:3b` answered in 1.78 s; dream cycle `completed` in 6.1 s across three consecutive runs.
