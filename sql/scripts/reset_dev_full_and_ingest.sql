/*******************************************************************************
 * Script: reset_dev_full_and_ingest.sql   (DEV / TEST ONLY)
 * Purpose: A TRUE clean-slate for a from-scratch dev ingest test. Truncates the
 *          six roster tables (like reset_and_run_full_ingest) AND the user-entered
 *          fact tables, then runs the orchestrator to rebuild from the Lakehouse
 *          Files/imports/{topic}/ folders.
 *
 * WHY THE EXTRA TRUNCATES: reset_and_run_full_ingest clears only the roster tables.
 *   TRUNCATE resets BIGINT IDENTITY, so re-ingest issues BRAND-NEW StudentKey/StaffKey
 *   surrogates — but any previously-entered assessment/programming result still points
 *   at the OLD surrogates, so it orphans and usp_RunDataQualityChecks halts the run
 *   (Msg 51000: "FactAssessmentReading.StudentKey not found in DimStudent", etc.).
 *   Clearing the entered facts here removes those orphans for a clean baseline.
 *
 * WHAT'S NOT TOUCHED (deliberately):
 *   - DimAssessmentWindow / DimShortCycle — the CYCLE instances (app-authored config).
 *     Keep them so entry works after ingest. (reset_for_production DOES wipe these — do
 *     NOT use that script here.)
 *   - StaffSchoolAccess — rebuilt by usp_MergeStaff (Step 6) during the ingest.
 *   - Reference/seed dims (DimSchool, DimProgram, DimTerm, DimGrade, DimRole,
 *     DimReadingScale, DimCourseAssessment).
 *   - Stg_* / Wrk_* — the load procs truncate staging themselves.
 *
 * NOT for production. Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

-- Roster tables (same six as reset_and_run_full_ingest)
TRUNCATE TABLE FactEnrollment;
TRUNCATE TABLE FactSectionTeachers;
TRUNCATE TABLE FactStaffAssignment;
TRUNCATE TABLE DimSection;
TRUNCATE TABLE DimStaff;
TRUNCATE TABLE DimStudent;

-- User-entered facts keyed on the (now reset) student/staff surrogates
TRUNCATE TABLE FactAssessmentReading;
TRUNCATE TABLE FactAssessmentWriting;
TRUNCATE TABLE FactAssessmentMath;
TRUNCATE TABLE FactStudentIPP;
TRUNCATE TABLE FactStudentAdaptation;
TRUNCATE TABLE FactSubmissionAudit;

EXEC usp_RunFullIngestCycle;

-- The export files date every enrollment to a fixed school year, which EXPIRES -- so rosters resolve
-- to nothing today and /enter shows "No cycles" for EVERYONE. Roll expired enrollments forward a year
-- so they're current. Guarded to expired rows only => safe + idempotent (mirrors rollforward_enrollment_dev.sql).
DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
UPDATE FactEnrollment
SET StartDate   = DATEADD(YEAR, 1, StartDate),
    EndDate     = DATEADD(YEAR, 1, EndDate),
    LastUpdated = GETDATE()
WHERE EndDate IS NOT NULL AND EndDate < @Today;
