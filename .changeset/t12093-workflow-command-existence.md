---
id: t12093-workflow-command-existence
tasks: [T12093]
kind: fix
summary: release-prepare invoked TWO commands that never existed (cleo version-bump, cleo release changelog) — every dispatch died at exit 127 after a full green preflight
---

The release pipeline could not complete a single run since PR #868 (2026-05-31). `Prepare bump-PR` step 3 ran `cleo version-bump`, a verb absent from the CLI manifest, and step 4 ran `cleo release changelog`, a sub-verb `cleo release` does not have — so fixing the first would only have revealed the second, 21 minutes later.

Fixed at the root: gate 15 (`scripts/lint-workflow-cleo-commands.mjs`) resolves every `cleo` invocation in every workflow and rendered template against the command manifest, parsed from source, in 200ms. It reproduces both original failures.

Version bumping is now a `{{VERSION_BUMP_CMD}}` placeholder (project-agnostic `npm version` default; cleocode overrides it via `.cleo/release-config.json`), `scripts/version-all.mjs` normalises a leading `v` and skips non-package directories instead of half-bumping the workspace, the CHANGELOG step verifies rather than regenerating (`cleo release plan` already writes it), and the bump-PR body renders `meta.releaseNotes` instead of a raw schema envelope.
