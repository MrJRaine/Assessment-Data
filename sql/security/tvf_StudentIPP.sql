/*******************************************************************************
 * Function: tvf_StudentIPP  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentIPP for the web app
 *          (Phase 3b) -- the bulk IPP-management screen (/ipp, mirrors the Power
 *          App scrIPP). One row per (Student, Subject, ProgramFamily) with a
 *          current FactStudentIPP row, in the signed-in user's scope. The SP
 *          can't use CURRENT_USER RLS, so this runs the SAME OR-across-EXISTS
 *          role branches (RegionalAnalyst / Administrator+SpecialistTeacher /
 *          Teacher) with CURRENT_USER -> LOWER(@UPN).
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). Mirrors vw_StudentIPP -- keep in sync until
 * the Power App is retired. ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentIPP;
GO

CREATE FUNCTION dbo.tvf_StudentIPP(@UPN VARCHAR(255))
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
        fsi.Subject,
        fsi.ProgramFamily                      AS IPPProgramFamily,
        fsi.IsIPP
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN FactStudentIPP fsi ON fsi.StudentKey = s.StudentKey AND fsi.IsCurrent = 1
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
GRANT SELECT ON [dbo].[tvf_StudentIPP] TO [StudentDataAssessment];
GO
