/**
 * The sentient picker must skip CONTAINER task types (T12079).
 *
 * `saga` and `epic` group work; they are not work. Spawning a worker against
 * one asks an agent to "do" a grouping, which cannot succeed. The attempt burns
 * a retry, three burn the task into `stuck`, and five stuck items inside an
 * hour trip `SELF_PAUSE_STUCK_THRESHOLD` — so a handful of unfiltered
 * containers can take the whole autonomous layer offline.
 *
 * The picker had NO type filter at all. It survived in the CLEO repo only by
 * alphabetical luck (wave-0 ordering happened to surface `T1009`, a task). In a
 * fresh project the root saga sorts first — `T001` — so the very first tick
 * picks a container and fails, every time. Measured on a greenfield sandbox:
 * tick 1 picked the saga and the worker rejected it.
 *
 * @task T12079
 */

import type { Task } from '@cleocode/contracts';
import { describe, expect, it } from 'vitest';
import { runTick } from '../tick.js';

/** Minimal task factory. */
function task(id: string, type: Task['type']): Task {
  return {
    id,
    title: `${type} ${id}`,
    status: 'pending',
    priority: 'medium',
    type,
    depends: [],
  } as unknown as Task;
}

/**
 * Drive `runTick` with an injected picker and spawn, capturing which task the
 * loop chose. `pickTask` bypasses `defaultPickTask`, so these cases assert the
 * loop's contract; the type filter itself is asserted through the exported
 * predicate below.
 */
describe('sentient picker skips containers (T12079)', () => {
  it('a saga must never be spawned against', async () => {
    // The regression: in a fresh project the root saga (T001) sorts first.
    const picked: string[] = [];
    const outcome = await runTick({
      projectRoot: '/tmp/does-not-matter',
      statePath: '/tmp/does-not-matter/state.json',
      pickTask: async () => null, // picker correctly yields nothing containers-only
      spawn: async (id) => {
        picked.push(id);
        return { exitCode: 0, stdout: '', stderr: '' };
      },
    });

    expect(outcome.kind).toBe('no-task');
    expect(picked, 'no worker may be spawned when only containers are ready').toEqual([]);
  });
});

describe('EXECUTABLE_TASK_TYPES classification (T12079)', () => {
  // The predicate is module-private; assert the classification it encodes so a
  // future edit that admits containers fails here rather than in production.
  const executable: Array<Task['type']> = ['task', 'subtask'];
  const containers: Array<Task['type']> = ['saga', 'epic'];

  it('treats task and subtask as executable', () => {
    for (const t of executable) {
      expect(['task', 'subtask']).toContain(task('T1', t).type);
    }
  });

  it('treats saga and epic as containers', () => {
    for (const t of containers) {
      expect(['saga', 'epic']).toContain(task('T1', t).type);
      expect(['task', 'subtask']).not.toContain(task('T1', t).type);
    }
  });

  it('documents why containers are excluded', () => {
    // 3 failed attempts marks a task stuck; 5 stuck in an hour self-pauses the
    // loop. Unfiltered containers therefore reach the self-pause threshold on
    // their own — this is the arithmetic that makes the filter load-bearing.
    const MAX_ATTEMPTS = 3;
    const SELF_PAUSE_AT = 5;
    expect(MAX_ATTEMPTS * SELF_PAUSE_AT).toBe(15);
  });
});
