/*******************************************************************************
 * Table: Stg_Section
 * Purpose: Landing zone for raw PowerSchool Sections export. All columns are
 *          VARCHAR — load-as-text, then validate/translate downstream in
 *          usp_MergeSection. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Sections export header exactly:
 *   ID, SchoolID, TermID, Course_Number, Section_Number, [2]course_name,
 *   No_of_students, MaxEnrollment, [5]Email_Addr
 *
 * PS bracket-prefix naming:
 *   The PS export header literally contains '[2]course_name' and
 *   '[5]Email_Addr' as column names — the bracket prefixes denote
 *   cross-table joins on the PS side (table 2 = Courses, table 5 = Teachers).
 *   The brackets cannot appear in a T-SQL identifier, so the staging columns
 *   below use the unprefixed form. COPY INTO matches by position (FIRSTROW=2
 *   skips the header), so the column-name divergence between header and
 *   staging table is fine.
 *
 * Filter expectation: PS export is pre-filtered to current school year only
 * (TermID 3500-3599 for 2025-2026). Absence from the import means the
 * section no longer exists in the active term — usp_MergeSection close-only
 * (no replacement) on missing sections.
 ******************************************************************************/

CREATE TABLE Stg_Section (
    ID                  VARCHAR(50)     NULL,   -- PS section ID; populates DimSection.SectionID and SourceSystemID
    SchoolID            VARCHAR(10)     NULL,   -- 4-digit provincial school number; PS strips leading zeros — pad in merge
    TermID              VARCHAR(10)     NULL,   -- PS 4-digit term value (e.g. '3500'); cast to INT in merge
    Course_Number       VARCHAR(50)     NULL,   -- Maps to DimSection.CourseCode
    Section_Number      VARCHAR(20)     NULL,
    course_name         VARCHAR(200)    NULL,   -- PS [2]course_name (bracket prefix dropped — see header note)
    No_of_students      VARCHAR(20)     NULL,   -- Maps to DimSection.EnrollmentCount
    MaxEnrollment       VARCHAR(20)     NULL,
    Email_Addr          VARCHAR(255)    NULL    -- PS [5]Email_Addr — primary teacher email; resolved to TeacherStaffKey in merge
);
