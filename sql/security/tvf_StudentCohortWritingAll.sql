/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only — no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a writing result they have this year):
 *   - FactAssessmentWriting.AssessmentLanguage IS part of the grain (unlike reading, which derives it
 *     from the scale), so a student with an English and a French writing result has TWO fact rows and
 *     gets TWO rows here ('English' / 'French'); one language => one row; no writing result => ONE row,
 *     AssessmentLanguage NULL ("No data").
 *
 * MEASURE: the band CODE of the latest writing AVERAGE for that (student, language), by the SAME cut
 *   scores as tvf_StudentCohortWriting (avg>=3.50->4, >=2.75->3, >=1.75->2, else 1; NULL avg->NULL code).
 *   Client % Meeting/Exceeding = rows with code >= 3 / rows with ANY code, IPP excluded (via the flag).
 *   Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped from numerator AND denominator).
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess.
 * @CycleGroupID NULL = all current-year Writing windows; a cycle id restricts the latest-pick. Grades =
 *   the span of the selected Writing windows' MinGrade..MaxGrade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
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
    LatestWriting AS (   -- latest result per (student, language) across the selected windows + its average
        SELECT faw.StudentNumber, faw.AssessmentLanguage, faw.AssessmentDate,
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
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS WritingIPPStatus,
        lw.AssessmentLanguage,                               -- 'English' | 'French'; NULL = no writing result
        lw.AssessmentDate                 AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        CASE WHEN lw.AvgScore IS NULL THEN NULL
             WHEN lw.AvgScore >= 3.50 THEN 4
             WHEN lw.AvgScore >= 2.75 THEN 3
             WHEN lw.AvgScore >= 1.75 THEN 2
             ELSE 1 END                   AS AchievementLevelCode
    FROM DimStudent s
    INNER JOIN DimGrade g ON g.GradeCode = s.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN WritingIPP ipp ON ipp.StudentKey = s.StudentKey
    LEFT  JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw ON lw.StudentNumber = s.StudentNumber
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingAll] TO [StudentDataAssessment];
GO
