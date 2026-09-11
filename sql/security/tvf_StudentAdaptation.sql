/*******************************************************************************
 * Function: tvf_StudentAdaptation  (INLINE table-valued function)
 * Purpose: @UPN-parameterized per-student ADAPTATION status for the web app's
 *          Programming > Adaptations roster. Structural mirror of tvf_StudentIPP,
 *          reading FactStudentAdaptation instead of FactStudentIPP. One row per
 *          (Student, Subject, ProgramFamily) with a current FactStudentAdaptation
 *          row, in the signed-in user's scope. Same OR-across-EXISTS role branches
 *          (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher), with
 *          CURRENT_USER -> LOWER(@UPN) since the SP can't use CURRENT_USER RLS.
 *
 *          The client pivots these flat rows into the collapsed roster's cells
 *          (one row per student, Reading|Writing|Math columns); FI grade-3+
 *          literacy students appear with BOTH an 'English' and a 'French Immersion'
 *          row, which drives the 4-way No/FLA-Only/ELA-Only/Both control.
 * Created: 2026-09-11
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see tvf_StudentIPP /
 * tvf_UserAssessmentWindows headers). Adaptations are record-only (no gating).
 * ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAdaptation;
GO

CREATE FUNCTION dbo.tvf_StudentAdaptation(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))      AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        s.Homeroom,
        s.SchoolID,
        p.ProgramFamily                        AS StudentProgramFamily,
        fsa.Subject,
        fsa.ProgramFamily                      AS AdaptationProgramFamily,
        fsa.HasAdaptation
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN FactStudentAdaptation fsa ON fsa.StudentKey = s.StudentKey AND fsa.IsCurrent = 1
    WHERE s.IsCurrent = 1
      AND (
            EXISTS (
                SELECT 1 FROM DimStaff staff
                WHERE LOWER(staff.Email) = LOWER(@UPN)
                  AND staff.IsCurrent    = 1
                  AND staff.AccessLevel  = 'RegionalAnalyst'
            )
            OR EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentAdaptation] TO [StudentDataAssessment];
GO
