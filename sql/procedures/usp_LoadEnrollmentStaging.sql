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
