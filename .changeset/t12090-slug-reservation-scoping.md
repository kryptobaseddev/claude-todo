---
id: t12090-slug-reservation-scoping
tasks: [T12090]
kind: fix
summary: the macOS-only E_SLUG_RESERVED flake was a process-global reservation set — keyed by slug alone, so CLEO_DIR isolation never isolated it
---

`docs-memory-observation.test.ts` failed on macos-latest shard 1 with `E_SLUG_RESERVED` for a slug it had never used, and passed on re-run. Nothing was wrong with macOS.

`reservedSlugs` was a module-level `Set<string>` keyed by the normalised slug ALONE — process-global. Vitest reuses a worker across files, so a file that reserved a slug and never consumed it left it reserved for every later file in that worker, no matter how carefully each set its own `CLEO_DIR`. The module even shipped `_resetSlugAllocatorState_TESTING_ONLY` to paper over this, which only helps files that remember to call it. Shard composition differs per platform, so only macOS happened to order the files that way — the classic signature of shared state mistaken for a platform bug.

Reservations are now keyed by resolved project root, so `CLEO_DIR` isolation is real and the reset hook is a convenience rather than a correctness requirement. `cwd` is threaded through the attachment-store check and the changeset writer's three release paths.
