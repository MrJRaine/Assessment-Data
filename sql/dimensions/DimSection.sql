/*******************************************************************************
 * Table: DimSection
 * Purpose: Instructional sections and their teacher-of-record assignments over time
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *            2026-04-24 - Added TermID (PS 4-digit term value). Joins to DimTerm
 *                         to decode school year and Year Long / S1 / S2.
 *            2026-04-28 - Added 4 fields: SectionNumber, CourseName,
 *                         EnrollmentCount, MaxEnrollment. SectionNumber and
 *                         CourseName are display metadata for the Power App
 *                         section picker UX. EnrollmentCount and MaxEnrollment
 *                         are stored to avoid re-aggregating FactEnrollment for
 *                         every Power BI visual that needs them.
 *            2026-04-28 - SCD policy change: ALL business attributes are now
 *                         Type 2 triggers (was: only TeacherStaffKey). Same
 *                         rationale as DimStudent and DimStaff: reports cite
 *                         point-in-time values and must reproduce regardless
 *                         of intervening changes. Note: EnrollmentCount Type 2
 *                         means DimSection versions whenever enrollments shift.
 *            2026-04-28 - DimSection versioning no longer cascades to
 *                         FactSectionTeachers. That bridge was reworked to
 *                         reference business keys (SectionID, TeacherEmail)
 *                         instead of surrogates, so it's now independent of
 *                         this dim's version history.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2).
-- The only fields that DON'T are the lifecycle/audit columns:
--   SectionKey, SectionID, EffectiveStartDate, EffectiveEndDate, IsCurrent,
--   SourceSystemID, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   SchoolID, TermID, CourseCode, SectionNumber, CourseName, EnrollmentCount,
--   MaxEnrollment, TeacherStaffKey
--
-- TeacherStaffKey references DimStaff surrogate key — not the business key.
-- TermID is effectively immutable per section (PS sections are year/term-specific),
-- so while it's a Type 2 trigger it should not actually change for a given SectionID.
-- EnrollmentCount changes as students enroll/withdraw, so this dimension will
-- accumulate versions throughout the school year. This is fine because
-- FactSectionTeachers does NOT cascade off DimSection — it references SectionID
-- (business key) and reconciles independently by (SectionID, TeacherEmail,
-- TeacherRole). DimSection's TeacherStaffKey remains a denormalized "primary
-- teacher of record" snapshot for reporting only.

CREATE TABLE DimSection (
    SectionKey          BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    SectionID           VARCHAR(50)     NOT NULL,           -- Business key, same across all versions
    SchoolID            VARCHAR(10)     NOT NULL,           -- 4-digit provincial school number
    TermID              INT             NOT NULL,           -- PS TermID (e.g. 3501); joins to DimTerm
    CourseCode          VARCHAR(50)     NULL,
    SectionNumber       VARCHAR(20)     NULL,               -- PS Section_Number — school-set, e.g. '01', '02'
    CourseName          VARCHAR(200)    NULL,               -- PS Courses.course_name — display label for Power App
    EnrollmentCount     INT             NULL,               -- PS No_of_students — current enrollment count
    MaxEnrollment       INT             NULL,               -- PS MaxEnrollment — capacity (lower for special programs)
    TeacherStaffKey     BIGINT          NOT NULL,           -- References DimStaff.StaffKey
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,               -- PowerSchool section ID
    LastUpdated         DATETIME2(0)    NOT NULL
);
