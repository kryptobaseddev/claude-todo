---
id: t12089-release-open-forwards-scope
tasks: [T12089]
kind: fix
summary: cleo release open could not cut ANY release — it dispatched only `version`, so the workflow planned with no scope and exited 2 at Prepare bump-PR
---

`cleo release open` sent exactly one input: `version`. With no `plan-blob-sha256`, `release-prepare.yml` takes its "generate a fresh plan" branch and runs:

```bash
cleo release plan "$VERSION" "${EPIC_ARGS[@]}" --json > "$PLAN_FILE"
```

`EPIC_ARGS` is empty unless an `epic` input was supplied — and `cleo release plan` requires `--saga | --epic | --tasks`. So it exited 2 and **every release died at *Prepare bump-PR***, after lint, typecheck, both test shards and build had all passed. The code was fine; the pipeline could not ship it.

`--epic` was not a workaround either: an epic drags in sibling tasks that legitimately have no evidence yet, failing the plan with `E_EVIDENCE_INSUFFICIENT` (22 such tasks on the epic used here).

**Changes**

- `release-prepare.yml` + its template gain a `tasks` input (comma-separated IDs) for task-scoped releases; both scope inputs are forwarded to `cleo release plan`, and a missing scope now fails with a readable reason instead of surfacing an argparse error from a nested command.
- `cleo release open` gains `--epic` / `--tasks` and forwards them as workflow inputs. `plan-blob-sha256` is still deliberately NOT forwarded — the verify branch needs the plan FILE in the workflow checkout and `.cleo/` is gitignored, so the hash alone cannot be validated there; `--commit-plan` is that path.

**Test-gap note:** the existing `release-open-field-schema` parity case dispatches *without* a scope, so `epic`/`tasks` never appeared among the passed keys and an undeclared input would have sailed through to a live HTTP 422 — the exact failure that test exists to prevent. Two cases added: one asserting the scope rides along AND that both keys are declared in the real workflow YAML, one asserting empty scope values are omitted rather than sent as empty inputs.

**Follow-up (same task):** the dispatch layer was a THIRD chokepoint. `packages/cleo/src/dispatch/domains/release.ts` maps params to `ReleaseOpenOptions` explicitly, so `--tasks` reached the CLI, was accepted, and was then silently dropped before `releaseOpen` ever saw it — the dispatched workflow again had no scope. Verified by the new guard firing in CI with the exact message it was written to produce ("No release scope supplied") rather than a nested argparse error. Adding an option to core + the CLI is not sufficient; every explicit mapping between them must carry it.

