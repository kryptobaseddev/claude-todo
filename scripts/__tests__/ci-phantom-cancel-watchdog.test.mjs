/**
 * Tests for scripts/ci-phantom-cancel-watchdog.mjs (T12103).
 *
 * Covers the phantom-cancel detection signature, the superseded-run guard,
 * the 7-day age guard, and dry-run mutation safety. All `gh` interaction is
 * dependency-injected via a fake exec function — no network, no CLI.
 *
 * @task T12103
 */

import { describe, expect, it } from 'vitest';
import {
  isLatestForTuple,
  isPhantomCancelJob,
  isPostJobCleanupStep,
  isWithinAgeWindow,
  MAX_AGE_DAYS,
  runWatchdog,
} from '../ci-phantom-cancel-watchdog.mjs';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const NOW = new Date('2026-08-20T12:00:00Z');

function makeRun(overrides = {}) {
  return {
    databaseId: 1001,
    workflowName: 'CI',
    workflowDatabaseId: 10,
    headBranch: 'feat/x',
    headSha: 'abc123',
    conclusion: 'cancelled',
    createdAt: '2026-08-20T10:00:00Z',
    number: 5,
    url: 'https://github.com/kryptobaseddev/cleo/actions/runs/1001',
    ...overrides,
  };
}

function makeStep(name, conclusion) {
  return { name, conclusion };
}

function makeJob(name, conclusion, steps) {
  return { databaseId: 1, name, conclusion, steps };
}

const ALL_SUCCESS_STEPS = [
  makeStep('Checkout', 'success'),
  makeStep('Install', 'success'),
  makeStep('Test', 'success'),
  makeStep('Complete job', 'success'),
];

/**
 * Build a fake exec that serves `gh run list` from `runs` and `gh run view`
 * from `jobsByRunId`, and records every invocation. Rerun calls record into
 * `calls` but produce no output.
 */
function makeFakeExec({ runs, jobsByRunId }) {
  const calls = [];
  const exec = (argv) => {
    calls.push(argv);
    if (argv[0] === 'run' && argv[1] === 'list') return JSON.stringify(runs);
    if (argv[0] === 'run' && argv[1] === 'view') {
      const id = Number(argv[2]);
      return JSON.stringify({ jobs: jobsByRunId[id] ?? [] });
    }
    if (argv[0] === 'run' && argv[1] === 'rerun') return '';
    throw new Error(`unexpected argv: ${argv.join(' ')}`);
  };
  return { exec, calls };
}

// ---------------------------------------------------------------------------
// Phantom signature
// ---------------------------------------------------------------------------

describe('isPhantomCancelJob', () => {
  it('flags a cancelled job whose steps all succeeded', () => {
    expect(isPhantomCancelJob(makeJob('Reject Test', 'cancelled', ALL_SUCCESS_STEPS))).toBe(true);
  });

  it('treats skipped steps as benign', () => {
    const steps = [...ALL_SUCCESS_STEPS, makeStep('Deploy', 'skipped')];
    expect(isPhantomCancelJob(makeJob('CI', 'cancelled', steps))).toBe(true);
  });

  it('exempts post-job cleanup steps from the all-success rule', () => {
    const steps = [...ALL_SUCCESS_STEPS, makeStep('Post Run actions/checkout@v4', 'cancelled')];
    expect(isPhantomCancelJob(makeJob('CI', 'cancelled', steps))).toBe(true);
  });

  it('rejects a genuine mid-step cancel (failed step)', () => {
    const steps = [makeStep('Checkout', 'success'), makeStep('Test', 'failure')];
    expect(isPhantomCancelJob(makeJob('CI', 'cancelled', steps))).toBe(false);
  });

  it('rejects a genuine mid-step cancel (cancelled step)', () => {
    const steps = [makeStep('Checkout', 'success'), makeStep('Test', 'cancelled')];
    expect(isPhantomCancelJob(makeJob('CI', 'cancelled', steps))).toBe(false);
  });

  it('ignores jobs that did not conclude cancelled', () => {
    expect(isPhantomCancelJob(makeJob('CI', 'success', ALL_SUCCESS_STEPS))).toBe(false);
    expect(isPhantomCancelJob(makeJob('CI', 'failure', ALL_SUCCESS_STEPS))).toBe(false);
  });
});

describe('isPostJobCleanupStep', () => {
  it('matches GitHub post-step and complete-job names', () => {
    expect(isPostJobCleanupStep('Post Run actions/checkout@v4')).toBe(true);
    expect(isPostJobCleanupStep('Post Cache pnpm store')).toBe(true);
    expect(isPostJobCleanupStep('Complete job')).toBe(true);
    expect(isPostJobCleanupStep('Run tests')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Guards
// ---------------------------------------------------------------------------

describe('isLatestForTuple', () => {
  it('accepts the newest run for its (workflow, branch, sha) tuple', () => {
    const older = makeRun({ databaseId: 1001, number: 5 });
    const newer = makeRun({ databaseId: 1002, number: 6 });
    expect(isLatestForTuple(newer, [older, newer])).toBe(true);
  });

  it('rejects a run superseded by a newer attempt of the same tuple', () => {
    const older = makeRun({ databaseId: 1001, number: 5 });
    const newer = makeRun({ databaseId: 1002, number: 6 });
    expect(isLatestForTuple(older, [older, newer])).toBe(false);
  });

  it('does not treat a different sha or workflow as superseding', () => {
    const run = makeRun({ databaseId: 1001, number: 5 });
    const otherSha = makeRun({ databaseId: 1002, number: 6, headSha: 'def456' });
    const otherWorkflow = makeRun({ databaseId: 1003, number: 7, workflowDatabaseId: 99 });
    expect(isLatestForTuple(run, [run, otherSha, otherWorkflow])).toBe(true);
  });
});

describe('isWithinAgeWindow', () => {
  it('accepts a run inside the window and rejects one outside it', () => {
    expect(isWithinAgeWindow(makeRun({ createdAt: '2026-08-19T00:00:00Z' }), NOW)).toBe(true);
    expect(isWithinAgeWindow(makeRun({ createdAt: '2026-08-01T00:00:00Z' }), NOW)).toBe(false);
  });

  it(`window is ${MAX_AGE_DAYS} days`, () => {
    const edge = new Date(NOW.getTime() - MAX_AGE_DAYS * 24 * 60 * 60 * 1000).toISOString();
    expect(isWithinAgeWindow(makeRun({ createdAt: edge }), NOW)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// runWatchdog integration (fake exec)
// ---------------------------------------------------------------------------

describe('runWatchdog', () => {
  const phantomJobs = {
    1001: [makeJob('Reject Test', 'cancelled', ALL_SUCCESS_STEPS)],
  };

  it('reruns a phantom-cancelled run in execute mode', async () => {
    const runs = [makeRun({ databaseId: 1001 })];
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId: phantomJobs });
    const summary = await runWatchdog({ exec, dryRun: false, limit: 30, now: NOW });

    expect(summary.phantomRuns.map((p) => p.id)).toEqual([1001]);
    expect(summary.phantomRuns[0].phantomJobs).toEqual(['Reject Test']);
    expect(summary.rerun).toEqual([1001]);
    expect(calls.some((c) => c[0] === 'run' && c[1] === 'rerun' && c[2] === '1001')).toBe(true);
  });

  it('produces no mutations in dry-run mode', async () => {
    const runs = [makeRun({ databaseId: 1001 })];
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId: phantomJobs });
    const summary = await runWatchdog({ exec, dryRun: true, limit: 30, now: NOW });

    expect(summary.phantomRuns.map((p) => p.id)).toEqual([1001]);
    expect(summary.rerun).toEqual([]);
    expect(calls.some((c) => c[1] === 'rerun')).toBe(false);
  });

  it('skips a cancelled run with a genuine failed step', async () => {
    const runs = [makeRun({ databaseId: 1001 })];
    const jobsByRunId = {
      1001: [makeJob('Test', 'cancelled', [makeStep('Test', 'failure')])],
    };
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId });
    const summary = await runWatchdog({ exec, dryRun: false, limit: 30, now: NOW });

    expect(summary.phantomRuns).toEqual([]);
    expect(summary.skippedNotPhantom).toEqual([1001]);
    expect(calls.some((c) => c[1] === 'rerun')).toBe(false);
  });

  it('never resurrects a superseded run', async () => {
    const older = makeRun({ databaseId: 1001, number: 5 });
    const newer = makeRun({ databaseId: 1002, number: 6, conclusion: 'success' });
    const runs = [older, newer];
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId: phantomJobs });
    const summary = await runWatchdog({ exec, dryRun: false, limit: 30, now: NOW });

    expect(summary.skippedSuperseded).toEqual([1001]);
    expect(summary.rerun).toEqual([]);
    expect(calls.some((c) => c[1] === 'rerun')).toBe(false);
  });

  it('skips runs older than the age window', async () => {
    const runs = [makeRun({ databaseId: 1001, createdAt: '2026-08-01T00:00:00Z' })];
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId: phantomJobs });
    const summary = await runWatchdog({ exec, dryRun: false, limit: 30, now: NOW });

    expect(summary.skippedTooOld).toEqual([1001]);
    expect(calls.some((c) => c[1] === 'rerun')).toBe(false);
  });

  it('ignores non-cancelled runs entirely (no run view call)', async () => {
    const runs = [makeRun({ databaseId: 1001, conclusion: 'success' })];
    const { exec, calls } = makeFakeExec({ runs, jobsByRunId: {} });
    const summary = await runWatchdog({ exec, dryRun: false, limit: 30, now: NOW });

    expect(summary.cancelledRuns).toBe(0);
    expect(summary.phantomRuns).toEqual([]);
    expect(calls.some((c) => c[1] === 'view')).toBe(false);
  });
});
