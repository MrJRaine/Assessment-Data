/*******************************************************************************
 * Script: run_demographic_decorrelation_ingest_dev.sql  (DEV: Assessment_Warehouse_Dev)
 * Purpose: Apply the 2026-11-17 demographic decorrelation (independent
 *          per-attribute hashes) with MINIMAL churn, using the same-day
 *          in-place path of usp_MergeStudent (step 2b).
 *
 * SEQUENCE (after uploading the regenerated StudentsExport.csv):
 *   1) Run query 1 below — counts current student versions that started AFTER
 *      2026-09-01 ("stragglers": a backdated merge silently skips them).
 *   2) EXEC usp_RunFullIngestCycle @EffectiveDate = '2026-09-01';
 *      -> every student whose current version started 2026-09-01 gets the new
 *         demographics IN PLACE: no re-version, no key churn, history reads as
 *         if the demographics were always these.
 *   3) ONLY IF query 1 returned > 0: EXEC usp_RunFullIngestCycle;  (no params)
 *      -> re-versions just the stragglers at today, which is honest for rows
 *         that genuinely postdate September.
 *
 * Expect afterwards: IPP gate reconciliation moves with the new flags (~112
 * flagged; students who LOST the flag get their gates closed, including
 * previously-resolved ones — correct detach semantics; gainers get unresolved
 * IPP? gates). The math team's 8 keep their flags (generator fixture).
 * Programming-page confirmation counts will shift accordingly.
 *
 * READS: DimStudent. WRITES: none from THIS script (the EXECs do the work).
 ******************************************************************************/

-- 1) Stragglers: current versions a backdated merge cannot touch
SELECT COUNT(*) AS VersionsStartedAfterSep1
FROM DimStudent
WHERE IsCurrent = 1 AND EnrollStatus IN (0, -1)
  AND EffectiveStartDate > '2026-09-01';
