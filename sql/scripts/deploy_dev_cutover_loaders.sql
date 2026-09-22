/*******************************************************************************
 * Script: deploy_dev_cutover_loaders.sql   (DEV warehouse ONLY)
 * Purpose: Bring the DEV staging loaders up to the LIVE "cutover" format so dev
 *          mirrors production. Live already runs the PowerSchool sqlReport CSV
 *          loaders (comma-delimited, FIELDQUOTE, FIRSTROW=2, Students*/Staff*/
 *          Sections*/Enrollments*/Co-Teachers* filenames); dev still ran the old
 *          direct-extract TAB loaders. This replaces the five dev load procs with
 *          the CSV format, pointed at the DEV lakehouse.
 *
 * WHY THIS EXISTS: the committed sql/procedures/usp_Load*Staging.sql are the LIVE
 *          versions and hardcode the LIVE lakehouse GUID (b3819971-...). Dev needs
 *          the same CSV format but the DEV lakehouse GUID (8c5589bd-...). Only the
 *          FROM path differs from the live procs; format config is identical.
 *
 * GUIDs (read from the dev bundle deploy_all_dev.sql / the Fabric portal URL):
 *   Workspace (Regional_Data_Portal) : a1b49041-0855-46de-8aca-86762132eefb
 *   DEV lakehouse (GUID per deploy_all_dev.sql) : 8c5589bd-d04e-4e94-bb2c-482db645afab
 *
 * Idempotent: DROP IF EXISTS + GO before each CREATE (CREATE PROCEDURE must be the
 *   first statement in its batch). Re-runnable.
 *
 * PAIRS WITH: data/imports/_generate_ingest_testset.ps1 -Format Cutover, which
 *   emits Students*/Staff*/Sections*/Enrollments*/Co-Teachers* .csv files matching
 *   the wildcards below. Upload those to the DEV lakehouse Files/imports/{topic}/.
 *
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ============================ Students ============================
DROP PROCEDURE IF EXISTS usp_LoadStudentsStaging;
GO
CREATE PROCEDURE usp_LoadStudentsStaging
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE Stg_Student;
    COPY INTO Stg_Student
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/students/Students*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================= Staff ==============================
DROP PROCEDURE IF EXISTS usp_LoadStaffStaging;
GO
CREATE PROCEDURE usp_LoadStaffStaging
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE Stg_Staff;
    COPY INTO Stg_Staff
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/staff/Staff*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- ============================ Sections ============================
DROP PROCEDURE IF EXISTS usp_LoadSectionStaging;
GO
CREATE PROCEDURE usp_LoadSectionStaging
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE Stg_Section;
    COPY INTO Stg_Section
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/sections/Sections*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- =========================== Enrollments =========================
DROP PROCEDURE IF EXISTS usp_LoadEnrollmentStaging;
GO
CREATE PROCEDURE usp_LoadEnrollmentStaging
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE Stg_Enrollment;
    COPY INTO Stg_Enrollment
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/enrollments/Enrollments*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO

-- =========================== Co-Teachers =========================
DROP PROCEDURE IF EXISTS usp_LoadCoTeacherStaging;
GO
CREATE PROCEDURE usp_LoadCoTeacherStaging
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE Stg_CoTeacher;
    COPY INTO Stg_CoTeacher
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/section-teachers/Co-Teachers*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO
