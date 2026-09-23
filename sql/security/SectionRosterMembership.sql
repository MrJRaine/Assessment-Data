/*******************************************************************************
 * Table: SectionRosterMembership   (materialized roster skeleton — the SOURCE OF TRUTH)
 * Purpose: Pre-joins the expensive, ingest-STABLE half of the entry roster — which
 *          students sit in which subject-mapped section for each active window, plus
 *          their static display attributes. Rebuilt every ingest by
 *          usp_RebuildRosterMembership. The roster TVFs read this instead of
 *          re-deriving the DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram
 *          join at query time (which measured ~2s for a 20-student roster on 2026-09-23).
 *
 *          VIEWER-INDEPENDENT on purpose: keyed by SECTION, not by teacher/analyst, so an
 *          oversight role (Administrator/SpecialistTeacher/RegionalAnalyst) can never
 *          explode this table region-wide. Access is applied LIVE in the TVF as a predicate
 *          on the few requested sections (FactSectionTeachers / StaffSchoolAccess). The
 *          fast teacher path reads the derived TeacherRosterMembership table instead.
 *
 *          FRESHNESS: roster membership already only changes on ingest (enrolment/section/
 *          staff come from the PowerSchool batch), so materializing it at ingest cadence
 *          introduces ZERO new staleness — same data, same clock, just pre-joined.
 *
 *          Grain: one row per (AssessmentWindowID, SectionID, StudentKey) across
 *          ActiveFlag=1 windows, restricted to sections mapped to that window's subject
 *          via DimCourseAssessment. The VOLATILE half (reading/writing/math results,
 *          deltas, benchmarks, IPP, achievement, starting point) stays LIVE in the TVF.
 *
 * SCD Type: N/A (derived cache; TRUNCATE + rebuild each ingest — not versioned)
 * Created: 2026-09-23
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE IF EXISTS dbo.SectionRosterMembership;
GO

CREATE TABLE dbo.SectionRosterMembership (
    AssessmentWindowID   BIGINT          NOT NULL,   -- DimAssessmentWindow.AssessmentWindowID (subject-specific)
    SectionKey           BIGINT          NOT NULL,   -- the DimSection version valid on WindowEffectiveDate
    SectionID            VARCHAR(50)     NOT NULL,    -- business key; the FactSectionTeachers / GroupKey anchor
    SchoolID             VARCHAR(10)     NOT NULL,    -- for the oversight StaffSchoolAccess check
    GroupKey             VARCHAR(70)     NOT NULL,    -- 'SEC:' + SectionID (what the app passes as @GroupKeys)
    SectionLanguage      VARCHAR(10)     NULL,        -- DimCourseAssessment.Language of the section's course
                                                      -- ('English'/'French' for literacy, NULL for Math). The
                                                      -- writing roster filters the EN/FR toggle by THIS (the
                                                      -- section decides the language, NOT the student's program).
    WindowEffectiveDate  DATE            NOT NULL,    -- MIN(rebuild day, window EndDate); drives the TVF's live access date-check
    StudentKey           BIGINT          NOT NULL,   -- the DimStudent version FactEnrollment points at
    StudentNumber        BIGINT          NOT NULL,   -- provincial 10-digit number (stable across SCD versions)
    FirstName            VARCHAR(100)    NOT NULL,
    LastName             VARCHAR(100)    NOT NULL,
    Grade                VARCHAR(10)     NOT NULL,
    Homeroom             VARCHAR(50)     NULL,        -- DimStudent.Homeroom display label
    SchoolName           VARCHAR(200)    NULL,
    ProgramCode          VARCHAR(10)     NOT NULL,
    ProgramFamily        VARCHAR(50)     NOT NULL,
    LastRebuiltAt        DATETIME2(0)    NOT NULL     -- stamp of the rebuild that wrote this row
);
GO

-- The web-app SP reads this table THROUGH the roster TVFs. Grant SELECT so the read
-- resolves whether or not Fabric applies ownership chaining (StaffSchoolAccess is granted
-- the same way). RLS is enforced in the TVF via the @UPN access predicate, not here.
GRANT SELECT ON [dbo].[SectionRosterMembership] TO [StudentDataAssessment];
GO
