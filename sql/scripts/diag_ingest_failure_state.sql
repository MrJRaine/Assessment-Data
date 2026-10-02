/*───────────────────────────────────────────────────────────────────────────────────────────
  diag_ingest_failure_state.sql
  Purpose: After an ingest cycle failed at the LOAD step (COPY INTO from OneLake couldn't fetch a
           token), confirm the warehouse is CLEAN before clearing maintenance and retrying.
  Type: READ-ONLY (four SELECTs). Run against LIVE Assessment_Warehouse.
  Region: Canada East.

  Why this is expected to be clean: usp_RunFullIngestCycle runs ALL staging loads first, THEN the
  merges. The failure was in step 1 (usp_LoadStudentsStaging), so no merge ran and the dims/facts
  were never touched — "half-applied" is precautionary here.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- 1) Maintenance state (NULL MaintenanceAt = clear; a value = still held ON).
SELECT MaintenanceAt, Message FROM dbo.AppMaintenance WHERE Id = 1;

-- 2) Recent ingest-cycle audit rows. The LATEST 'IngestCycle' row should be your PRIOR GOOD run,
--    NOT one from this failed attempt — the cycle throws at load before writing any success row.
SELECT TOP 10 SubmissionTimestamp, Status, Message
FROM dbo.FactSubmissionAudit
WHERE RecordType = 'IngestCycle'
ORDER BY SubmissionTimestamp DESC;

-- 3) Merges never ran ⇒ these MAX(LastUpdated) values should PREDATE this failed attempt (i.e. be
--    from your last successful ingest, not today's failed one). If any is "now", investigate.
SELECT 'DimStudent'         AS TableName, MAX(LastUpdated) AS MaxLastUpdated, COUNT(*) AS Rows_ FROM dbo.DimStudent
UNION ALL SELECT 'DimStaff',            MAX(LastUpdated), COUNT(*) FROM dbo.DimStaff
UNION ALL SELECT 'DimSection',          MAX(LastUpdated), COUNT(*) FROM dbo.DimSection
UNION ALL SELECT 'FactEnrollment',      MAX(LastUpdated), COUNT(*) FROM dbo.FactEnrollment
UNION ALL SELECT 'FactSectionTeachers', MAX(LastUpdated), COUNT(*) FROM dbo.FactSectionTeachers;

-- 4) Staging is transient (truncated at the start of the next load), so its contents don't affect
--    reporting — this is just for context on how far the failed load got.
SELECT 'Stg_Student' AS StagingTable, COUNT(*) AS Rows_ FROM dbo.Stg_Student
UNION ALL SELECT 'Stg_Staff',      COUNT(*) FROM dbo.Stg_Staff
UNION ALL SELECT 'Stg_Section',    COUNT(*) FROM dbo.Stg_Section
UNION ALL SELECT 'Stg_Enrollment', COUNT(*) FROM dbo.Stg_Enrollment;
