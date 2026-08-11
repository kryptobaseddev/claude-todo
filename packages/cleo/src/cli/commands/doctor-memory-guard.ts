/**
 * `cleo doctor memory-guard` — is this machine protected from a runaway test run?
 *
 * T12096 bounded the tools CLEO spawns. It does not — and cannot — bound a test
 * an agent runs itself (`pnpm test`, `npx vitest run`, `cargo test`), because
 * CLEO is not in that process tree at all. The only layer that covers it is a
 * cgroup limit on the slice holding the terminal, and unlike an environment
 * variable a cgroup limit binds shells that are ALREADY open.
 *
 * Read-only by default. `--fix` applies the recommended limits, which persists a
 * systemd drop-in affecting the whole desktop session — hence explicit opt-in.
 *
 * @task T12097
 */

import { spawnSync } from 'node:child_process';
import {
  auditMemoryGuard,
  buildMemoryGuardFixCommands,
} from '@cleocode/core/resources/memory-guard.js';
import { defineCommand } from '../lib/define-cli-command.js';
import { cliOutput } from '../renderers/index.js';

/**
 * `cleo doctor memory-guard` subcommand.
 *
 * Exits non-zero when the machine is unguarded, so it can gate a setup script.
 *
 * @task T12097
 */
export const doctorMemoryGuardCommand = defineCommand({
  meta: {
    name: 'memory-guard',
    description:
      'Audit the machine-wide memory guard that bounds test runs an agent starts OUTSIDE cleo ' +
      '(pnpm test / npx vitest). Read-only; --fix applies the recommended cgroup limits.',
  },
  args: {
    fix: {
      type: 'boolean',
      description:
        'Apply the recommended MemoryHigh/MemoryMax to app.slice. Persists a systemd user ' +
        'drop-in and affects the whole desktop session.',
    },
    json: { type: 'boolean', description: 'Output as JSON' },
    human: { type: 'boolean', description: 'Force human-readable output' },
    quiet: { type: 'boolean', description: 'Suppress non-essential output' },
  },
  async run({ args }) {
    const audit = auditMemoryGuard();
    const commands = buildMemoryGuardFixCommands(audit);

    const applied: { command: string; exitCode: number | null; stderr: string }[] = [];
    if (args.fix === true) {
      for (const argv of commands) {
        const [cmd, ...rest] = argv;
        // `cmd` is always a literal from buildMemoryGuardFixCommands — never
        // user input — so there is no injection surface here.
        const r = spawnSync(cmd as string, rest, { encoding: 'utf8' });
        applied.push({
          command: argv.join(' '),
          exitCode: r.status,
          stderr: (r.stderr ?? '').trim(),
        });
      }
    }

    // Re-audit after a fix so the reported state is what is actually in force,
    // not what was requested.
    const finalAudit = args.fix === true ? auditMemoryGuard() : audit;

    cliOutput(
      {
        ...finalAudit,
        fixApplied: args.fix === true,
        recommendedCommands: commands.map((c) => c.join(' ')),
        applied,
      },
      { command: 'doctor', operation: 'doctor.memory-guard.run' },
    );

    const failed = applied.some((a) => a.exitCode !== 0);
    if ((!finalAudit.guarded || failed) && (process.exitCode ?? 0) === 0) {
      process.exitCode = 1;
    }
  },
});
