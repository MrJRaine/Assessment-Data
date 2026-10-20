/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded — the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup. Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped);
 * band CODE by the writing cut scores (reused name + colour from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName
        FROM DimStudent s
        INNER JOIN DimGrade g ON g.GradeCode = s.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = s.StudentKey)
          )
    ),
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.AssessmentLanguage,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS WritingIPPStatus,
        lw.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        lw.IdeasScore,
        lw.OrganizationScore,
        lw.LanguageScore,
        lw.ConventionsScore,
        lw.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentKey = gs.StudentKey
    LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw ON lw.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO
