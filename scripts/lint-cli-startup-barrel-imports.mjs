#!/usr/bin/env node
/**
 * Gate: ratchet down STATIC core-barrel imports in the CLI (T12076).
 *
 * ## Why (measured, not assumed)
 *
 * Every `cleo` invocation pays ~2.4 s before doing any work. The cause is not
 * the command being run — `cleo version` touches no database and still pays it.
 * Measured on 2026-08-10:
 *
 *   bare `node -e 1`                              0.01 s
 *   `cleo version` (wall)                         2.5 – 3.0 s
 *   importing the CLI entry graph alone           2.71 s   ← the whole tax
 *   importing `@cleocode/core` (main barrel)      2.54 s   ← nearly all of it
 *   importing `@cleocode/core/internal`           2.27 s
 *   importing ONE deep module (build-command-groups) 0.12 s
 *
 * `packages/core/dist` contains **1266 ESM files**; a CPU profile of the barrel
 * import attributes ~1.8 s to module machinery (V8 compile plus
 * `package_json_reader` resolution), not to any single slow function. So the cost
 * is proportional to how much of core is reachable at load, and a barrel makes
 * ALL of it reachable.
 *
 * `cli/index.ts` already lazy-loads the barrel via `await import()` and documents
 * why. That effort is defeated by static imports elsewhere in the bundle: the
 * moment any bundled module does `import … from '@cleocode/core'`, the whole
 * graph loads anyway.
 *
 * ## What this gate does
 *
 * Counts static barrel imports under `packages/cleo/src/**` (excluding tests) and
 * fails when the count RISES. It does not demand zero today — there are 106 of
 * them and converting one at a time is how you get a half-migrated codebase and a
 * `EnvironmentTeardownError` (which is exactly what happened when one site was
 * converted in isolation; see the T12076 revert). The gate exists so the number
 * can only move down, and so the next person sees the measurement rather than
 * rediscovering it.
 *
 * Lower the baseline in the same PR that removes imports. `--update-baseline`
 * rewrites it.
 *
 * @task T12076
 */

import { existsSync, globSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const REPO = process.cwd();
const BASELINE = 'scripts/.lint-cli-startup-barrel-baseline.json';

/** Barrel specifiers whose import pulls a large share of `@cleocode/core`. */
const BARRELS = ['@cleocode/core', '@cleocode/core/internal'];

/** Static (non-`await import`) barrel imports, excluding tests. */
function collect() {
  const hits = [];
  const files = globSync('packages/cleo/src/**/*.ts', { cwd: REPO });
  for (const rel of files) {
    if (/__tests__|\.test\.ts$|\.spec\.ts$/.test(rel)) continue;
    const src = readFileSync(join(REPO, rel), 'utf8');
    const lines = src.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // Only STATIC top-level imports. `await import('…')` is the desired form
      // and must never be counted as a violation.
      const m = line.match(/^import\s[^;]*?from\s+'([^']+)'/);
      if (!m) continue;
      if (!BARRELS.includes(m[1])) continue;
      hits.push({ file: rel, line: i + 1, specifier: m[1] });
    }
  }
  return hits;
}

const hits = collect();
const asJson = process.argv.includes('--json');
const update = process.argv.includes('--update-baseline') || process.argv.includes('--baseline');

if (update) {
  writeFileSync(
    join(REPO, BASELINE),
    `${JSON.stringify(
      {
        _comment:
          'Static @cleocode/core barrel imports in packages/cleo/src (T12076). ' +
          'Each one forces the full 1266-module core graph to load at CLI startup. ' +
          'This number may only go DOWN. Lower it in the same PR that removes imports.',
        total: hits.length,
      },
      null,
      2,
    )}\n`,
  );
  process.stdout.write(`lint-cli-startup-barrel-imports: baseline set to ${hits.length}\n`);
  process.exit(0);
}

let baseline = Number.POSITIVE_INFINITY;
if (existsSync(join(REPO, BASELINE))) {
  try {
    baseline = JSON.parse(readFileSync(join(REPO, BASELINE), 'utf8')).total;
  } catch {
    baseline = Number.POSITIVE_INFINITY;
  }
}

if (asJson) {
  process.stdout.write(`${JSON.stringify({ total: hits.length, baseline, hits }, null, 2)}\n`);
  process.exit(hits.length > baseline ? 1 : 0);
}

if (hits.length > baseline) {
  process.stderr.write(
    `lint-cli-startup-barrel-imports: FAIL — ${hits.length} static core-barrel import(s), ` +
      `baseline ${baseline}.\n\n` +
      `Each one makes the full 1266-module @cleocode/core graph load before any command runs.\n` +
      `Measured: importing that barrel costs 2.54 s; a deep subpath module costs 0.12 s.\n\n` +
      `Use a deep import (\`@cleocode/core/<dir>/<module>\` — the './*' export permits it)\n` +
      `or \`await import()\` inside the handler.\n\nNew since baseline:\n`,
  );
  for (const h of hits.slice(baseline)) {
    process.stderr.write(`  • ${h.file}:${h.line} imports '${h.specifier}'\n`);
  }
  process.exit(1);
}

const trend = hits.length < baseline ? ` (down from ${baseline} — lower the baseline)` : '';
process.stdout.write(
  `lint-cli-startup-barrel-imports: OK — ${hits.length} static core-barrel import(s)${trend}.\n`,
);
