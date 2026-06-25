/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping (Teacher / SchoolAdmin+SpecialistTeacher /
 *          RegionalAnalyst role branches, window-date roster reconciliation,
 *          group filtering) -- only the per-student entry context differs:
 *          the MOST RECENT writing entry's four trait scores + their average +
 *          achievement band, plus Writing-IPP status. No benchmark / delta
 *          (writing has none). One row per student for the given window + group.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKey VARCHAR(60))
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily, sec.SectionID
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.ProgramCode, a.ProgramFamily, sec.SectionID
        FROM AdminAnalystApplicable a
        LEFT JOIN FactEnrollment e
               ON a.GradeOrder >= 10
              AND e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramFamily,
            CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
                 WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
            END AS GroupKey
        FROM ApplicableStudents
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            CAST((IdeasScore + OrganizationScore + LanguageScore + ConventionsScore) / 4.0 AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        faw.IdeasScore         AS ExistingIdeasScore,
        faw.OrganizationScore  AS ExistingOrganizationScore,
        faw.LanguageScore      AS ExistingLanguageScore,
        faw.ConventionsScore   AS ExistingConventionsScore,
        faw.AvgScore           AS ExistingAvgScore,
        faw.AssessmentDate     AS ExistingAssessmentDate,
        ipp.IsIPP              AS WritingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS WritingIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily) AS IPPProgramFamily,
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND faw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN faw.AvgScore >= 3.50 THEN 4
                   WHEN faw.AvgScore >= 2.75 THEN 3
                   WHEN faw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE sg.GroupKey = @GroupKey
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO
