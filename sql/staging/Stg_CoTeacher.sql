/*******************************************************************************
 * Table: Stg_CoTeacher
 * Purpose: Landing zone for the PowerSchool Co-Teachers sqlReport export. All
 *          columns are VARCHAR — load-as-text, then validate/translate
 *          downstream in usp_MergeSectionTeachers. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Co-Teachers report header exactly:
 *   School, TermID, Course, Section, Teacher, Email, Role, SectionID
 *
 * Format quirks (Export 4 — sqlReport, NOT a direct table extract):
 *   - Comma-delimited (FIELDTERMINATOR = ',')
 *   - .csv extension
 *   - CRLF line endings (default ROWTERMINATOR — no override needed)
 *   - Double-quote text qualifier (FIELDQUOTE = '"') — required because the
 *     Teacher column emits values like "Hazel, Glade" containing commas
 *
 * Optional export: per docs/export-procedures.md, this report is skipped
 * entirely if PS does not track co-teaching. usp_MergeSectionTeachers must
 * tolerate Stg_CoTeacher being empty — primary teachers (from Stg_Section)
 * are still ingested.
 *
 * Only Email, Role, and SectionID are used by the merge — School/TermID/
 * Course/Section/Teacher are captured for audit/debug visibility only.
 ******************************************************************************/

CREATE TABLE Stg_CoTeacher (
    School              VARCHAR(100)    NULL,   -- Display label only — not used by merge
    TermID              VARCHAR(10)     NULL,   -- Display label only
    Course              VARCHAR(50)     NULL,   -- Display label only
    Section             VARCHAR(20)     NULL,   -- Display label only
    Teacher             VARCHAR(200)    NULL,   -- "LastName, FirstName" display label only
    Email               VARCHAR(255)    NULL,   -- Lowercased and used as TeacherEmail in merge
    Role                VARCHAR(50)     NULL,   -- 'Co-teacher' / 'Support' / etc — normalized in merge
    SectionID           VARCHAR(50)     NULL    -- Joins to DimSection.SectionID / Stg_Section.ID
);
