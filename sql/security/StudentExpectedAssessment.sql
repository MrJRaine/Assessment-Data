/*******************************************************************************
 * Table: StudentExpectedAssessment   (materialized "who is expected to be assessed")
 * Purpose: Per-student, per-cycle EXPECTED assessment set — which (Subject x Language) each
 *          student is supposed to be assessed in, derived PURELY from config: their enrolled
 *          mapped-course literacy sections (DimCourseAssessment language) intersected with the
 *          active cycle INSTANCES (DimAssessmentWindow scope: ProgramScope, grade band, language).
 *          NO hardcoded program/grade rules — it is a student-grain DISTINCT projection of
 *          SectionRosterMembership joined to DimAssessmentWindow, rebuilt every ingest by
 *          usp_RebuildRosterMembership (right after the membership tables it reads).
 *
 *          The reports read this to drive the EN/FR split in the student list / roll-up drill:
 *          a (student, subject, language) row here = "expected" (so the language's row shows, with
 *          '-' until a result lands); no row = "not applicable" (that language's row is not shown).
 *
 *          Grain: one row per (StudentKey, CycleGroupID, AssessmentType, Language). Literacy only
 *          (Reading/Writing with a concrete English/French course language); Math is single-track
 *          and excluded. Match reads on the STABLE StudentNumber (mirrors the fact-SCD policy).
 *
 * SCD Type: N/A (derived cache; TRUNCATE + rebuild each ingest — not versioned)
 * Created: 2026-10-20
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE IF EXISTS dbo.StudentExpectedAssessment;
GO

CREATE TABLE dbo.StudentExpectedAssessment (
    StudentKey     BIGINT        NOT NULL,   -- current DimStudent version (SectionRosterMembership.StudentKey)
    StudentNumber  BIGINT        NOT NULL,   -- provincial 10-digit (stable; reads match on this)
    CycleGroupID   VARCHAR(36)   NOT NULL,   -- the cycle this expectation belongs to (DimAssessmentWindow.CycleGroupID)
    AssessmentType VARCHAR(20)   NOT NULL,   -- 'Reading' | 'Writing'
    Language       VARCHAR(10)   NOT NULL,   -- 'English' | 'French' (the section's course language)
    LastRebuiltAt  DATETIME2(0)  NOT NULL
);
GO

GRANT SELECT ON [dbo].[StudentExpectedAssessment] TO [StudentDataAssessment];
GO
