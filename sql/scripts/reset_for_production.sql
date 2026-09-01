/*******************************************************************************
 * Script: reset_for_production.sql
 * Purpose: ONE-TIME production cutover reset. Clears ALL synthetic / pilot test
 *          data from Assessment_Warehouse and leaves it EMPTY and ready to
 *          receive the first REAL PowerSchool ingest. Unlike the dev reset
 *          (reset_and_run_full_ingest.sql), this does NOT re-run the
 *          orchestrator — it leaves the warehouse clean, not re-populated.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * =============================== WARNING ====================================
 * DESTRUCTIVE and intended for the LIVE warehouse. Run ONCE, deliberately, at
 * the production data cutover. TRUNCATE resets BIGINT IDENTITY, so surrogate
 * keys restart clean at go-live. There is no undo — confirm you are on the
 * intended warehouse before running.
 * ============================================================================
 *
 * WHAT IT CLEARS (24 tables) — all synthetic/pilot data:
 *   - PS roster:      DimStudent, DimStaff, DimSection, FactEnrollment,
 *                     FactSectionTeachers, FactStaffAssignment
 *   - App/assessment: FactAssessmentReading, FactAssessmentWriting,
 *                     FactStudentIPP
 *   - Audit logs:     FactSubmissionAudit, FactDataQualityAudit
 *   - Derived access: StaffSchoolAccess (rebuilt by usp_MergeStaff on ingest)
 *   - Cycles/windows: DimAssessmentWindow — the OLD auto-generated monthly
 *                     windows are obsolete under the "Short Cycles of Response"
 *                     model (2026-08-27). Cleared here; recreate cycles manually
 *                     via usp_UpsertShortCycle / the admin screen after reset.
 *   - Staging:        Stg_* (5) + Wrk_* (6) transient load tables
 *
 * WHAT IT PRESERVES (reference / seed / admin config — NOT touched):
 *   DimGender, DimGrade, DimRole, DimProgram, DimTerm, DimCalendar,
 *   DimSchool (24 REAL TCRCE schools — NS DoE directory seed, incl. 2 alt high schools),
 *   DimReadingScale, DimReadingBenchmark, DimAchievementLevel,
 *   StaffAppAccess (manual admin-capability allowlist — must survive a data reset).
 *   All procedures / views / inline TVFs / grants are untouched.
 *
 * NOTE: RLS_UserSchoolAccess / RLS_UserSectionAccess do NOT exist (dropped in
 *   favour of the derived StaffSchoolAccess). Do not look for them here.
 *
 * ------------------------- BEFORE the first real ingest ---------------------
 * 1. CSV loaders: the live usp_Load*Staging procs must be at CUTOVER (sqlReport
 *    CSV) format, and the real PS sqlReport exports must be in the Lakehouse
 *    Files/imports/{topic}/ folders. (Source is ahead of live for the CSV
 *    loaders — deploy them at cutover.)
 * 2b. Short Cycles of Response: this reset clears DimAssessmentWindow. Before
 *    teachers can enter results, create the cycles (region-wide date ranges per
 *    subject) via usp_UpsertShortCycle or the Manage-Short-Cycles admin screen.
 * 2. RegionalAnalyst access (IMPORTANT): the jeffrey.raine@tcrce.ca analyst
 *    access is NOT stored anywhere except as the result of ingesting his staff
 *    row. This reset removes it (DimStaff/FactStaffAssignment/StaffSchoolAccess
 *    are all cleared). It is restored ONLY if the REAL PS staff export contains
 *    a jeffrey.raine@tcrce.ca row whose Group maps to RegionalAnalyst (Group 40,
 *    or 10/29/41/42/43). Do NOT hand-INSERT into DimStaff — the merge will fight
 *    it; fix it in the staff export instead. Until that ingest runs, no one can
 *    see data in the app (sign-in still works; scoped reads return nothing).
 * ----------------------------------------------------------------------------
 *
 * AFTER this script: run the first real ingest via EXEC usp_RunFullIngestCycle
 * (or the in-app / scheduled trigger) once the real PS files are staged.
 ******************************************************************************/

-- ============================================================================
-- 1. CLEAR — PS roster dimensions + facts
-- ============================================================================
TRUNCATE TABLE FactEnrollment;
TRUNCATE TABLE FactSectionTeachers;
TRUNCATE TABLE FactStaffAssignment;
TRUNCATE TABLE DimSection;
TRUNCATE TABLE DimStaff;
TRUNCATE TABLE DimStudent;

-- ============================================================================
-- 2. CLEAR — app-entered assessment data + IPP
-- ============================================================================
TRUNCATE TABLE FactAssessmentReading;
TRUNCATE TABLE FactAssessmentWriting;
TRUNCATE TABLE FactStudentIPP;

-- ============================================================================
-- 3. CLEAR — audit logs (clean production log; comment these two out to keep
--    the pilot audit history instead)
-- ============================================================================
TRUNCATE TABLE FactSubmissionAudit;
TRUNCATE TABLE FactDataQualityAudit;

-- ============================================================================
-- 4. CLEAR — derived access table (usp_MergeStaff rebuilds it on next ingest)
-- ============================================================================
TRUNCATE TABLE StaffSchoolAccess;

-- ============================================================================
-- 4b. CLEAR — assessment cycles/windows. The old auto-generated monthly windows
--     are obsolete; recreate "Short Cycles of Response" manually after reset.
-- ============================================================================
TRUNCATE TABLE DimAssessmentWindow;

-- ============================================================================
-- 5. CLEAR — transient staging / work tables (reloaded each ingest anyway)
-- ============================================================================
TRUNCATE TABLE Stg_Student;
TRUNCATE TABLE Stg_Staff;
TRUNCATE TABLE Stg_Section;
TRUNCATE TABLE Stg_Enrollment;
TRUNCATE TABLE Stg_CoTeacher;
TRUNCATE TABLE Wrk_Student;
TRUNCATE TABLE Wrk_StaffPersons;
TRUNCATE TABLE Wrk_StaffAssignment;
TRUNCATE TABLE Wrk_Section;
TRUNCATE TABLE Wrk_SectionTeacher;
TRUNCATE TABLE Wrk_Enrollment;
GO

-- ============================================================================
-- VERIFY — every CLEARed table should read 0 (per feedback_fabric_stale_preview,
-- trust these COUNT(*)s, not the table data-preview pane which caches).
-- ============================================================================
SELECT 'FactEnrollment'         AS TableName, COUNT(*) AS Rows, 'expect 0' AS Expect FROM FactEnrollment
UNION ALL SELECT 'FactSectionTeachers',  COUNT(*), 'expect 0' FROM FactSectionTeachers
UNION ALL SELECT 'FactStaffAssignment',  COUNT(*), 'expect 0' FROM FactStaffAssignment
UNION ALL SELECT 'DimSection',           COUNT(*), 'expect 0' FROM DimSection
UNION ALL SELECT 'DimStaff',             COUNT(*), 'expect 0' FROM DimStaff
UNION ALL SELECT 'DimStudent',           COUNT(*), 'expect 0' FROM DimStudent
UNION ALL SELECT 'FactAssessmentReading',COUNT(*), 'expect 0' FROM FactAssessmentReading
UNION ALL SELECT 'FactAssessmentWriting',COUNT(*), 'expect 0' FROM FactAssessmentWriting
UNION ALL SELECT 'FactStudentIPP',       COUNT(*), 'expect 0' FROM FactStudentIPP
UNION ALL SELECT 'FactSubmissionAudit',  COUNT(*), 'expect 0' FROM FactSubmissionAudit
UNION ALL SELECT 'FactDataQualityAudit', COUNT(*), 'expect 0' FROM FactDataQualityAudit
UNION ALL SELECT 'StaffSchoolAccess',    COUNT(*), 'expect 0' FROM StaffSchoolAccess
UNION ALL SELECT 'DimAssessmentWindow',  COUNT(*), 'expect 0' FROM DimAssessmentWindow
ORDER BY TableName;

-- ============================================================================
-- VERIFY — PRESERVED reference/config tables should be UNCHANGED (non-zero).
-- DimSchool must read 24 (the NS DoE TCRCE seed). (DimAssessmentWindow is NOT
-- here — it is cleared above; Short Cycles are created manually after reset.)
-- ============================================================================
SELECT 'DimSchool'            AS TableName, COUNT(*) AS Rows, 'expect 24'        AS Expect FROM DimSchool
UNION ALL SELECT 'DimReadingScale',      COUNT(*), 'expect >0 (seed)'     FROM DimReadingScale
UNION ALL SELECT 'DimReadingBenchmark',  COUNT(*), 'expect >0 (seed)'     FROM DimReadingBenchmark
UNION ALL SELECT 'DimAchievementLevel',  COUNT(*), 'expect >0 (seed)'     FROM DimAchievementLevel
UNION ALL SELECT 'DimGrade',             COUNT(*), 'expect >0 (seed)'     FROM DimGrade
UNION ALL SELECT 'DimProgram',           COUNT(*), 'expect >0 (seed)'     FROM DimProgram
UNION ALL SELECT 'DimRole',              COUNT(*), 'expect >0 (seed)'     FROM DimRole
UNION ALL SELECT 'DimTerm',              COUNT(*), 'expect >0 (seed)'     FROM DimTerm
UNION ALL SELECT 'DimGender',            COUNT(*), 'expect >0 (seed)'     FROM DimGender
UNION ALL SELECT 'DimCalendar',          COUNT(*), 'expect >0 (seed)'     FROM DimCalendar
ORDER BY TableName;
