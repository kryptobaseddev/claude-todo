---
id: t12107-t12108-files-commit-field-projection
tasks: [T12107, T12108]
kind: fix
summary: files: atom resolves against the sibling commit: sha first; cleo show --field transparently resolves full-projection fields like verification.gates
---

gh#1195: a `files:` evidence atom was checked only against the worktree and git refs, rejecting files that exist on the merged commit named by the sibling `commit:` atom (common in shared checkouts). Resolution is now commit tree → worktree → git refs, consistently at verify and complete, with failure messages naming every location checked. gh#1197: `cleo show --field /data/task/verification/gates` 404'd with a fix string implying the field doesn't exist; `--field` now transparently falls back to the full projection for `tasks.show`, and the boundary text states which fields live only in `--full`.
