---
id: t12094-t12097-ci-dispatch-and-memory-guard
tasks: [T12094, T12097]
kind: fix
summary: bump-PRs opened with zero checks and could never merge; and tests an agent runs itself bypassed every CLEO memory ceiling
---

**T12094** — GitHub does not trigger workflows for events caused by GITHUB_TOKEN. release-prepare pushes the branch and opens the PR with exactly that token, so the bump-PR arrived with NO checks while branch protection requires the `CI` context. Both v2026.8.3 and v2026.8.4 needed a human to push a throwaway commit to wake CI. Fixed: `ci.yml` gains `workflow_dispatch` and release-prepare dispatches it for the branch after opening the PR; the check runs land on the branch-tip SHA, which is the PR head. Also gave `dorny/paths-filter` an explicit `base` for that event only — without it every filter reports false, every job skips, and the aggregate `CI` passes vacuously.

**T12097** — T12096 bounds tools CLEO spawns; it cannot bound `pnpm test` typed by an agent, because CLEO is not in that process tree. Env vars are not a fix: they bind only shells started afterwards, and the five heaviest tabs on 2026-08-10 all predated the profile edit. Only a cgroup limit binds already-running processes. `cleo doctor memory-guard` audits it and `--fix` applies RAM-derived limits (MemoryHigh 72%, MemoryMax 90%), so a 16 GiB laptop is not handed a 45 GiB ceiling. Proven live: MemoryHigh applied to a scope 12 minutes after its creation took effect immediately, and a bare `node -e` allocation was accounted to the guarded slice.
