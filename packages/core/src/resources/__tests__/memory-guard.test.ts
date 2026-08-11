/**
 * Machine-wide memory guard audit (T12097).
 *
 * Everything is injected — RAM, cgroup dir, platform — because an audit whose
 * verdict depends on the host running it is useless as a regression test, and
 * because the whole point of the module is to be right on machines that are NOT
 * this one.
 *
 * @task T12097
 */

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  auditMemoryGuard,
  buildMemoryGuardFixCommands,
  MEMORY_HIGH_FRACTION,
  MEMORY_MAX_FRACTION,
} from '../memory-guard.js';

const GIB = 1024 ** 3;
let dir: string;

/** Write a fake cgroup with the given knob values (`null` → `max`). */
function fakeCgroup(highGib: number | null, maxGib: number | null): string {
  writeFileSync(join(dir, 'memory.high'), highGib === null ? 'max' : String(highGib * GIB));
  writeFileSync(join(dir, 'memory.max'), maxGib === null ? 'max' : String(maxGib * GIB));
  return dir;
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cleo-memguard-'));
  mkdirSync(dir, { recursive: true });
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('auditMemoryGuard (T12097)', () => {
  const linux62 = { totalRamBytes: 62.5 * GIB, platform: 'linux' as NodeJS.Platform };

  it('FAILS when MemoryHigh is unset — that is the unbounded case', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(null, 56) });
    expect(a.guarded).toBe(false);
    expect(a.findings[0]?.id).toBe('memory-high-unset');
    expect(a.findings[0]?.severity).toBe('fail');
  });

  it('WARNS when MemoryHigh leaves too little for the desktop', () => {
    // The measured freeze: MemoryHigh=48 on 62.5 GiB. The slice peaked at 48.1
    // and the session locked up — set, but not low enough to matter.
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(48, 56) });
    const f = a.findings.find((x) => x.id === 'memory-high-too-permissive');
    expect(f?.severity).toBe('warn');
    expect(f?.evidence).toContain('48.1');
    // A warn is advisory — it must NOT be reported as unbounded.
    expect(a.guarded).toBe(true);
  });

  it('passes at the recommended values', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(45, 56) });
    expect(a.guarded).toBe(true);
    expect(a.findings.every((f) => f.severity === 'ok')).toBe(true);
  });

  it('derives recommendations from RAM, so a small machine gets small limits', () => {
    const small = auditMemoryGuard({
      totalRamBytes: 16 * GIB,
      platform: 'linux',
      cgroupDir: fakeCgroup(null, null),
    });
    expect(small.recommendedHighGib).toBe(Math.floor(16 * MEMORY_HIGH_FRACTION));
    expect(small.recommendedMaxGib).toBe(Math.floor(16 * MEMORY_MAX_FRACTION));
    // Sanity: the throttle must sit strictly below the hard wall.
    expect(small.recommendedHighGib).toBeLessThan(small.recommendedMaxGib);
  });

  it('reports unsupported rather than inventing a verdict off-Linux', () => {
    const a = auditMemoryGuard({ totalRamBytes: 32 * GIB, platform: 'darwin' });
    expect(a.supported).toBe(false);
    expect(a.guarded).toBe(false);
    expect(a.findings[0]?.id).toBe('unsupported');
    // Must not claim to have read limits it could not read.
    expect(a.memoryHighGib).toBeNull();
    expect(a.memoryMaxGib).toBeNull();
  });

  it('treats a missing cgroup directory as unsupported, not as unguarded', () => {
    const a = auditMemoryGuard({
      ...linux62,
      cgroupDir: join(dir, 'does-not-exist'),
    });
    expect(a.supported).toBe(false);
  });

  it('orders findings worst-first so the first line is the actionable one', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(null, null) });
    expect(a.findings[0]?.severity).toBe('fail');
  });
});

describe('buildMemoryGuardFixCommands (T12097)', () => {
  const linux62 = { totalRamBytes: 62.5 * GIB, platform: 'linux' as NodeJS.Platform };

  it('emits both properties when nothing is set', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(null, null) });
    const cmds = buildMemoryGuardFixCommands(a);
    expect(cmds).toHaveLength(2);
    expect(cmds[0]?.join(' ')).toBe(
      `systemctl --user set-property app.slice MemoryHigh=${a.recommendedHighGib}G`,
    );
    expect(cmds[1]?.join(' ')).toContain(`MemoryMax=${a.recommendedMaxGib}G`);
  });

  it('emits NOTHING when the guard is already correct — idempotent', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(45, 56) });
    expect(buildMemoryGuardFixCommands(a)).toEqual([]);
  });

  it('tightens a too-permissive MemoryHigh but leaves a set MemoryMax alone', () => {
    const a = auditMemoryGuard({ ...linux62, cgroupDir: fakeCgroup(48, 56) });
    const cmds = buildMemoryGuardFixCommands(a);
    expect(cmds).toHaveLength(1);
    expect(cmds[0]?.join(' ')).toContain('MemoryHigh=45G');
  });

  it('proposes nothing on an unsupported system rather than a command that cannot work', () => {
    const a = auditMemoryGuard({ totalRamBytes: 32 * GIB, platform: 'win32' });
    expect(buildMemoryGuardFixCommands(a)).toEqual([]);
  });
});
