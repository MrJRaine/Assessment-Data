/*******************************************************************************
 * Script:  diag_ingest_landing_dev.sql   (DEV synthetic only — READ ONLY)
 * Purpose: diag_demo_seed_scope showed DimStudent has 0 current rows — the config
 *          (cycles/windows/benchmarks/tasks) is fine but the ROSTER is missing. This
 *          localizes WHERE the student roster was lost: did COPY INTO land rows in
 *          staging (Stg_Student), did the merge insert current DimStudent rows, and
 *          what did the last ingest audit report. No writes — SELECTs only.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_ingest_landing_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

------------------------------------------------------------------------------
-- A. Staging landing — did COPY INTO actually load rows? 0 = file not in OneLake,
--    filename/glob mismatch, wrong path, or ROWTERMINATOR (silent 0-row load).
------------------------------------------------------------------------------
SELECT 'A. staging counts' AS Stage,
       (SELECT COUNT(*) FROM dbo.Stg_Student)    AS Stg_Student,
       (SELECT COUNT(*) FROM dbo.Stg_Staff)      AS Stg_Staff,
       (SELECT COUNT(*) FROM dbo.Stg_Section)    AS Stg_Section,
       (SELECT COUNT(*) FROM dbo.Stg_Enrollment) AS Stg_Enrollment;

------------------------------------------------------------------------------
-- B. Dimension landing — total rows vs current rows. total>0 & current=0 => the
--    merge CLOSED everyone (missing-from-import); total=0 => nothing ever inserted.
------------------------------------------------------------------------------
SELECT 'B. DimStudent' AS Stage,
       COUNT(*) AS TotalRows,
       SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentRows,
       MIN(EffectiveStartDate) AS MinStart, MAX(EffectiveStartDate) AS MaxStart
FROM dbo.DimStudent;

SELECT 'B2. DimStaff' AS Stage,
       COUNT(*) AS TotalRows,
       SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentRows
FROM dbo.DimStaff;

SELECT 'B3. DimSection' AS Stage,
       COUNT(*) AS TotalRows,
       SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS CurrentRows
FROM dbo.DimSection;

SELECT 'B4. FactEnrollment' AS Stage,
       COUNT(*) AS TotalRows,
       SUM(CASE WHEN ActiveFlag = 1 THEN 1 ELSE 0 END) AS ActiveRows
FROM dbo.FactEnrollment;

------------------------------------------------------------------------------
-- C. Last ingest audit — what each merge reported (staged / new / versioned /
--    missing-closed). A "0 staged" message here = COPY INTO loaded nothing.
------------------------------------------------------------------------------
SELECT TOP 20 'C. recent audit' AS Stage,
       SubmissionTimestamp, RecordType, Source, Status, RecordCount, Message
FROM dbo.FactSubmissionAudit
ORDER BY SubmissionTimestamp DESC;
