---
id: t12104-pr-atom-derive-provenance
tasks: [T12104]
kind: fix
summary: "pr: atom derives required checks from the target repo's branch protection; rejections print both sides and the list's source"
---

The `pr:<n>` evidence atom fell back to cleocode's own hardcoded gate list in consuming repos, rejecting every PR (gh#1192). Required-workflow resolution now inserts a live tier — the target repo's branch-protection required contexts via `gh api` (cached 1h under `.cleo/cache/evidence/`) — between the project-context override and the built-in default, which remains the offline fallback. The missing-workflows rejection now prints each required entry FOUND/NOT FOUND, the workflows that actually ran with conclusions, and which tier produced the list (gh#1198), instead of asserting the user's PR was at fault.
