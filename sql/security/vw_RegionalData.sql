/*******************************************************************************
 * View: vw_RegionalData
 * Purpose: RLS-gated region-wide student roster for the 10 regional analyst
 *          users. One row per student, no school filter — full regional
 *          visibility. Used by Power BI region-level reports and Power Apps
 *          regional dashboards.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS model:
 *   The calling user is identified via CURRENT_USER. Access is
 *   gated through DimStaff: the user must have a current, active row with
 *   AccessLevel = 'RegionalAnalyst'. AccessLevel is the Type 1 column
 *   denormalized onto DimStaff at staff merge time (computed from the
 *   highest-priority school-tier RoleCode in FactStaffAssignment).
 *
 *   The gate is binary at the user level — either the user IS a regional
 *   analyst (sees all rows) or they're not (sees zero rows). No row-level
 *   filtering against student attributes.
 *
 *   ProvincialAnalyst (DoE / Evaluation Services) is intentionally NOT in
 *   the access list — those accounts are excluded from the PowerApp
 *   security group entirely (confirmed 2026-04-29 with PS admin) and don't
 *   authenticate to the platform.
 *
 *   Email comparison wrapped in LOWER() defensively.
 *
 * Visibility rules:
 *   - Student must be current (IsCurrent = 1).
 *   - EnrollStatus IN (0, -1) — Active and Pre-Enrolled both visible.
 *   - NO date gate (analysts have full visibility for planning, same
 *     rationale as vw_SchoolStudents).
 *
 * Grain: one row per StudentKey. ~6000 rows region-wide at full rollout.
 *
 * Connection-identity caveat: same as vw_TeacherStudents header.
 ******************************************************************************/

CREATE VIEW vw_RegionalData
AS
SELECT
    s.StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.DateOfBirth,
    s.CurrentGrade,
    s.CurrentSchoolID,
    sch.SchoolName,
    s.ProgramCode,
    s.EnrollStatus,
    s.Homeroom,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.CurrentIPP,
    s.CurrentAdap
FROM DimStudent s
INNER JOIN DimSchool sch
        ON sch.SchoolID = s.CurrentSchoolID
WHERE s.IsCurrent = 1
  AND s.EnrollStatus IN (0, -1)
  AND EXISTS (
      SELECT 1
      FROM DimStaff st
      WHERE LOWER(st.Email) = LOWER(CURRENT_USER)
        AND st.IsCurrent   = 1
        AND st.ActiveFlag  = 1
        AND st.AccessLevel = 'RegionalAnalyst'
  );
