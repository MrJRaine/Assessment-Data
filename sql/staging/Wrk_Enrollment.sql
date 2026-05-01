/*******************************************************************************
 * Table: Wrk_Enrollment
 * Purpose: Typed working set for enrollment merge. Populated by
 *          usp_MergeEnrollment from Stg_Enrollment INNER-JOINed against
 *          DimStudent / DimSection / DimTerm with all source-value
 *          translations applied:
 *            - Student_Number cast to BIGINT
 *            - DateEnrolled MM/DD/YYYY -> DATE
 *            - DateLeft MM/DD/YYYY -> DATE (empty -> NULL)
 *            - StudentKey resolved via JOIN DimStudent on StudentNumber +
 *              IsCurrent=1. Rows that fail resolution are EXCLUDED from
 *              this Wrk and counted as a warning by usp_MergeEnrollment.
 *            - SectionKey resolved via JOIN DimSection on SectionID +
 *              IsCurrent=1. Same exclusion semantics on failure.
 *            - ActiveFlag computed via DimSection.TermID -> DimTerm:
 *                DateLeft IS NULL                          -> 1 (still active)
 *                DateLeft month-year matches term-end      -> 1 (PS auto-fill,
 *                                                                 still active)
 *                DateLeft otherwise                        -> 0 (left early)
 *            - EndDate = DateLeft verbatim (NULL if empty)
 *
 *          Term-end month derivation:
 *            TermCode 0 (Year Long) -> June, year = SchoolYearEnd
 *            TermCode 1 (Semester 1) -> January, year = SchoolYearEnd
 *            TermCode 2 (Semester 2) -> June, year = SchoolYearEnd
 *
 *          Tolerance: month-only match (anywhere in the canonical term-end
 *          month counts as auto-fill). PS may shift the auto-fill date by a
 *          few days to the nearest school day, so a tighter day-level check
 *          would generate false LEFT-EARLY flags. Edge case: a student who
 *          left in the first week of June would be misclassified as "still
 *          active". Acceptable for MVP; revisit if this misclassification
 *          shows up in real data.
 *
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Enrollment (
    StudentNumber       BIGINT          NOT NULL,
    SectionID           VARCHAR(50)     NOT NULL,
    StudentKey          BIGINT          NOT NULL,   -- Resolved via JOIN DimStudent IsCurrent=1
    SectionKey          BIGINT          NOT NULL,   -- Resolved via JOIN DimSection IsCurrent=1
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NULL,       -- = DateLeft verbatim (NULL when DateLeft empty)
    ActiveFlag          BIT             NOT NULL,   -- Computed (see header)
    SourceSystemID      VARCHAR(50)     NOT NULL    -- PS CC.ID — matching key in FactEnrollment merge
);
