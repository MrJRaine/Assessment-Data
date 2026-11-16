/*******************************************************************************
 * Diagnostic: diag_loader_credential_state_2026-11-16.sql
 * Purpose: Run on EITHER warehouse (Assessment_Warehouse or _Dev) to answer:
 *          are the five staging loaders currently deployed WITH the
 *          Workspace-Identity CREDENTIAL (the #1119 workaround), and what do
 *          recent App-vs-FabricSQL ingest runs look like?
 *
 *          Context: the data SP's OneLake COPY INTO passthrough has been broken
 *          tenant-side since ~2026-09 (#1119, closed as workaround). A loader
 *          deployed from a pre-workaround source (e.g. the frozen
 *          deploy_all_dev.sql) silently reverts the App/SP ingest path to the
 *          broken passthrough -> token error, while user-run (Fabric editor)
 *          ingests still work. This shows which state each loader is in.
 *
 * READS: sys.objects, sys.sql_modules, IngestRunLog. WRITES: nothing.
 *
 * Result meanings:
 *   1) HasWICredential = 1 for all five -> loaders carry the workaround; an
 *      App-triggered ingest should NOT hit the OneLake token error here.
 *      HasWICredential = 0 on any row -> that loader was redeployed from a
 *      pre-workaround source; the App/SP path WILL fail its COPY INTO with a
 *      token error on this warehouse. Fix: redeploy from
 *      sql/procedures/usp_Load*Staging.sql (live sources, credentialed) or
 *      sql/scripts/deploy_dev_loaders_workspace_identity.sql (dev).
 *   2) Recent runs: a failed run shows a Started row + the Load rows that got
 *      through, but NO terminal Completed/Failed row (Fabric has no TRY/CATCH,
 *      so a COPY INTO auth error aborts the cycle unlogged). App runs dying at
 *      the first Load while FabricSQL runs complete is the signature of a
 *      passthrough (non-credentialed) loader.
 ******************************************************************************/

-- ---- 1. Deployed loader definitions: credentialed or passthrough? ----------
SELECT o.name AS LoaderProc,
       CASE WHEN m.definition LIKE '%Workspace Identity%' THEN 1 ELSE 0 END AS HasWICredential,
       o.modify_date AS LastDeployedUTC
FROM sys.objects o
INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.type = 'P'
  AND o.name IN ('usp_LoadStudentsStaging', 'usp_LoadStaffStaging', 'usp_LoadSectionStaging',
                 'usp_LoadEnrollmentStaging', 'usp_LoadCoTeacherStaging')
ORDER BY o.name;

-- ---- 2. Last 10 ingest cycles: who ran them, from where, how far they got --
-- Collate a run by CycleStart and read its steps in LoggedAt order (IngestRunLogID
-- is non-monotonic on Fabric). An App run that logs Started but never Completed,
-- while FabricSQL runs complete, points at the loader COPY INTO auth.
SELECT l.CycleStart, l.Source, l.CallerUPN, l.Phase, l.Topic, l.Status, l.RowsLoaded, l.Message, l.LoggedAt
FROM IngestRunLog l
WHERE l.CycleStart IN (SELECT TOP 10 CycleStart FROM IngestRunLog GROUP BY CycleStart ORDER BY MAX(LoggedAt) DESC)
ORDER BY l.CycleStart DESC, l.LoggedAt ASC;
