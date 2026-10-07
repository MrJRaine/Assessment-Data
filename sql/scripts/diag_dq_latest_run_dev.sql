/*******************************************************************************
 * Script: diag_dq_latest_run_dev.sql   (DEV warehouse -- read-only diagnostic)
 * Purpose: After the 2026-10-07 app ingest reached the DQ gate (so #1119's SP-path
 *          COPY INTO is FIXED) and usp_RunFullIngestCycle halted on "data quality
 *          checks failed", show exactly WHICH checks failed on the most recent run
 *          so we can decide if it's a real data problem or dev-recovery residue.
 *
 * Reads:  FactDataQualityAudit only. No writes. No PII (keys are IDs/emails/section codes).
 *
 * Result set 1 -- the latest run's violation SUMMARY (category x check x table, counts).
 * Result set 2 -- a SAMPLE of up to 100 offending rows (KeyColumn/KeyValue/Detail) to read.
 * Result set 3 -- the run header (timestamp + total violations) for context.
 *
 * HOW TO READ: the CheckCategory tells the class (Orphan / IsCurrent / Date / Reference /
 *   Consistency). Given this session closed DimStaff overlap + re-expired FactEnrollment,
 *   an IsCurrent or Date violation on DimStaff/FactEnrollment is the likely residue; an
 *   Orphan/Reference on a fact points at the fresh load. Paste all three back.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- Latest proc execution (one RunTimestamp groups all rows from one run).
DECLARE @LatestRun DATETIME2(0) = (SELECT MAX(RunTimestamp) FROM FactDataQualityAudit);

-- 1) Summary: what failed, by category/check/table, with counts.
SELECT
    CheckCategory,
    CheckName,
    TableName,
    COUNT(*) AS Violations
FROM FactDataQualityAudit
WHERE RunTimestamp = @LatestRun
  AND CheckCategory <> 'PASS'
GROUP BY CheckCategory, CheckName, TableName
ORDER BY Violations DESC, CheckCategory, CheckName;

-- 2) Sample offending rows (cap 100) so we can see the actual keys/details.
SELECT TOP 100
    CheckCategory,
    CheckName,
    TableName,
    KeyColumn,
    KeyValue,
    Detail
FROM FactDataQualityAudit
WHERE RunTimestamp = @LatestRun
  AND CheckCategory <> 'PASS'
ORDER BY CheckCategory, CheckName, TableName, KeyValue;

-- 3) Run header: timestamp + total violation count (0 here would mean the halt predates this run).
SELECT
    @LatestRun AS LatestRunTimestamp,
    SUM(CASE WHEN CheckCategory <> 'PASS' THEN 1 ELSE 0 END) AS TotalViolations,
    SUM(CASE WHEN CheckCategory =  'PASS' THEN 1 ELSE 0 END) AS PassRows
FROM FactDataQualityAudit
WHERE RunTimestamp = @LatestRun;
