/**
 * SSoT for the isolated checkpoint repository's git directory (T12079).
 *
 * ## Why this is not `.git`
 *
 * CLEO keeps an isolated git repository under `.cleo/` to back checkpoints and
 * remote sync. It was created at `.cleo/.git`, and that one name broke every
 * freshly-initialised project:
 *
 * ```text
 * $ cleo init && git add -A
 * error: '.cleo/' does not have a commit checked out
 * error: unable to index file '.cleo/'
 * fatal: adding files failed
 * ```
 *
 * Git treats any directory containing `.git` as a repository boundary, and it
 * refuses to index an **untracked** nested repository that has no commits. A
 * newly-created checkpoint repo has none, and a fresh project's `.cleo/` is
 * entirely untracked — so `git add -A`, one of the most common commands there
 * is and the one every coding agent reaches for, failed outright.
 *
 * This repository is unaffected only by accident of history: its `.cleo/`
 * already contained COMMITTED files (`.cleo/.gitignore`, `adrs/**`) from before
 * the checkpoint repo existed, so git descends into it rather than treating it
 * as foreign. Nothing about the design guaranteed that.
 *
 * ### Why renaming is the right fix
 *
 * Git only auto-detects a repository from a directory named exactly `.git`.
 * Naming it `checkpoint.git` leaves `.cleo/` an ordinary directory, so:
 *
 *   - `git add -A` works in a fresh project;
 *   - selective tracking through `.cleo/.gitignore` keeps working (ADRs, specs
 *     and agent outputs stay trackable, which is why
 *     `removeCleoFromRootGitignore` deliberately refuses to blanket-ignore
 *     `.cleo/`);
 *   - nothing about the checkpoint repo's behaviour changes, because every
 *     access already goes through an explicit `GIT_DIR` / `--git-dir` rather
 *     than directory discovery.
 *
 * The alternatives were each tried and rejected: adding `.cleo/.git/` to the
 * host `.gitignore` does not help (git still sees the nested repo); ignoring
 * `.cleo/` wholesale works but contradicts selective tracking; and giving the
 * nested repo an initial commit would require `cleo init` to commit to the
 * user's repository.
 *
 * @task T12079
 */

import { existsSync, renameSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Directory name of the isolated checkpoint repository inside `.cleo/`.
 *
 * Deliberately NOT `.git` — see the module docs.
 */
export const CHECKPOINT_GIT_DIRNAME = 'checkpoint.git' as const;

/** Legacy name, migrated away from by {@link migrateCheckpointGitDir}. */
export const LEGACY_CHECKPOINT_GIT_DIRNAME = '.git' as const;

/**
 * Absolute path to the checkpoint repository's git directory.
 *
 * @param cleoDir - absolute path to the project's `.cleo/` directory.
 * @returns absolute path to the checkpoint git dir.
 *
 * @example
 * ```ts
 * const gitDir = checkpointGitDir('/repo/.cleo'); // → /repo/.cleo/checkpoint.git
 * ```
 *
 * @task T12079
 */
export function checkpointGitDir(cleoDir: string): string {
  return join(cleoDir, CHECKPOINT_GIT_DIRNAME);
}

/** Outcome of a migration attempt. */
export interface CheckpointGitMigration {
  /** Whether a legacy directory was renamed. */
  readonly migrated: boolean;
  /** Human-readable detail for scaffold reporting. */
  readonly detail: string;
}

/**
 * Move a legacy `.cleo/.git` to `.cleo/checkpoint.git`, preserving history.
 *
 * A plain rename is sufficient and lossless: the repository's objects, refs and
 * config are all inside the directory, and every CLEO access addresses it by an
 * explicit `GIT_DIR`, never by discovery. Existing checkpoint commits survive.
 *
 * Idempotent, and conservative when both exist — it will not clobber a
 * already-migrated directory.
 *
 * @param cleoDir - absolute path to the project's `.cleo/` directory.
 * @returns whether a rename happened, plus a reportable detail string.
 *
 * @task T12079
 */
export function migrateCheckpointGitDir(cleoDir: string): CheckpointGitMigration {
  const legacy = join(cleoDir, LEGACY_CHECKPOINT_GIT_DIRNAME);
  const target = checkpointGitDir(cleoDir);

  if (!existsSync(legacy)) {
    return { migrated: false, detail: 'No legacy .cleo/.git present' };
  }
  if (existsSync(target)) {
    // Both present — leave the legacy directory alone rather than risk
    // discarding either history. Surfaced so `cleo doctor` can flag it.
    return {
      migrated: false,
      detail: `Both .cleo/.git and .cleo/${CHECKPOINT_GIT_DIRNAME} exist — manual review required`,
    };
  }

  renameSync(legacy, target);
  return {
    migrated: true,
    detail: `Renamed .cleo/.git → .cleo/${CHECKPOINT_GIT_DIRNAME} so .cleo/ is not a git repository boundary`,
  };
}
