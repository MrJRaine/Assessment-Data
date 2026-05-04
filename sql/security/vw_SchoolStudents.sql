/*******************************************************************************
 * View: vw_SchoolStudents
 * Purpose: RLS-gated school admin roster — returns the current students
 *          assigned to schools the calling user has school-tier access to.
 *          One row per student (no enrollment fanout). Used by school admin
 *          dashboards in Power Apps.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. Access is
 *   gated through StaffSchoolAccess (materialized RLS-oracle table —
 *   rebuilt on every staff merge), which unpacks DimStaff's HomeSchoolID +
 *   CanChangeSchool + AccessLevel into a (StaffKey, Email, SchoolID,
 *   AccessLevel) row set. The view filters to rows where the user has
 *   access to the student's SchoolID with one of the school-tier
 *   AccessLevels:
 *     - 'Administrator'      — Principal, VP, admin assistants
 *     - 'SpecialistTeacher'  — counsellors, registrars, coordinators,
 *                              resource teachers (school-based)
 *     - 'RegionalAnalyst'    — board-level (multi-school via CanChangeSchool;
 *                              also covered by vw_RegionalData but listed
 *                              here so they see school-level rosters too)
 *
 *   Email comparison wrapped in LOWER() defensively (same rationale as
 *   vw_TeacherStudents).
 *
 * Visibility rules (DELIBERATELY LOOSER than vw_TeacherStudents):
 *   - Student must be current (IsCurrent = 1) in DimStudent.
 *   - EnrollStatus IN (0, -1) — both Active AND Pre-Enrolled visible.
 *   - NO date gate on pre-enrolled — admins see all pre-enrolled students
 *     regardless of FactEnrollment.StartDate, for roster planning purposes.
 *     Decision 2026-05-01: admins need the heads-up to plan staffing
 *     and resources before students arrive; teachers' workflow is
 *     "enter assessments for kids in front of me today" so they get the
 *     date-gated view.
 *
 * Grain: one row per StudentKey (no enrollment fanout). Students with
 * multiple section enrollments appear only once. Students attending
 * multiple schools (rare; would require multiple DimStudent versions
 * with different SchoolID) appear once per school they're
 * currently associated with — but our DimStudent model only stores ONE
 * current school per student, so this is effectively one row per student.
 *
 * Connection-identity caveat: same as vw_TeacherStudents header.
 ******************************************************************************/

CREATE VIEW vw_SchoolStudents
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.SchoolID,
    sch.SchoolName,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP,
    s.Adap,
    ssa.AccessLevel    AS UserAccessLevel
FROM DimStudent s
INNER JOIN DimSchool sch
        ON sch.SchoolID = s.SchoolID
INNER JOIN StaffSchoolAccess ssa
        ON ssa.SchoolID = s.SchoolID
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
  AND LOWER(ssa.Email) = LOWER(CURRENT_USER);
