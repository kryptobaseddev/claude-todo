/**
 * `cleo doctor superseded-store` — answer "which database is the real one?".
 *
 * After the E6 dual-scope migration (ADR-068) a project's store is
 * `.cleo/cleo.db`, with task rows in PREFIXED tables (`tasks_tasks`, …). The
 * pre-migration `.cleo/tasks.db` is left on disk under the name that every doc,
 * ADR-013 §9 note, and `cleo restore backup --file tasks.db` invocation still
 * uses — and snapshots are written as `tasks-<ts>.db` while actually
 * snapshotting `cleo.db`. A 408 KB `tasks.db` therefore sits beside 58 MB files
 * bearing its own name, which reads exactly like a truncated live database.
 *
 * Measured 2026-08-09: an agent in a project with 1,123 healthy tasks looped on
 * "the current tasks.db is 417KB, much smaller than the backups (58MB) — maybe
 * it was rotated/rebuilt", and moved on to guessing the store might be
 * `llmtxt.db`. The data was fine. This command exists so that question costs one
 * call: it names the superseded file and PROVES which store is authoritative by
 * counting rows in both.
 *
 * Read-only. It never deletes anything — the recommendation is printed and the
 * operator decides.
 *
 * @task T12095
 * @see ADR-068 — dual-scope DB chokepoint
 */

import { getProjectRoot } from '@cleocode/core';
import { scanSupersededStores } from '@cleocode/core/doctor/superseded-store.js';
import { defineCommand } from '../lib/define-cli-command.js';
import { cliOutput } from '../renderers/index.js';

/**
 * `cleo doctor superseded-store` subcommand.
 *
 * Exits non-zero when at least one superseded file is present, so it can gate a
 * cleanup step in a script. A clean project exits 0 with an empty list.
 *
 * @task T12095
 */
export const doctorSupersededStoreCommand = defineCommand({
  meta: {
    name: 'superseded-store',
    description:
      'Report pre-dual-scope store files (.cleo/tasks.db, .cleo/brain.db) still on disk under ' +
      'their old LIVE names after the cleo.db migration, proving which store holds the data. ' +
      'Read-only — deletes nothing.',
  },
  args: {
    json: { type: 'boolean', description: 'Output as JSON' },
    human: { type: 'boolean', description: 'Force human-readable output' },
    quiet: { type: 'boolean', description: 'Suppress non-essential output' },
  },
  async run() {
    const result = scanSupersededStores(getProjectRoot());

    cliOutput(result, {
      command: 'doctor',
      operation: 'doctor.superseded-store.run',
    });

    if (result.entries.length > 0 && (process.exitCode === undefined || process.exitCode === 0)) {
      process.exitCode = 1;
    }
  },
});
