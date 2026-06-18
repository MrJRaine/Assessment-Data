/*******************************************************************************
 * View: vw_StudentCohortTeachers
 * Purpose: Companion bridge view to vw_StudentCohort for the scrStudentData
 *          Teacher filter (Pack B). One row per (student, teacher) pair in the
 *          calling user's scope — a student appears once per distinct current
 *          section teacher. Power Apps uses it two ways:
 *            1. Teacher combo options: distinct (TeacherEmail, TeacherName)
 *            2. Filter predicate: cohort StudentKey membership against the
 *               pairs whose TeacherEmail is selected
 *
 *          Consumed by:
 *            - scrStudentData cmbFltTeacher (admin/analyst-gated multi-select)
 *
 * Created: 2026-06-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: DISTINCT (StudentKey, TeacherEmail, TeacherName). TeacherRole is
 *   deliberately excluded — a teacher covering the same student in two roles
 *   or two sections still yields one row, which is the grain the filter needs.
 *
 * Teacher resolution: current section teachers only — FactSectionTeachers
 *   (IsCurrent = 1) via DimSection (IsCurrent = 1) joined to active
 *   enrollments (FactEnrollment.ActiveFlag = 1). This matches the cohort
 *   screen's current-state semantics (vw_StudentCohort is current-roster
 *   scoped); historical-roster reconciliation deliberately does NOT apply
 *   here — that pattern is reserved for the window-context views.
 *
 * TeacherName: DimStaff (IsCurrent = 1) FirstName + LastName via lowercased
 *   email match; falls back to the raw TeacherEmail if the staff row is
 *   missing (e.g. teacher not yet in a staff import).
 *
 * RLS branching: identical OR-across-EXISTS block to vw_StudentCohort —
 *   Regional Analyst (all), Admin/SpecialistTeacher (their schools via
 *   StaffSchoolAccess), Teacher (their section roster). Keep the two views'
 *   RLS blocks in sync if either changes. Uses CURRENT_USER (Fabric Warehouse
 *   does not support USERPRINCIPALNAME()).
 *
 * Power Apps binding notes:
 *   - StudentKey CAST to VARCHAR(20) to match vw_StudentCohort.StudentKey
 *     (BIGINT precision — see project_powerapps_bigint_precision memory).
 *   - NEW data source: must be ADDED in Studio (first-time add picks up the
 *     current schema; no refresh dance needed).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentCohortTeachers;
GO

CREATE VIEW vw_StudentCohortTeachers AS
SELECT DISTINCT
    CAST(s.StudentKey AS VARCHAR(20))                        AS StudentKey,
    LOWER(fst.TeacherEmail)                                  AS TeacherEmail,
    COALESCE(staff.FirstName + ' ' + staff.LastName,
             LOWER(fst.TeacherEmail))                        AS TeacherName
FROM DimStudent s
JOIN FactEnrollment e
    ON  e.StudentKey = s.StudentKey
    AND e.ActiveFlag = 1
JOIN DimSection sec
    ON  sec.SectionKey = e.SectionKey
    AND sec.IsCurrent  = 1
JOIN FactSectionTeachers fst
    ON  fst.SectionID = sec.SectionID
    AND fst.IsCurrent = 1
LEFT JOIN DimStaff staff
    ON  LOWER(staff.Email) = LOWER(fst.TeacherEmail)
    AND staff.IsCurrent    = 1
WHERE s.IsCurrent     = 1
  AND s.EnrollStatus IN (0, -1)
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff st
            WHERE LOWER(st.Email)  = LOWER(CURRENT_USER)
              AND st.IsCurrent     = 1
              AND st.AccessLevel   = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email)  = LOWER(CURRENT_USER)
              AND ssa.SchoolID      = s.SchoolID
              AND ssa.AccessLevel  IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst2
            JOIN   DimSection sec2
                ON sec2.SectionID = fst2.SectionID
               AND sec2.IsCurrent = 1
            JOIN   FactEnrollment e2
                ON e2.SectionKey  = sec2.SectionKey
               AND e2.ActiveFlag  = 1
            WHERE LOWER(fst2.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst2.IsCurrent = 1
              AND e2.StudentKey  = s.StudentKey
        )
      );
GO
