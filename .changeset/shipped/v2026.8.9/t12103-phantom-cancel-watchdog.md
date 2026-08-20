---
id: t12103-phantom-cancel-watchdog
tasks: [T12103]
kind: feat
summary: "CI phantom-cancel watchdog — detects workflow runs cancelled after all steps succeeded and auto-reruns them (scripts/ci-phantom-cancel-watchdog.mjs + scheduled workflow)"
---

Hosted runners have cancelled jobs whose every step succeeded (5 occurrences in 2 days; logs show the orphan-process reaper firing right before cancellation), and each occurrence cost a manual re-run that blocked the merge queue. The watchdog scans recent completed runs for the all-steps-success-then-cancelled signature and re-runs them, guarded by latest-run-only per (workflow, branch, sha) and a 7-day age window. Runs on a 15-minute schedule plus workflow_dispatch; --dry-run previews without mutating.
