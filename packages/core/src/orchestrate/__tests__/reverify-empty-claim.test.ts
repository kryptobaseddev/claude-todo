/**
 * The re-verify gate must not reject a worker for making no file claim (T12080).
 *
 * ## The regression
 *
 * `runTick` builds its `WorkerReport` with `touchedFiles: []` — hardcoded,
 * because the spawn contract gives a worker exactly one return channel (an exit
 * code), so the loop cannot learn which files it touched. `compareFileSets`
 * then compared that empty claim against `git status --porcelain` and
 * mismatched on size (0 vs N) on EVERY run: after `cleo init` the working tree
 * is never clean, because CLEO's own scaffolding (`.cleo/`, `AGENTS.md`,
 * `.worktreeinclude`, …) is untracked.
 *
 * `runTick` was therefore **structurally incapable of returning `success`**.
 * Every correct worker was rejected, three rejections marked the task stuck,
 * and five stuck tasks self-paused the loop.
 *
 * It also inverted the intent: a worker following CLEO's own evidence protocol
 * COMMITS its work (ADR-051 wants a `commit:<sha>` atom), which removes those
 * paths from `git status` entirely. The check punished exactly the behaviour
 * the protocol requires.
 *
 * The anti-fabrication control is preserved wherever it can actually work — a
 * caller that DOES supply a claim still gets the full comparison.
 *
 * @task T12080
 */

import { describe, expect, it } from 'vitest';
import { reVerifyWorkerReport, type WorkerReport } from '../worker-verify.js';

/** A report shaped like the one `runTick` builds. */
function report(over: Partial<WorkerReport> = {}): WorkerReport {
  return {
    taskId: 'T003',
    selfReportSuccess: true,
    evidenceAtoms: ['tool:test'],
    touchedFiles: [],
    ...over,
  } as WorkerReport;
}

/** Options with both ground-truth probes stubbed. */
function opts(over: { tests?: boolean; files?: string[] } = {}) {
  return {
    projectRoot: '/tmp/irrelevant',
    runProjectTests: async () => ({ ok: over.tests ?? true }),
    listChangedFiles: async () => over.files ?? ['.cleo/', 'AGENTS.md', '.worktreeinclude'],
  };
}

describe('reVerifyWorkerReport — empty file claim (T12080)', () => {
  it('ACCEPTS when the loop supplied no file claim and tests pass', async () => {
    // The exact production shape: touchedFiles: [] from runTick, against a
    // dirty tree full of CLEO scaffolding.
    const verdict = await reVerifyWorkerReport(report(), opts());
    expect(verdict.accepted).toBe(true);
    expect(verdict.mismatches).toEqual([]);
  });

  it('still REJECTS when the real test suite fails', async () => {
    // The check that matters — ground truth, not a self-report — is intact.
    const verdict = await reVerifyWorkerReport(report(), opts({ tests: false }));
    expect(verdict.accepted).toBe(false);
    expect(verdict.mismatches.join(' ')).toContain('tests');
  });

  it('still REJECTS a worker claiming success with zero evidence atoms', async () => {
    const verdict = await reVerifyWorkerReport(report({ evidenceAtoms: [] }), opts());
    expect(verdict.accepted).toBe(false);
    expect(verdict.mismatches.join(' ')).toContain('evidence');
  });

  it('still compares file sets when a claim IS supplied', async () => {
    // Anti-fabrication preserved: a caller that names files must name the
    // right ones.
    const verdict = await reVerifyWorkerReport(
      report({ touchedFiles: ['src/nope.ts'] }),
      opts({ files: ['src/calc.ts'] }),
    );
    expect(verdict.accepted).toBe(false);
    expect(verdict.mismatches.join(' ')).toContain('files');
  });

  it('accepts a claim that matches the actual set', async () => {
    const verdict = await reVerifyWorkerReport(
      report({ touchedFiles: ['src/calc.ts'] }),
      opts({ files: ['src/calc.ts'] }),
    );
    expect(verdict.accepted).toBe(true);
  });

  it('a committed change leaves a clean tree and is not treated as "did nothing"', async () => {
    // A worker following ADR-051 commits its work, so its paths vanish from
    // `git status`. With no claim to compare, that must not be a rejection.
    const verdict = await reVerifyWorkerReport(report(), opts({ files: [] }));
    expect(verdict.accepted).toBe(true);
  });
});
