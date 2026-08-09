---
id: t12092-changelog-and-committed-plan
tasks: [T12092]
kind: fix
summary: changelog emitted empty sections; --commit-plan silently committed nothing; and the workflow cannot re-derive a plan because CI has no tasks.db
---

Three defects found while trying to actually publish v2026.8.3.

**1. The changelog emitted empty sections.** Every Keep-a-Changelog heading rendered unconditionally, so a fix-only release shipped:

```
### Added

### Changed

### Fixed
- …
```

An empty heading under a shipped version reads as a forgotten section and teaches readers to skim past headings. Only sections with entries now render; the canonical ORDER — which is what the test was really protecting — is unchanged.

**2. `--commit-plan` committed nothing, silently.** The plan lives at `.cleo/release/<version>.plan.json` and `.cleo/` is gitignored, so `git add <path>` refuses it ("use -f if you really want to add them"). The commit then had nothing staged. Now force-added.

**3. The premise underneath both was wrong.** `commitPlanFile`'s doc claimed *"the workflow can re-derive the plan envelope from `releases` + tasks.db without it"*. It cannot: `.cleo/tasks.db` is deliberately gitignored (ADR-013 §9 — committing it is the T5158 data-loss vector), so a CI runner has **no task database** and `cleo release plan --tasks …` exits 4 (`E_NOT_FOUND`) there.

Proven by dispatching manually to isolate CLEO from `gh`: the scope arrived intact and the workflow built `SCOPE_ARGS+=(--tasks "T12081,…")` correctly, then `cleo release plan` exited 4.

So committing the plan is not an optional extra — it is the **only** way a task- or epic-scoped release can be planned. `plan-blob-sha256` is now forwarded exactly when `--commit-plan` was used, so the workflow VERIFIES the committed plan instead of regenerating one it cannot compute. Sending the hash without the file would fail verification; omitting it with the file present would pointlessly regenerate.
