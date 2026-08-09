---
id: t12086-worktree-locate
tasks: [T12086]
kind: fix
summary: cleo worktree destroy reported worktreeRemoved/branchDeleted without acting — resolve path and branch from git, not by convention
---

```
$ cleo worktree destroy T11248 --force
{ "worktreeRemoved": true, "branchDeleted": true }
```

The directory, the git registration, and the branch were all still there. 23 worktrees were "destroyed" this way and none were removed. **This is how 42 worktrees accumulated** — the cleanup verb claimed to work, so nobody looked.

Both halves derived their target by convention instead of asking git:

1. `resolveTaskWorktreePath(computeProjectHash(projectRoot), taskId)` produces the CURRENT hash scheme. Worktrees provisioned under an earlier scheme live at a different directory, so `existsSync` was false and the code took its `else { worktreeRemoved = true // already gone }` branch.
2. `branch = \`task/${taskId}\`` — real branches carry a slug (`task/T11248-cleo-exodus`). The lookup missed, the delete was skipped, and `branchDeleted = true` was returned anyway.

New `worktree-locate.ts` reads `git worktree list --porcelain` — the authoritative registry — and returns the actual path, actual branch, and lock state. `destroyWorktree` uses those, prunes a stale registration instead of calling it "already gone", and reports `branchDeleted: false` **with a reason** when no branch matched. It now also tells the truth when it cannot act: `E_DESTROY_FAILED: Branch 'task/T11547' not found — nothing deleted` (that worktree is really named `T11547b`).

Result: 42 worktrees → 1. Every removal verified first — content present in main, CLEO task `done`, all uncommitted state archived. An orphaned 323-line design doc was rescued into the docs SSoT; an uncommitted `gc-subsystem.ts` draft was confirmed superseded by the version that shipped in `core/src/gc/`. 5.7 GB of banned-location sibling checkouts freed.
