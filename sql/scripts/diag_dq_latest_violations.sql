/*******************************************************************************
 * Script: diag_dq_latest_violations  (READ-ONLY, reusable — no values to edit)
 * Purpose: The violation rows behind the most recent data-quality gate run
 *          (the "data quality gate FAILED | N violations | see
 *          FactDataQualityAudit" message). One row per offending record with
 *          the rule, table, key, and detail. On a passing run it returns the
 *          single PASS summary row instead.
 * Reads: FactDataQualityAudit. Writes: nothing.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Run DATETIME2(0);
SELECT @Run = MAX(RunTimestamp) FROM FactDataQualityAudit;

SELECT
    CAST(RunTimestamp AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS RunAtlantic,
    CheckCategory,
    CheckName,
    TableName,
    KeyColumn,
    KeyValue,
    Detail
FROM FactDataQualityAudit
WHERE RunTimestamp = @Run
ORDER BY CheckCategory, CheckName, KeyValue;
