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
 * COPY INTO config locked in during Step 7:
 *   FILE_TYPE       = 'CSV'
 *   FIELDTERMINATOR = '\t'      (PS direct extracts are TAB-delimited)
 *   ROWTERMINATOR   = '0x0D'    (PS direct extracts use CR-only line endings)
 *   FIRSTROW        = 2         (skip header)
 * UTF-8 is the default; ENCODING parameter is not supported by Fabric.
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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/students/AssessmentData*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',
        FIRSTROW        = 2
    );
END;
