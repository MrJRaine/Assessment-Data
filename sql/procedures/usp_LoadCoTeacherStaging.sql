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
    FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/section-teachers/AssessmentData*'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = ',',
        FIELDQUOTE      = '"',
        FIRSTROW        = 2
    );
END;
