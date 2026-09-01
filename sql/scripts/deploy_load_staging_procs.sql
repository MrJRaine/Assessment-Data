/*******************************************************************************
 * Combined deploy: all 5 usp_Load*Staging procs (CSV loaders) in one run.
 * Run ONCE on the target warehouse (dev or live). Each proc is wrapped with
 * DROP IF EXISTS + GO so a re-deploy is self-contained (the individual proc
 * files are bare CREATE with no DROP/GO). Fabric needs each CREATE PROCEDURE
 * in its own batch -- the GO separators provide that.
 *
 * COPY INTO globs (match the PS export base names + any suffix):
 *   students/Students*  staff/Staff*  sections/Sections*
 *   enrollments/Enrollments*  section-teachers/Co-Teachers*
 ******************************************************************************/

-- ============================================================================
DROP PROCEDURE IF EXISTS usp_LoadStudentsStaging;
GO
/*******************************************************************************
 * Procedure: usp_LoadStudentsStaging
 * Purpose: Strategy A loader — TRUNCATE Stg_Student and COPY INTO from the
 *          OneLake students/ folder. Decoupled from usp_MergeStudent so that
 *          the Strategy B Pipeline (Step 29) can replace this proc with a
 *          Copy activity without touching the merge logic.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Students export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files, so leaving stale exports in place will produce
 * duplicates. Operators should clear the folder before each ingest.
 *
 * COPY INTO config — PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed — see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default — sqlReports use CRLF, default catches it)
 * UTF-8 is the default; ENCODING parameter is not supported by Fabric.
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports — the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard — any single dropped file loads, no filename
 * prefix required.
 *
 * Path note: Step 7 testing showed the GUID-based abfss:// path works in this
 * environment while the name-based path failed authentication. The GUIDs
 * embedded below correspond to the Regional_Data_Portal workspace and the
 * Assessment_Landing lakehouse — read them from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadStudentsStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Student;

    COPY INTO Stg_Student
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/students/Students*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================================================================
DROP PROCEDURE IF EXISTS usp_LoadStaffStaging;
GO
/*******************************************************************************
 * Procedure: usp_LoadStaffStaging
 * Purpose: Strategy A loader — TRUNCATE Stg_Staff and COPY INTO from the
 *          OneLake staff/ folder. Decoupled from usp_MergeStaff so the
 *          Strategy B Pipeline (Step 29) can replace this proc with a Copy
 *          activity without touching the merge logic.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Staff export file present
 * in the watched folder at call time. The wildcard pattern below unions any
 * matching files — operators should clear the folder before each ingest.
 *
 * COPY INTO config — PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed — see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default — sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports — the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard — any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse — read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadStaffStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Staff;

    COPY INTO Stg_Staff
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/staff/Staff*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================================================================
DROP PROCEDURE IF EXISTS usp_LoadSectionStaging;
GO
/*******************************************************************************
 * Procedure: usp_LoadSectionStaging
 * Purpose: Strategy A loader — TRUNCATE Stg_Section and COPY INTO from the
 *          OneLake sections/ folder. Decoupled from usp_MergeSection so the
 *          Strategy B Pipeline (Step 29) can replace this proc with a Copy
 *          activity without touching the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Sections export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files — operators should clear the folder before
 * each ingest.
 *
 * COPY INTO config — PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed — see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default — sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports — the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard — any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse — read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadSectionStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Section;

    COPY INTO Stg_Section
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/sections/Sections*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================================================================
DROP PROCEDURE IF EXISTS usp_LoadEnrollmentStaging;
GO
/*******************************************************************************
 * Procedure: usp_LoadEnrollmentStaging
 * Purpose: Strategy A loader — TRUNCATE Stg_Enrollment and COPY INTO from the
 *          OneLake enrollments/ folder. Decoupled from usp_MergeEnrollment
 *          so the Strategy B Pipeline (Step 29) can replace this proc with a
 *          Copy activity without touching the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Enrollments export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files — operators should clear the folder before
 * each ingest.
 *
 * COPY INTO config — PowerSchool sqlReport CSV format (source updated 2026-06-08;
 * NOT yet deployed — see docs/powerschool-report-specifications.md Appendix C):
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited)
 *   FIELDQUOTE      = '"'       (text qualifier; handles embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default — sqlReports use CRLF, default catches it)
 * Replaces the pilot direct-table-extract format (TAB / CR-only 0x0D / .text).
 * DEPLOY ONLY at cutover, together with the new SQL reports — the live pilot
 * ingest still runs the previously-deployed TAB format until then.
 * Folder-routed by '*' wildcard — any single dropped file loads, no filename
 * prefix required.
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse — read GUIDs from the Fabric portal URL if
 * the workspace or lakehouse is ever rebuilt.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadEnrollmentStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_Enrollment;

    COPY INTO Stg_Enrollment
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/enrollments/Enrollments*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================================================================
DROP PROCEDURE IF EXISTS usp_LoadCoTeacherStaging;
GO
/*******************************************************************************
 * Procedure: usp_LoadCoTeacherStaging
 * Purpose: Strategy A loader — TRUNCATE Stg_CoTeacher and COPY INTO from the
 *          OneLake section-teachers/ folder. Decoupled from
 *          usp_MergeSectionTeachers so the Strategy B Pipeline (Step 29)
 *          can replace this proc with a Copy activity without touching
 *          the merge logic.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Operational expectation: exactly ONE PowerSchool Co-Teacher export file
 * present in the watched folder at call time. The wildcard pattern below
 * unions any matching files — operators should clear the folder before
 * each ingest.
 *
 * Empty-file tolerance: if PS is not tracking co-teaching, the export is
 * skipped entirely and this folder is empty. COPY INTO with no matching
 * files raises an error in that case — operators handling that scenario
 * should either drop a 0-row "headers only" placeholder file in the folder
 * or skip calling this proc altogether. usp_MergeSectionTeachers DOES
 * tolerate Stg_CoTeacher being empty (primary teachers from Stg_Section
 * are still ingested).
 *
 * COPY INTO config — DIFFERENT from the direct-table-extract loaders:
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = ','       (sqlReport is comma-delimited, NOT TAB)
 *   FIELDQUOTE      = '"'       (Teacher column emits "Last, First" with embedded commas)
 *   FIRSTROW        = 2         (skip header)
 *   ROWTERMINATOR   = (default — sqlReports use CRLF, default catches it)
 *
 * Path: GUID-based abfss URL into the Regional_Data_Portal workspace's
 * Assessment_Landing lakehouse.
 ******************************************************************************/

CREATE PROCEDURE usp_LoadCoTeacherStaging
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE Stg_CoTeacher;

    COPY INTO Stg_CoTeacher
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/section-teachers/Co-Teachers*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

