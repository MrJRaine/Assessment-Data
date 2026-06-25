/*******************************************************************************
 * Function: tvf_StudentAssessmentHistory  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentAssessmentHistory for the
 *          web app (Phase 3b). One row per (student, completed reading
 *          assessment) for students in the signed-in user's scope. Powers the
 *          per-student detail timeline + trend line.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Adds an optional @StudentKey filter the Power App didn't need (it pulled all
 * history and filtered client-side): pass a key to scope to one student for the
 * detail screen, or NULL for the full in-scope history. Same OR-across-EXISTS
 * role branches as vw_StudentAssessmentHistory, CURRENT_USER -> LOWER(@UPN).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistory;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        CAST(far.ReadingAssessmentID AS VARCHAR(20))            AS ReadingAssessmentID,
        CAST(far.AssessmentWindowID  AS VARCHAR(20))            AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        aw.ScaleSystem,
        far.AssessmentDate,
        drs.LevelCode,
        drs.LevelOrder,
        far.ReadingDelta,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM FactAssessmentReading far
    JOIN DimStudent s ON s.StudentKey = far.StudentKey AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
    JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND far.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound))
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
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
GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistory] TO [StudentDataAssessment];
GO
