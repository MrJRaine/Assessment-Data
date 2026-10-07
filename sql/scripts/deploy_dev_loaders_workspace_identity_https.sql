/*******************************************************************************
 * Script: deploy_dev_loaders_workspace_identity_https.sql   (DEV warehouse ONLY)
 * Purpose: #1119 option A, STEP 2. Redeploy the five DEV staging loaders with the
 *          Workspace-Identity credential AND the `https://onelake.dfs.fabric.microsoft.com/
 *          <ws>/<lh>/Files/...` source form -- the one every MS Workspace-Identity example uses
 *          and the exact form our proven ADLS upload already writes to (webapp/src/lib/onelake.ts).
 *
 *          Identical to deploy_dev_loaders_workspace_identity.sql in EVERY respect except the
 *          COPY INTO source scheme: `abfss://<ws>@onelake.dfs.fabric.microsoft.com/<lh>/Files/...`
 *          becomes `https://onelake.dfs.fabric.microsoft.com/<ws>/<lh>/Files/...`. The abfss form
 *          threw Msg 13840 ("unsupported URL") on the SP path (2026-10-06); the hypothesis is that
 *          abfss makes the WI credential a no-op and https engages it.
 *
 * RUN ORDER (do NOT skip step 1):
 *   1. test_copyinto_https_wi_dev.sql MUST load clean first. A credentialed COPY INTO is validated
 *      at CREATE PROCEDURE time (eager) -- if the https form or the credential can't authorize, each
 *      CREATE below FAILS and, because it is DROP IF EXISTS + CREATE, the DROP leaves the loader GONE.
 *      The standalone probe de-risks that before any DROP runs here.
 *   2. Run this script (recreates all five loaders).
 *   3. Run the ingest FROM THE APP on dev (awdev-impersonation :3002 or awdev :3000) -- that is the
 *      ONLY run that exercises the SP connection. A manual EXEC in the SQL editor runs as a USER and
 *      proves nothing (user COPY INTO has always worked). Watch for Msg 13840 to be GONE.
 *   4. Dev is currently IN MAINTENANCE MODE (the app set it after the half-failed ingest). Clear it
 *      after a clean app ingest (usp_ClearMaintenanceWindow / the down-overlay Clear button).
 *
 * REVERT (back to caller-passthrough, the pre-WI behaviour):
 *   re-run sql/scripts/deploy_dev_cutover_loaders.sql (DROP+CREATE, clean restore).
 *
 * PORT TO LIVE: once the dev app ingest is clean, port this https+WI form to the LIVE loaders
 *   (same two GUIDs differ -- live workspace is the same Regional_Data_Portal GUID; the LIVE landing
 *   lakehouse GUID differs from dev's 8c5589bd..., so substitute it before deploying to live).
 *
 * PREREQUISITE: Workspace Identity provisioned on Regional_Data_Portal
 *   (a1b49041-0855-46de-8aca-86762132eefb) with >= Contributor (already satisfied this session).
 * Idempotent: DROP IF EXISTS + GO before each CREATE. Re-runnable.
 * Dev lakehouse GUID: 8c5589bd-d04e-4e94-bb2c-482db645afab. No PII.
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/students/Students*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/staff/Staff*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/sections/Sections*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/enrollments/Enrollments*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/section-teachers/Co-Teachers*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
    );
END;
GO
