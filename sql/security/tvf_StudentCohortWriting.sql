/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentCohort for the web app's cohort
 *          screen (Reading|Writing toggle). One row per student in the signed-in
 *          user's scope + their MOST-RECENT writing evidence: the four trait
 *          scores (Ideas/Organization/Language/Conventions), their average, and
 *          the achievement band that average falls in. Plus the Writing-IPP gate.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Achievement band: writing has NO benchmark/delta. The average of the four
 * 1-4 traits maps to a band CODE by fixed cut scores, and that code joins
 * DimAchievementLevel to reuse the SAME band names + colours as reading:
 *     avg >= 3.50 -> 4 Exceeding | >= 2.75 -> 3 Meeting | >= 1.75 -> 2 Approaching | else 1 Not Yet Meeting
 * (No Domain filter needed: we join DimAchievementLevel by code, for name/colour
 * only -- its reading delta bounds are not used here.)
 *
 * Role branches (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher)
 * are identical to tvf_StudentCohort -- caller passed as @UPN. SECURITY: trusts
 * @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestWriting AS (
        SELECT
            faw.StudentKey,
            faw.WritingAssessmentID,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            CAST((faw.IdeasScore + faw.OrganizationScore + faw.LanguageScore + faw.ConventionsScore) / 4.0 AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (
                PARTITION BY faw.StudentKey
                ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting faw
    ),
    CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
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
        cwd.IsIPP                                               AS IsIPP_Writing,
        CASE
            WHEN cwd.StudentKey IS NULL THEN 'N/A'
            WHEN cwd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN cwd.IsIPP = 1          THEN 'IPP'
            WHEN cwd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Writing,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        lw.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        lw.IdeasScore                                           AS MostRecentIdeasScore,
        lw.OrganizationScore                                    AS MostRecentOrganizationScore,
        lw.LanguageScore                                        AS MostRecentLanguageScore,
        lw.ConventionsScore                                     AS MostRecentConventionsScore,
        lw.AvgScore                                             AS MostRecentAvgScore,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestWriting lw ON lw.StudentKey = s.StudentKey AND lw.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lw.AssessmentWindowID
    -- Map the average to a band CODE, then reuse DimAchievementLevel's name + colour by code.
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
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

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO
