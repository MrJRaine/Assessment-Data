/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentCohort for the web app
 *          (Phase 3b). The app connects as the StudentDataAssessment service
 *          principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped view returns nothing. This iTVF takes the signed-in
 *          UPN and runs the SAME OR-across-EXISTS role branches (RegionalAnalyst
 *          / Administrator+SpecialistTeacher / Teacher), so admins/analysts get
 *          their full multi-school cohort.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * One row per student in scope + most-recent (lifetime) reading evidence, the
 * Reading-IPP gate, and the achievement band/colour for that latest delta.
 * Mirrors vw_StudentCohort verbatim except CURRENT_USER -> LOWER(@UPN). Keep the
 * two in sync until the Power App is retired.
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (the
 * client never supplies it). See tvf_UserAssessmentWindows header.
 * ORDER BY intentionally omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestReading AS (
        SELECT
            far.StudentKey,
            far.ReadingAssessmentID,
            far.AssessmentWindowID,
            far.ReadingScaleID,
            far.ReadingDelta,
            far.AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY far.StudentKey
                ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading far
    ),
    CurrentReadingIPP AS (
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
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        crd.IsIPP                                               AS IsIPP_Reading,
        CASE
            WHEN crd.StudentKey IS NULL THEN 'N/A'
            WHEN crd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN crd.IsIPP = 1          THEN 'IPP'
            WHEN crd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Reading,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        lr.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        drs.LevelCode                                           AS MostRecentLevelCode,
        drs.LevelOrder                                          AS MostRecentLevelOrder,
        lr.ReadingDelta                                         AS MostRecentReadingDelta,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestReading lr ON lr.StudentKey = s.StudentKey AND lr.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lr.AssessmentWindowID
    LEFT JOIN DimReadingScale drs ON drs.ReadingScaleID = lr.ReadingScaleID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
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
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO
