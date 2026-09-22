/*******************************************************************************
 * Script: diag_last_dq_run.sql   (READ-ONLY)
 * Purpose: Show the violations from the MOST RECENT usp_RunDataQualityChecks run
 *          (the gate that halts usp_RunFullIngestCycle with Msg 51000). Result 1
 *          is the per-check summary; Result 2 is up to 200 offending rows so you
 *          can see the actual keys/detail.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @LastRun DATETIME2(0) = (SELECT MAX(RunTimestamp) FROM FactDataQualityAudit);

-- Result 1 — summary: how many violations per check
SELECT
    CheckCategory,
    CheckName,
    TableName,
    COUNT(*) AS Violations
FROM FactDataQualityAudit
WHERE RunTimestamp = @LastRun
  AND CheckCategory <> 'PASS'
GROUP BY CheckCategory, CheckName, TableName
ORDER BY COUNT(*) DESC, CheckName;

-- Result 2 — samples: the offending rows (key + what was wrong)
SELECT TOP 200
    CheckCategory,
    CheckName,
    TableName,
    KeyColumn,
    KeyValue,
    Detail
FROM FactDataQualityAudit
WHERE RunTimestamp = @LastRun
  AND CheckCategory <> 'PASS'
ORDER BY CheckName, KeyValue;
