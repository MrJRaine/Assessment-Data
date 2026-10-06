/*******************************************************************************
 * Script: deploy_dev_loaders_workspace_identity.sql   (DEV warehouse ONLY)
 * Purpose: TEST the Workspace-Identity fix for the #1119 COPY INTO OneLake token
 *          failure. Redeploys the five DEV staging loaders identically to
 *          deploy_dev_cutover_loaders.sql EXCEPT each COPY INTO now authorizes the
 *          OneLake source read with the WORKSPACE IDENTITY instead of the caller's
 *          (SP) passthrough token:
 *              CREDENTIAL = (IDENTITY = 'Workspace Identity')
 *          This decouples the source read from the SP's control-plane Fabric token,
 *          so it needs no token bootstrap and never lapses.
 *
 *          NOT the Managed Identity we ruled out (Msg 13838) -- 'Workspace Identity'
 *          is a distinct, supported credential for OneLake COPY INTO.
 *          Refs: learn.microsoft.com/fabric/security/workspace-identity-authenticate
 *                learn.microsoft.com/fabric/data-warehouse/ingest-data
 *
 * PREREQUISITE (or every COPY INTO below fails with a credential error):
 *   The workspace (Regional_Data_Portal, a1b49041-0855-46de-8aca-86762132eefb) must
 *   have a WORKSPACE IDENTITY provisioned -- Workspace settings -> Workspace identity
 *   -> + Workspace identity -- and that identity must hold at least CONTRIBUTOR on the
 *   workspace (it is both the warehouse's and the source lakehouse's workspace, so one
 *   grant covers the source). Provisioning once covers DEV and LIVE (shared workspace).
 *
 * REVERT (if this doesn't work): re-run sql/scripts/deploy_dev_cutover_loaders.sql,
 *   which recreates these five procs WITHOUT the credential (caller-passthrough) --
 *   i.e. exactly the current behaviour. DROP+CREATE, so it's a clean restore.
 *
 * Idempotent: DROP IF EXISTS + GO before each CREATE. Re-runnable. DEV lakehouse
 *   GUID 8c5589bd-d04e-4e94-bb2c-482db645afab. No PII.
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/staff/Staff*'
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/sections/Sections*'
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/enrollments/Enrollments*'
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/section-teachers/Co-Teachers*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2,
        CREDENTIAL      = (IDENTITY = 'Workspace Identity')
    );
END;
GO
