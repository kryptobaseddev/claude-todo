---
id: t12095-superseded-store-diagnosis
tasks: [T12095]
kind: fix
summary: a healthy migrated project read as CORRUPT — three leftovers from the cleo.db migration sent an agent in circles over a 1123-task database that was completely intact
---

Post-E6 (ADR-068) the project store is `.cleo/cleo.db` with task rows in PREFIXED tables (`tasks_tasks`, …). Three artefacts conspire to say otherwise:

1. `.cleo/tasks.db` — the pre-migration store — is left on disk under the name every doc still uses for "live".
2. Snapshots are written `tasks-<ts>.db` while actually snapshotting `cleo.db`, so a 408 KB legacy file sits beside 58 MB files bearing its own name.
3. `cleo.db` keeps a bare, empty `tasks` table next to the populated `tasks_tasks`, so a direct SQL probe finds the decoy.

Measured in a real project: an agent looped on "the current tasks.db is 417KB which is much smaller than the backups (58MB) — maybe it was rotated/rebuilt", then began theorising the store might be `llmtxt.db`. The data was fine — 1,123 tasks, 106 sessions, an active session, 47 pending.

`cleo doctor superseded-store` answers it in one read-only call, naming each superseded file and proving which store holds the data by counting rows in both. It stays silent when `cleo.db` is absent, so it can never tell an operator to delete their only database, and it withholds the archive recommendation when the legacy file still holds rows. The injection template every agent reads now states where the data lives and warns against reasoning about `.db` file sizes.
