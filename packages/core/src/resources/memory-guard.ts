/**
 * Machine-wide memory guard audit + repair (T12097).
 *
 * ## The gap this closes
 *
 * T12096 put a hard ceiling on tools CLEO spawns. It binds `tool:test` evidence
 * runs and nothing else. An agent that simply types
 *
 *     pnpm test          npx vitest run          cargo test
 *
 * never touches CLEO, so no CLEO-side bound applies. On 2026-08-10 that path
 * drove `app.slice` to 48.1 GiB against a `MemoryHigh` of exactly 48 GiB; the
 * kernel reclaimed hard, thrashed 7.7 GiB of zram, and the desktop locked up.
 * Notably there was NO OOM kill — a throttle-and-thrash freeze logs nothing at
 * all, which is why repeated OOM hunts found nothing.
 *
 * ## Why cgroups, and not environment variables
 *
 * The obvious mitigation — exporting `NODE_OPTIONS` / `VITEST_MAX_WORKERS` from
 * a shell profile — has a fatal property: **environment variables only bind
 * shells started after the edit.** Measured the same day: the five heaviest
 * terminal tabs had all started BEFORE the profile was written, so none of them
 * carried the caps, and the worst reached 37.3 GiB on its own.
 *
 * A cgroup limit on the enclosing slice has the opposite property. It is
 * enforced by the kernel, applies the instant it is set to processes that are
 * ALREADY running, and cannot be opted out of by a child process choosing its
 * own flags. It is the only layer that satisfies "the bound survives a shell
 * that was already open".
 *
 * ## What this module does
 *
 * Audits the guard and reports what is missing, with the numbers that justify
 * each verdict. It is deliberately advisory-by-default: writing memory limits
 * for a user's whole desktop session is the operator's decision, so
 * {@link buildMemoryGuardFixCommands} returns the commands rather than running
 * them, and the CLI runs them only under an explicit `--fix`.
 *
 * Linux/systemd only. Everywhere else the audit reports `supported: false`
 * rather than inventing a verdict it cannot substantiate.
 *
 * @task T12097
 * @see ADR-013 §9, `resources/spawn-wrapper.ts` (per-spawn scope limits)
 */

import { existsSync, readFileSync } from 'node:fs';
import { totalmem } from 'node:os';

/**
 * Fraction of total RAM above which the throttle should engage.
 *
 * 0.72 of 62.5 GiB ≈ 45 GiB, leaving ~17 GiB for the compositor, browser and
 * the rest of the session. The freeze happened with this at 0.77 (48/62.5),
 * which left too little for the desktop to stay responsive while the kernel
 * reclaimed inside the slice.
 */
export const MEMORY_HIGH_FRACTION = 0.72;

/**
 * Fraction of total RAM at which the kernel kills inside the slice instead of
 * letting the machine thrash.
 *
 * A cgroup-scoped kill loses one agent's work. Exhausting the machine loses
 * every session plus whatever the desktop was holding, so the hard wall is
 * worth having even though it is never meant to be reached.
 */
export const MEMORY_MAX_FRACTION = 0.9;

/** Slice that holds terminal tabs and everything an agent spawns in them. */
export const GUARDED_SLICE = 'app.slice';

/** One finding from the audit. */
export interface MemoryGuardFinding {
  /** Stable identifier, e.g. `memory-high-unset`. */
  readonly id: string;
  /** `ok` needs no action; `warn` is advisory; `fail` means unbounded. */
  readonly severity: 'ok' | 'warn' | 'fail';
  /** One-line statement of the finding. */
  readonly summary: string;
  /** The measurement behind the verdict, printed verbatim. */
  readonly evidence: string;
}

/** Result of {@link auditMemoryGuard}. */
export interface MemoryGuardAudit {
  /** False on non-Linux or when cgroup v2 is unavailable. */
  readonly supported: boolean;
  /** Total machine RAM in GiB, rounded to one decimal. */
  readonly totalRamGib: number;
  /** Current `MemoryHigh` in GiB, or `null` when unset/`infinity`. */
  readonly memoryHighGib: number | null;
  /** Current `MemoryMax` in GiB, or `null` when unset/`infinity`. */
  readonly memoryMaxGib: number | null;
  /** Recommended `MemoryHigh` in GiB for this machine. */
  readonly recommendedHighGib: number;
  /** Recommended `MemoryMax` in GiB for this machine. */
  readonly recommendedMaxGib: number;
  /** Findings, worst first. */
  readonly findings: readonly MemoryGuardFinding[];
  /** True when nothing is at `fail`. */
  readonly guarded: boolean;
}

/** cgroup v2 path for the guarded slice under the user manager. */
function guardedSliceCgroupPath(uid: number = process.getuid?.() ?? 1000): string {
  return `/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service/${GUARDED_SLICE}`;
}

/**
 * Read a cgroup memory knob in GiB.
 *
 * @param dir - cgroup directory.
 * @param file - knob filename (`memory.high` / `memory.max`).
 * @returns GiB, or `null` when absent, unreadable, or `max` (no limit).
 */
function readLimitGib(dir: string, file: string): number | null {
  try {
    const raw = readFileSync(`${dir}/${file}`, 'utf8').trim();
    if (raw === 'max' || raw === '') return null;
    const bytes = Number(raw);
    if (!Number.isFinite(bytes) || bytes <= 0) return null;
    return Number((bytes / 1024 ** 3).toFixed(1));
  } catch {
    return null;
  }
}

/**
 * Audit the machine's memory guard.
 *
 * Read-only. Never throws — an unreadable cgroup yields `supported: false`
 * rather than a wrong verdict.
 *
 * @param opts - injectable measurements for deterministic tests.
 * @returns the audit.
 *
 * @example
 * ```ts
 * const a = auditMemoryGuard();
 * if (!a.guarded) for (const f of a.findings) console.error(f.summary);
 * ```
 *
 * @task T12097
 */
export function auditMemoryGuard(
  opts: { totalRamBytes?: number; cgroupDir?: string; platform?: NodeJS.Platform } = {},
): MemoryGuardAudit {
  const platform = opts.platform ?? process.platform;
  const totalBytes = opts.totalRamBytes ?? totalmem();
  const totalRamGib = Number((totalBytes / 1024 ** 3).toFixed(1));
  const recommendedHighGib = Math.floor(totalRamGib * MEMORY_HIGH_FRACTION);
  const recommendedMaxGib = Math.floor(totalRamGib * MEMORY_MAX_FRACTION);

  const dir = opts.cgroupDir ?? guardedSliceCgroupPath();
  const supported = platform === 'linux' && existsSync(dir);

  if (!supported) {
    return {
      supported: false,
      totalRamGib,
      memoryHighGib: null,
      memoryMaxGib: null,
      recommendedHighGib,
      recommendedMaxGib,
      findings: [
        {
          id: 'unsupported',
          severity: 'warn',
          summary: `Cannot audit the memory guard on this system — ${GUARDED_SLICE} cgroup not found.`,
          evidence: `platform=${platform} cgroupDir=${dir} exists=${existsSync(dir)}`,
        },
      ],
      guarded: false,
    };
  }

  const memoryHighGib = readLimitGib(dir, 'memory.high');
  const memoryMaxGib = readLimitGib(dir, 'memory.max');
  const findings: MemoryGuardFinding[] = [];

  if (memoryHighGib === null) {
    findings.push({
      id: 'memory-high-unset',
      severity: 'fail',
      summary: `${GUARDED_SLICE} has no MemoryHigh — a runaway test run can consume the whole machine and freeze the desktop.`,
      evidence: `memory.high=max, total=${totalRamGib} GiB, recommended=${recommendedHighGib} GiB`,
    });
  } else if (memoryHighGib > recommendedHighGib) {
    findings.push({
      id: 'memory-high-too-permissive',
      severity: 'warn',
      summary: `${GUARDED_SLICE} MemoryHigh leaves too little for the desktop; it will still thrash before throttling helps.`,
      evidence:
        `memory.high=${memoryHighGib} GiB of ${totalRamGib} GiB total ` +
        `(recommended ≤ ${recommendedHighGib} GiB, i.e. ${Math.round(MEMORY_HIGH_FRACTION * 100)}%). ` +
        `Measured 2026-08-10: the slice peaked at 48.1 GiB against MemoryHigh=48 GiB and the session locked up.`,
    });
  } else {
    findings.push({
      id: 'memory-high-ok',
      severity: 'ok',
      summary: `${GUARDED_SLICE} MemoryHigh is set and leaves headroom for the desktop.`,
      evidence: `memory.high=${memoryHighGib} GiB of ${totalRamGib} GiB (≤ ${recommendedHighGib} GiB recommended)`,
    });
  }

  if (memoryMaxGib === null) {
    findings.push({
      id: 'memory-max-unset',
      severity: 'warn',
      summary: `${GUARDED_SLICE} has no MemoryMax — without a hard wall the kernel thrashes instead of killing one offender.`,
      evidence: `memory.max=max, recommended=${recommendedMaxGib} GiB`,
    });
  } else {
    findings.push({
      id: 'memory-max-ok',
      severity: 'ok',
      summary: `${GUARDED_SLICE} MemoryMax is set — the kernel kills inside the slice rather than exhausting the machine.`,
      evidence: `memory.max=${memoryMaxGib} GiB of ${totalRamGib} GiB`,
    });
  }

  const order = { fail: 0, warn: 1, ok: 2 } as const;
  findings.sort((a, b) => order[a.severity] - order[b.severity]);

  return {
    supported: true,
    totalRamGib,
    memoryHighGib,
    memoryMaxGib,
    recommendedHighGib,
    recommendedMaxGib,
    findings,
    guarded: !findings.some((f) => f.severity === 'fail'),
  };
}

/**
 * The commands that would apply the recommended guard.
 *
 * Returned rather than executed so the operator can read them first — these
 * change memory limits for their entire desktop session, and
 * `systemctl set-property` persists a drop-in under `~/.config/systemd/`.
 *
 * @param audit - a prior {@link auditMemoryGuard} result.
 * @returns argv arrays, in order. Empty when nothing needs changing.
 *
 * @task T12097
 */
export function buildMemoryGuardFixCommands(audit: MemoryGuardAudit): readonly string[][] {
  if (!audit.supported) return [];
  const cmds: string[][] = [];
  const needsHigh = audit.memoryHighGib === null || audit.memoryHighGib > audit.recommendedHighGib;
  if (needsHigh) {
    cmds.push([
      'systemctl',
      '--user',
      'set-property',
      GUARDED_SLICE,
      `MemoryHigh=${audit.recommendedHighGib}G`,
    ]);
  }
  if (audit.memoryMaxGib === null) {
    cmds.push([
      'systemctl',
      '--user',
      'set-property',
      GUARDED_SLICE,
      `MemoryMax=${audit.recommendedMaxGib}G`,
    ]);
  }
  return cmds;
}
