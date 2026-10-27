/*******************************************************************************
 * Script: diag_mergestaff_fix_and_dq_dev.sql   (DEV only — READ ONLY)
 * Purpose: The §7.2 email-change re-ingest halted on Msg 51000 (DQ checks failed).
 *          (1) Is the step-3.5 email-reconciliation fix actually DEPLOYED on dev's
 *              usp_MergeStaff? (search the stored module body for an in-body marker;
 *              header comments are NOT stored, so markers must live after CREATE.)
 *          (2) What exactly did the latest DQ run flag?
 * Reads:  sys module definition, FactDataQualityAudit. Writes: NOTHING.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_mergestaff_fix_and_dq_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

-- A. Is step 3.5 deployed? '@EmailsReconciled' is declared IN the proc body (after CREATE), so it is
--    stored in the module definition. UPPER() both sides — Fabric LIKE is case-sensitive (binary collation).
SELECT 'A. mergestaff fix' AS Stage,
       CASE WHEN UPPER(OBJECT_DEFINITION(OBJECT_ID('dbo.usp_MergeStaff'))) LIKE '%EMAILSRECONCILED%'
            THEN 'FIX PRESENT (step 3.5 reconciliation deployed)'
            ELSE 'FIX MISSING (dev is running a pre-3.5 usp_MergeStaff)' END AS Status;

-- B. What the latest DQ run flagged (one row per violation; the halted run's rows).
SELECT TOP 100 'B. latest DQ run' AS Stage,
       RunTimestamp, CheckCategory, CheckName, TableName, KeyColumn, KeyValue, Detail
FROM dbo.FactDataQualityAudit
WHERE RunTimestamp = (SELECT MAX(RunTimestamp) FROM dbo.FactDataQualityAudit)
ORDER BY CheckCategory, CheckName, KeyValue;

-- C. If it's a staff double-current / ghost: show Pat Willow's DimStaff rows to see the collision.
SELECT 'C. Pat Willow rows' AS Stage, StaffKey, Email, AccessLevel, IsCurrent, ActiveFlag,
       EffectiveStartDate, EffectiveEndDate
FROM dbo.DimStaff
WHERE FirstName = 'Pat' AND LastName = 'Willow'
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;
