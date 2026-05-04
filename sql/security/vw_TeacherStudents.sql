/*******************************************************************************
 * View: vw_TeacherStudents
 * Purpose: RLS-gated teacher roster — returns the current students enrolled
 *          in sections taught by the calling user. One row per (student ×
 *          section assignment). Used by the Power Apps assessment-entry
 *          form to populate the student dropdown for a given section.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. The view joins
 *   FactSectionTeachers (which keys on TeacherEmail directly — decoupled
 *   from DimSection / DimStaff versioning per the 2026-04-28 design
 *   decision) and filters to only rows whose TeacherEmail matches the
 *   current user. No DimStaff lookup needed for the access check.
 *
 *   Email comparison is wrapped in LOWER() on both sides:
 *     - DimStaff.Email and FactSectionTeachers.TeacherEmail are lowercased
 *       at ingest, so the DB side is already lowercase.
 *     - CURRENT_USER casing is environment-dependent (typically
 *       lowercase in Entra ID but not guaranteed). LOWER() defends against
 *       a mismatch.
 *
 * Visibility rules:
 *   - Student must be current (IsCurrent = 1) in DimStudent.
 *   - EnrollStatus IN (0, -1) — Active or Pre-Enrolled. Inactive (2) and
 *     Graduated (3) are filtered out at PS export upstream and never reach
 *     the warehouse, so this filter is defense-in-depth.
 *   - FactEnrollment.ActiveFlag = 1 — only currently-active enrollments.
 *   - Section must be current (DimSection.IsCurrent = 1).
 *   - FactSectionTeachers row must be current (IsCurrent = 1).
 *   - Universal date gate: FactEnrollment.StartDate <= today. This is
 *     primarily for pre-enrolled students (they appear on the teacher's
 *     roster automatically on the day their start date arrives, even if
 *     the next ingest hasn't run yet). Also correctly hides active students
 *     with future-dated enrollments (e.g. a transfer student pre-registered
 *     for a section starting next semester).
 *
 * Grain: one row per (StudentKey × SectionID × TeacherRole). A student
 * enrolled in two sections taught by the same teacher appears twice. A
 * student enrolled in one section with a Primary teacher and a CoTeacher
 * appears in EACH teacher's view (once per teacher, not multiple times
 * for the same teacher).
 *
 * Connection-identity caveat:
 *   CURRENT_USER returns the connection's authenticated identity.
 *   This works correctly when:
 *     - Power Apps is configured with Entra ID identity passthrough to
 *       the Fabric SQL endpoint
 *     - Power BI semantic model uses DirectQuery with the user's Entra
 *       identity propagated
 *   It does NOT work as expected if the connection uses a service
 *   principal or a shared service account — in that case all queries
 *   return rows for the SP, not the end user. RLS would then need to
 *   move into the Power BI semantic model (DAX-based RLS roles). Confirm
 *   the Power Apps connection mode at Step 16 (Power Apps → Fabric SQL
 *   endpoint connection setup).
 ******************************************************************************/

CREATE VIEW vw_TeacherStudents
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.SchoolID,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP,
    s.Adap,
    sec.SectionKey,
    sec.SectionID,
    sec.CourseCode,
    sec.SectionNumber,
    sec.CourseName,
    fst.TeacherEmail,
    fst.TeacherRole,
    e.StartDate     AS EnrollmentStartDate,
    e.EndDate       AS EnrollmentEndDate
FROM DimStudent s
INNER JOIN FactEnrollment e
        ON e.StudentKey = s.StudentKey
       AND e.ActiveFlag = 1
       AND e.StartDate <= CAST(GETDATE() AS DATE)
INNER JOIN DimSection sec
        ON sec.SectionKey = e.SectionKey
       AND sec.IsCurrent  = 1
INNER JOIN FactSectionTeachers fst
        ON fst.SectionID = sec.SectionID
       AND fst.IsCurrent = 1
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER);
