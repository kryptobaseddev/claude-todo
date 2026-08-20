/**
 * Tests for the no-active-session warning in validateGateVerify (gh#1194 / T12106).
 *
 * `cleo verify` is intentionally session-free (T9505) so crash-recovery
 * re-attestation works before a new session is started — the gate write MUST
 * succeed without a session. But `cleo complete` requires an active session,
 * so a write under strict enforcement with no active session MUST emit a loud
 * NON-fatal W_NO_ACTIVE_SESSION warning on the envelope meta.warnings channel
 * (stdout JSON contract stays pure), telling the agent that complete will
 * require a session and that recorded gates are preserved.
 *
 * Test matrix:
 * - Gate write with NO active session → success + W_NO_ACTIVE_SESSION warning
 * - Gate write WITH an active session → success + no warning
 * - View mode (no write) with no session → no warning
 *
 * These tests NEED strict session enforcement — `getEnforcementMode`
 * short-circuits to 'none' while `process.env.VITEST` is set, so it is
 * temporarily cleared (same pattern as tasks/__tests__/epic-enforcement.test.ts).
 *
 * @task T12106
 * @gh 1194
 */

import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  createSqliteDataAccessor,
  resetDbState,
  validateGateVerify,
} from '@cleocode/core/internal';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { drainWarnings } from '../../output.js';
import { startSession } from '../../sessions/index.js';
import { seedTasks } from '../../store/__tests__/test-db-helper.js';

const savedVitest = process.env.VITEST;
beforeAll(() => {
  delete process.env.VITEST;
});
afterAll(() => {
  if (savedVitest) process.env.VITEST = savedVitest;
});

/** Absolute project root for each test — recreated per test. */
let TEST_ROOT: string;

/** Real commit SHA used as `commit:` evidence for the implemented gate (T9245). */
let SEED_COMMIT_SHA: string;

/**
 * Minimal config that limits required gates to just `implemented` so tests
 * can write a single gate. Session enforcement is deliberately NOT disabled
 * (unlike gate-verify-hint.test.ts) — these tests exercise it.
 */
const MINIMAL_CONFIG = {
  enforcement: {
    acceptance: { mode: 'off' },
  },
  verification: {
    enabled: true,
    requiredGates: ['implemented'],
  },
  lifecycle: { mode: 'off' },
};

function initGitRepoWithCommit(taskFile: string): void {
  const git = (args: string[]): string => execFileSync('git', args, { cwd: TEST_ROOT }).toString();
  git(['init', '-q']);
  git(['config', 'user.name', 'gate-verify-no-session test']);
  git(['config', 'user.email', 'nosession@example.com']);
  git(['config', 'commit.gpgsign', 'false']);
  writeFileSync(join(TEST_ROOT, taskFile), 'seed\n');
  git(['add', taskFile]);
  git(['commit', '-q', '-m', 'seed']);
  SEED_COMMIT_SHA = git(['rev-parse', 'HEAD']).trim();
}

async function seedTask(taskId: string): Promise<void> {
  const accessor = await createSqliteDataAccessor(TEST_ROOT);
  await seedTasks(accessor, [
    {
      id: taskId,
      title: `Test task ${taskId}`,
      type: 'task',
      status: 'active',
      priority: 'medium',
      acceptance: ['AC1'],
      // T9245: declare an AC file so commit content-intersect can validate.
      files: ['seed.ts'],
    },
  ]);
  await accessor.close();
  resetDbState();
}

describe('validateGateVerify — no-active-session warning (gh#1194 / T12106)', () => {
  beforeEach(async () => {
    resetDbState();
    drainWarnings();
    TEST_ROOT = await mkdtemp(join(tmpdir(), 'cleo-gate-nosession-'));
    await mkdir(join(TEST_ROOT, '.cleo'), { recursive: true });
    await writeFile(join(TEST_ROOT, '.cleo', 'config.json'), JSON.stringify(MINIMAL_CONFIG));
    initGitRepoWithCommit('seed.ts');
  });

  afterEach(async () => {
    resetDbState();
    drainWarnings();
    await rm(TEST_ROOT, { recursive: true, force: true });
  });

  it('records the gate AND warns when no session is active (verify stays session-free)', async () => {
    await seedTask('T400');
    drainWarnings();

    const result = await validateGateVerify(TEST_ROOT, {
      taskId: 'T400',
      gate: 'implemented',
      value: true,
      evidence: `commit:${SEED_COMMIT_SHA};files:seed.ts`,
    });

    // The write succeeds — verify is session-free by design (T9505).
    expect(result.success).toBe(true);
    const data = result.data as Record<string, unknown>;
    expect(data.action).toBe('set_gate');

    // …but a loud non-fatal warning is pushed onto the envelope channel.
    const warnings = drainWarnings() ?? [];
    const hit = warnings.find((w) => w.code === 'W_NO_ACTIVE_SESSION');
    expect(hit).toBeDefined();
    expect(hit?.message).toContain('E_CLEO_SESSION_REQUIRED');
    expect(hit?.message).toContain('cleo session start');
    expect(hit?.message).toContain('preserved');
    expect(hit?.message).toContain('do NOT need re-verification');
  });

  it('emits NO warning when a session is active', async () => {
    await seedTask('T401');
    await startSession(TEST_ROOT, { name: 'Active work', scope: 'global' });
    resetDbState();
    drainWarnings();

    const result = await validateGateVerify(TEST_ROOT, {
      taskId: 'T401',
      gate: 'implemented',
      value: true,
      evidence: `commit:${SEED_COMMIT_SHA};files:seed.ts`,
    });

    expect(result.success).toBe(true);
    const warnings = drainWarnings() ?? [];
    expect(warnings.find((w) => w.code === 'W_NO_ACTIVE_SESSION')).toBeUndefined();
  });

  it('emits NO warning in view mode even without a session', async () => {
    await seedTask('T402');
    drainWarnings();

    const result = await validateGateVerify(TEST_ROOT, { taskId: 'T402' });

    expect(result.success).toBe(true);
    const data = result.data as Record<string, unknown>;
    expect(data.action).toBe('view');
    const warnings = drainWarnings() ?? [];
    expect(warnings.find((w) => w.code === 'W_NO_ACTIVE_SESSION')).toBeUndefined();
  });
});
