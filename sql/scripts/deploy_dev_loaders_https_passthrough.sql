/*******************************************************************************
 * Script: deploy_dev_loaders_https_passthrough.sql   (DEV warehouse ONLY)
 * Purpose: #1119 ISOLATION EXPERIMENT -- does the `https://` source form ALONE fix the
 *          SP-path COPY INTO, WITHOUT the Workspace-Identity credential (i.e. plain CALLER
 *          PASSTHROUGH)? Recreates the five dev loaders with the https source form but NO
 *          `CREDENTIAL = (IDENTITY = 'Workspace Identity')` clause -- back to the SP's own
 *          OneLake passthrough token, exactly like deploy_dev_cutover_loaders.sql except the
 *          source scheme is https:// instead of abfss://.
 *
 * WHY: the https+WI form got the app/SP ingest PAST the loaders to the DQ gate (2026-10-07),
 *      proving #1119's COPY INTO is fixed -- but with TWO variables changed at once (url form
 *      AND credential). This backs the credential out to learn which one did the work:
 *        - If the app/SP ingest reaches the DQ gate / merges again => the https:// FORM alone
 *          fixed it (abfss was the whole problem for the SP). We can DROP the Workspace-Identity
 *          dependency entirely -- simplest, most durable outcome (nothing to provision/maintain).
 *        - If it throws Msg 13840 / a token/403 at COPY INTO => the WI credential is doing the
 *          real work; revert to deploy_dev_loaders_workspace_identity_https.sql and keep WI.
 *      (Plausible it works: the tenant "SPs can call Fabric APIs" setting is confirmed ON, so SP
 *      passthrough should now get an OneLake token -- abfss's unsupported-URL rejection may have
 *      masked that all along.)
 *
 * RUN ORDER -- do NOT run this until the DQ gate is CLEAN:
 *   This is the SECOND experiment. First get a clean dev app ingest on the https+WI loaders
 *   (diagnose + fix whatever trips FactDataQualityAudit via diag_dq_latest_run_dev.sql). Only
 *   with a clean baseline does "reaches a clean finish" become a meaningful success signal here.
 *   Then: (1) run THIS script, (2) app-ingest on dev (SP path), (3) read the run result.
 *
 * NOTE -- no standalone probe needed: a bare passthrough COPY INTO run in the SQL editor executes
 *   as the USER (passthrough always worked), so it proves nothing. Only the app/SP run is the test.
 *   And unlike a credentialed loader, a passthrough CREATE is not eagerly auth-validated against a
 *   credential, so a failed SP auth won't drop the proc at CREATE time.
 *
 * REVERT paths:
 *   - keep WI (if passthrough fails) : deploy_dev_loaders_workspace_identity_https.sql
 *   - original abfss passthrough     : deploy_dev_cutover_loaders.sql
 *
 * Workspace (Regional_Data_Portal) : a1b49041-0855-46de-8aca-86762132eefb
 * DEV lakehouse                    : 8c5589bd-d04e-4e94-bb2c-482db645afab
 * Idempotent: DROP IF EXISTS + GO before each CREATE. Re-runnable. No PII.
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/staff/Staff*'
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/sections/Sections*'
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/enrollments/Enrollments*'
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
    FROM 'https://onelake.dfs.fabric.microsoft.com/a1b49041-0855-46de-8aca-86762132eefb/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/section-teachers/Co-Teachers*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
GO
