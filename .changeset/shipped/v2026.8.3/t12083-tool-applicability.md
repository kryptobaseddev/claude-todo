---
id: t12083-tool-applicability
tasks: [T12083]
kind: fix
summary: no task could EVER be completed in a project without TypeScript — gate rigour now scales to the project's real toolchain
---

Found by dropping CLEO into a fresh plain-JavaScript repo and driving the whole lifecycle. A correct worker implemented a function, wrote a test, ran the suite, committed, and recorded `implemented` + `testsPassed`. Then `cleo complete` refused:

```
Error: Task T003 failed verification gates: qaPassed (45)
```

`qaPassed` requires `tool:typecheck`, whose node language default is `npx tsc --noEmit` — which in a project with no TypeScript answers *"This is not the tsc command you are looking for"* and exits 1. Same for `tool:lint` → `npx biome check .`. **In any project lacking a typechecker and a linter the gate is unsatisfiable, so no task can ever be completed however correct the work**, and the autonomous loop runs `failure → backoff → backoff` on work that is finished and committed.

The comment on those defaults claimed they exist so "a fresh project still gets a working default". They are not working defaults — they are guesses about a project, and in a bare project the guess is wrong.

The fix is an asymmetry: a command the operator **declared** (`typecheck.command` in `project-context.json`) always runs; a command CLEO **guessed** runs only when the project shows evidence of that toolchain (config file, `package.json` script of that name, or matching dependency). Otherwise resolution returns the new `E_TOOL_NOT_APPLICABLE` and the evidence layer records a first-class `notApplicable` atom **with its reason** — the gate is satisfied by absence and the audit trail says so, rather than implying a tool ran. A project that later adopts TypeScript is held to it automatically.

Rigour here is unchanged: cleocode has `tsconfig.json`, `biome.json`, and both scripts, so every gate still bites. Verified in both directions.

The full drop-in chain went from 8/15 to 15/15 checks: init → nexus analyze → nexus impact on unseen symbols → saga/epic/tasks → three unattended tick→worker→commit→evidence→complete cycles → BRAIN observations → dream cycle on local inference → paraphrase recall of a pattern it synthesised from its own work → nexus resolving a symbol that did not exist when CLEO arrived.
