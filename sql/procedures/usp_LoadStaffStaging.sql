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
 * COPY INTO config locked in during Step 7:
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = '\t'      (PS direct extracts are TAB-delimited)
 *   ROWTERMINATOR   = '0x0D'    (PS direct extracts use CR-only line endings)
 *   FIRSTROW        = 2         (skip header)
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/staff/AssessmentData*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
