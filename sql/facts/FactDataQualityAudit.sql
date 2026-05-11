/*******************************************************************************
 * Table: FactDataQualityAudit
 * Purpose: Append-only audit log for data quality check runs against the
 *          Assessment_Warehouse. Written by usp_RunDataQualityChecks.
 *          One row per violation per run; one PASS sentinel row when a run
 *          finds zero violations (so the table itself is the run history).
 * SCD Type: N/A (append-only audit log)
 * Created: 2026-05-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Usage patterns:
 *   - "Did the last ingest produce clean data?"
 *       SELECT TOP 1 * FROM FactDataQualityAudit ORDER BY RunTimestamp DESC;
 *   - "When did this specific violation first appear?"
 *       SELECT MIN(RunTimestamp) FROM FactDataQualityAudit
 *       WHERE CheckName = '...' AND KeyValue = '...';
 *   - "How many runs have been clean vs failed?"
 *       SELECT RunTimestamp,
 *              SUM(CASE WHEN CheckCategory = 'PASS' THEN 1 ELSE 0 END) AS Passes,
 *              SUM(CASE WHEN CheckCategory <> 'PASS' THEN 1 ELSE 0 END) AS Violations
 *       FROM FactDataQualityAudit GROUP BY RunTimestamp;
 *
 * Retention: no automatic pruning. At pilot scale (5 PS exports/year + ad-hoc
 * runs) this stays small for years. Revisit at full rollout if row count
 * becomes meaningful — easy to add a periodic prune of PASS rows older than
 * N months while keeping all violation history.
 ******************************************************************************/

CREATE TABLE FactDataQualityAudit (
    DataQualityAuditID  BIGINT          NOT NULL IDENTITY,
    RunTimestamp        DATETIME2(0)    NOT NULL,           -- groups all rows from one proc execution
    CheckCategory       VARCHAR(20)     NOT NULL,           -- 'Orphan' / 'IsCurrent' / 'Date' / 'Reference' / 'Consistency' / 'PASS'
    CheckName           VARCHAR(150)    NOT NULL,           -- short description of the rule violated (or 'All checks passed' on PASS row)
    TableName           VARCHAR(50)     NULL,               -- table containing the offending row; NULL on PASS row
    KeyColumn           VARCHAR(50)     NULL,               -- column name used to identify the offending row; NULL on PASS row
    KeyValue            VARCHAR(150)    NULL,               -- value of that column for the offending row (or composite triple); NULL on PASS row
    Detail              VARCHAR(500)    NULL,               -- what was wrong (or run summary on PASS row)
    LastUpdated         DATETIME2(0)    NOT NULL            -- set on insert; equals RunTimestamp
);
