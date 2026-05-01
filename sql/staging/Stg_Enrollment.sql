/*******************************************************************************
 * Table: Stg_Enrollment
 * Purpose: Landing zone for raw PowerSchool Enrollments export. All columns
 *          are VARCHAR — load-as-text, then validate/translate downstream in
 *          usp_MergeEnrollment. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Enrollments export header exactly:
 *   [1]Student_Number, SectionID, DateEnrolled, DateLeft, ID
 *
 * PS bracket-prefix naming: '[1]Student_Number' is literally the column name
 * in the export header (the [1] indicates table 1 = Students). Brackets are
 * not valid in T-SQL identifiers, so the staging column drops the prefix —
 * COPY INTO matches by position (FIRSTROW=2 skips the header).
 *
 * Export scope (per docs/export-procedures.md): currently-active enrollments
 * AND any enrollments closed since the last pull. NOT a full historical
 * roster. Anti-join in usp_MergeEnrollment closes any FactEnrollment row that
 * is currently ActiveFlag=1 in the warehouse but absent from this import.
 *
 * DateLeft auto-fill semantics: PS auto-populates DateLeft to the section's
 * term-end-date at enrollment time (so PS can auto-exit the student when the
 * term ends). DateLeft = term-end means STILL ACTIVE; DateLeft < term-end
 * means LEFT EARLY. DateLeft empty also means STILL ACTIVE. The merge proc
 * compares DateLeft against DimSection -> DimTerm to discriminate.
 ******************************************************************************/

CREATE TABLE Stg_Enrollment (
    Student_Number      VARCHAR(50)     NULL,   -- PS [1]Student_Number; provincial 10-digit student number
    SectionID           VARCHAR(50)     NULL,   -- PS section ID; matches DimSection.SectionID
    DateEnrolled        VARCHAR(20)     NULL,   -- MM/DD/YYYY format from PS
    DateLeft            VARCHAR(20)     NULL,   -- MM/DD/YYYY format; empty = still enrolled (no auto-fill)
    ID                  VARCHAR(50)     NULL    -- PS CC.ID — enrollment record ID; matching key in merge (SourceSystemID)
);
