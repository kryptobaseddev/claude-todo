---
id: t12100-pr-atom-override-guidance
tasks: [T12100]
kind: fix
summary: pr-atom missing-workflows error now names the CLEO_PR_REQUIRED_WORKFLOWS env var and release.prRequiredWorkflows config key
---

When a consuming repo's branch protection lacks the cleocode default gates (CI / Lockfile Check / Contracts Dep Lint), `pr:<num>` evidence failed with "required gates were skipped" and no hint of the override tiers added in T12014, leading users to conclude the list was hardcoded and work around it. The error now names both overrides.
