/**
 * Nexus analyze orchestrator — business logic extracted from `cleo nexus analyze`.
 *
 * Runs the code-intelligence pipeline, clears the existing index for full runs,
 * refreshes the nexus-bridge, updates the multi-project registry, and sweeps
 * the git log for task–symbol links. All side-effects are best-effort and do
 * not fail the pipeline on error.
 *
 * @module nexus/analyze-orchestrator
 * @epic T9833
 * @task T10062
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Parameters for {@link runNexusAnalysis}. */
export interface NexusAnalysisParams {
  /** Absolute path to the repository to analyze. */
  repoPath: string;
  /** Override the project ID (default: `base64url(repoPath).slice(0, 32)`). */
  projectIdOverride?: string;
  /** When true, only re-index files that changed since the last run. */
  incremental?: boolean;
  /**
   * Progress callback invoked every 50 files (and on completion).
   * Omit for JSON output mode.
   */
  onProgress?: (current: number, total: number, filePath: string) => void;
}

/** Result of a successful {@link runNexusAnalysis} call. */
export interface NexusAnalysisResult {
  projectId: string;
  repoPath: string;
  incremental: boolean;
  nodeCount: number;
  relationCount: number;
  fileCount: number;
  durationMs: number;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Run the nexus code-intelligence pipeline on a repository.
 *
 * This function:
 * 1. Derives the project ID.
 * 2. For full runs, clears the existing nexus index.
 * 3. Runs `@cleocode/nexus` pipeline.
 * 4. Best-effort: refreshes `nexus-bridge.md`.
 * 5. Best-effort: updates the multi-project registry.
 * 6. Best-effort: sweeps the git log for task–symbol links.
 *
 * @param params - Analysis configuration
 * @returns Pipeline result with node/relation/file counts and duration
 * @throws {Error} When the pipeline itself fails (best-effort steps never throw)
 */
export async function runNexusAnalysis(params: NexusAnalysisParams): Promise<NexusAnalysisResult> {
  const { repoPath, projectIdOverride, incremental = false, onProgress } = params;

  const startTime = Date.now();

  // SSoT-EXEMPT:pipeline-progress — requires direct DB handle access and a
  // progress callback that is CLI-only. Extracted here to keep the core
  // runnable without the CLI layer, but the DB/pipeline imports still happen
  // via dynamic imports so the CLI controls when heavy deps are loaded.
  const [{ getNexusDb, nexusSchema }, { runPipeline }] = await Promise.all([
    import('@cleocode/core/store/nexus-sqlite' as string),
    import('@cleocode/nexus/pipeline' as string),
  ]);

  const projectId = projectIdOverride ?? Buffer.from(repoPath).toString('base64url').slice(0, 32);

  const db = await getNexusDb();
  const tables = {
    nexusNodes: nexusSchema.nexusNodes,
    nexusRelations: nexusSchema.nexusRelations,
  };

  if (!incremental) {
    // ADR-090 · T11648: the graph is project-scoped (one project per `cleo.db`),
    // so a non-incremental reindex clears the WHOLE graph table — the former
    // `WHERE project_id = ?` predicate is dropped.
    try {
      db.delete(nexusSchema.nexusNodes).run();
    } catch {
      // table may be empty — ignore
    }
    try {
      db.delete(nexusSchema.nexusRelations).run();
    } catch {
      // table may be empty — ignore
    }
    // T12074: clear the FTS shadow explicitly.
    //
    // `nexus_symbols_fts` is kept in sync by AFTER INSERT/DELETE/UPDATE
    // triggers on `nexus_nodes`, keyed on `rowid`. When the shadow drifts —
    // rows whose base row vanished by a path that did not fire the delete
    // trigger — those orphaned rowids survive the clear above and then COLLIDE
    // with the rebuild's `INSERT INTO nexus_symbols_fts(rowid, …)`, because
    // the insert supplies an explicit rowid.
    //
    // The failure mode is severe and silent about its cause: the reindex has
    // already emptied `nexus_nodes`/`nexus_relations`, so the collision leaves
    // the project with a DESTROYED index and an `E_PIPELINE_FAILED` whose
    // message is a bare "Failed query: insert into nexus_nodes" plus 8,500
    // bound parameters. Observed on this repo 2026-08-06: a graph of 24,482
    // nodes / 39,163 relations reduced to 500 / 0 by a single `cleo nexus
    // analyze`, with 70 orphaned shadow rows as the only cause.
    //
    // That matters doubly because `analyze` is the repair command the agent
    // protocol — and the stale-index error added in T12068 — tell agents to
    // run. A repair path that can destroy the thing it repairs is worse than
    // no repair path.
    try {
      const { sql } = await import('drizzle-orm');
      db.run(sql`DELETE FROM nexus_symbols_fts`);
    } catch {
      // FTS shadow is optional (older schemas lack it) — ignore
    }
  }

  const result = await runPipeline(repoPath, projectId, db, tables, onProgress, {
    incremental,
  });

  // Best-effort: refresh nexus-bridge.md
  try {
    const { refreshNexusBridge } = await import('@cleocode/core/internal' as string);
    await refreshNexusBridge(repoPath, projectId);
  } catch {
    // non-fatal
  }

  // Best-effort: update multi-project registry
  try {
    const { nexusUpdateIndexStats } = await import('@cleocode/core/internal' as string);
    await nexusUpdateIndexStats(repoPath, {
      nodeCount: result.nodeCount,
      relationCount: result.relationCount,
      fileCount: result.fileCount,
    });
  } catch {
    // non-fatal
  }

  // Best-effort: sweep git log for task–symbol links
  try {
    const { runGitLogTaskLinker } = await import('@cleocode/core/nexus' as string);
    const sweeperResult = await runGitLogTaskLinker(repoPath);
    if (sweeperResult.commitsProcessed > 0) {
      process.stderr.write(
        `[nexus] Task-symbol sweep: ${sweeperResult.commitsProcessed} commit(s), ${sweeperResult.tasksFound} task(s), ${sweeperResult.linked} edge(s) linked.\n`,
      );
    }
  } catch {
    // non-fatal
  }

  return {
    projectId,
    repoPath,
    incremental,
    nodeCount: result.nodeCount,
    relationCount: result.relationCount,
    fileCount: result.fileCount,
    durationMs: Date.now() - startTime,
  };
}
