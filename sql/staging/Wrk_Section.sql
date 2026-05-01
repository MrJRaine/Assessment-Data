/*******************************************************************************
 * Table: Wrk_Section
 * Purpose: Typed working set for section merge. Populated by usp_MergeSection
 *          from Stg_Section JOIN DimStaff with all source-value translations
 *          applied:
 *            - SchoolID zero-padded to 4 chars
 *            - TermID cast to INT
 *            - No_of_students / MaxEnrollment cast to INT (empty -> NULL)
 *            - Email_Addr lowercased (matches DimStaff business key)
 *            - TeacherStaffKey resolved via JOIN DimStaff on Email + IsCurrent=1
 *              + ActiveFlag=1. Sections whose teacher email cannot be resolved
 *              are EXCLUDED from this Wrk and counted as a warning by
 *              usp_MergeSection. (DimSection.TeacherStaffKey is BIGINT NOT NULL,
 *              so we cannot land a section without a resolved teacher.)
 *            - CourseCode / SectionNumber / CourseName: empty -> NULL
 *
 *          Persisting the translated set as a real table (vs inline CTE) gives
 *          us a single, inspectable, NULL-safe payload that the SCD merge
 *          statements can JOIN against repeatedly.
 *
 *          Column shape mirrors DimSection business columns + SectionID +
 *          SourceSystemID. No SCD lifecycle columns here. TeacherEmail is
 *          carried for audit/debug visibility — only resolved emails make it
 *          into Wrk anyway.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Section (
    SectionID           VARCHAR(50)     NOT NULL,   -- Business key
    SchoolID            VARCHAR(10)     NOT NULL,   -- Zero-padded 4 chars
    TermID              INT             NOT NULL,
    CourseCode          VARCHAR(50)     NULL,
    SectionNumber       VARCHAR(20)     NULL,
    CourseName          VARCHAR(200)    NULL,
    EnrollmentCount     INT             NULL,
    MaxEnrollment       INT             NULL,
    TeacherEmail        VARCHAR(255)    NOT NULL,   -- Lowercased; carried for audit
    TeacherStaffKey     BIGINT          NOT NULL,   -- Resolved via JOIN DimStaff on Email + IsCurrent=1 + ActiveFlag=1
    SourceSystemID      VARCHAR(50)     NULL        -- Same value as SectionID for sections (PS section ID is the business key)
);
