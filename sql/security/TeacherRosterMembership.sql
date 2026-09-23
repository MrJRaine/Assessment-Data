/*******************************************************************************
 * Table: TeacherRosterMembership   (materialized FAST path for classroom teachers)
 * Purpose: The Taught-scope projection of SectionRosterMembership — one row per
 *          (TeacherEmail, AssessmentWindowID, SectionID, StudentKey) = base ⨝ the
 *          teacher's own sections (FactSectionTeachers). Carries the same static
 *          attributes as the base so a teacher's roster is a SINGLE-TABLE, JOIN-FREE,
 *          access-check-free read keyed by (TeacherEmail, GroupKey) — the hot path for
 *          the ~200 classroom teachers who open rosters constantly.
 *
 *          BOUNDED by construction: only a teacher's OWN sections, so no region-wide
 *          explosion (that's why oversight roles stay on SectionRosterMembership + a live
 *          school-access check — they're few and can afford the extra work). Because it's
 *          derived from the base in the SAME rebuild proc, the two can't drift.
 *
 *          Covers P-9 homeroom-sections and HS course-sections identically — the teacher
 *          link is FactSectionTeachers everywhere; there is no separate homeroom source.
 *
 *          Routing: the app sends a group card's Scope ('Taught' -> this table; 'Oversight'
 *          -> the base table), so a dual-role user opening their OWN class still gets the
 *          fast path. The VOLATILE results half stays LIVE in the TVF, same as the base.
 *
 * SCD Type: N/A (derived cache; TRUNCATE + rebuild each ingest — not versioned)
 * Created: 2026-09-23
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DROP TABLE IF EXISTS dbo.TeacherRosterMembership;
GO

CREATE TABLE dbo.TeacherRosterMembership (
    TeacherEmail         VARCHAR(255)    NOT NULL,   -- LOWER(FactSectionTeachers.TeacherEmail) — the read key
    AssessmentWindowID   BIGINT          NOT NULL,
    SectionID            VARCHAR(50)     NOT NULL,
    GroupKey             VARCHAR(70)     NOT NULL,    -- 'SEC:' + SectionID
    StudentKey           BIGINT          NOT NULL,
    StudentNumber        BIGINT          NOT NULL,
    FirstName            VARCHAR(100)    NOT NULL,
    LastName             VARCHAR(100)    NOT NULL,
    Grade                VARCHAR(10)     NOT NULL,
    Homeroom             VARCHAR(50)     NULL,
    SchoolName           VARCHAR(200)    NULL,
    ProgramCode          VARCHAR(10)     NOT NULL,
    ProgramFamily        VARCHAR(50)     NOT NULL,
    SchoolID             VARCHAR(10)     NOT NULL,
    LastRebuiltAt        DATETIME2(0)    NOT NULL
);
GO

GRANT SELECT ON [dbo].[TeacherRosterMembership] TO [StudentDataAssessment];
GO
