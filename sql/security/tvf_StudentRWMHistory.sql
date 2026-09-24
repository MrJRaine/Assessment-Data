/*******************************************************************************
 * Function: tvf_StudentRWMHistory  (INLINE table-valued function)
 * Purpose: Per-cycle RWM trend for the Reports > RWM individual page (0.7.0, item 5).
 *          One row per monthly SCoR cycle in the current school year, carrying the
 *          student's AS-OF standing in each area (most-recent result up to the end of
 *          that month) and the resulting 0-3 RWM score. Powers the per-cycle table +
 *          the trend graph.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * A "cycle" here is a calendar month that has >=1 active assessment window this school
 * year (Reading, Writing and Math windows for the same month collapse to one cycle).
 * For each cycle we take the student's most-recent evidence in each area DATED on or
 * before the end of that month, so the 0-3 score is cumulative and reads as a trend.
 * "Meeting+" definitions match tvf_StudentCohortRWM (reading/writing code IN (3,4),
 * math roll-up >= 0.75). @StudentKey passed as VARCHAR to dodge Power Fx BIGINT loss.
 *
 * SECURITY: trusts @UPN; only returns rows when the student is visible to @UPN (same
 * OR-across-EXISTS role gate as the cohort TVFs). SELECT granted to the SP only.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentRWMHistory;
GO

CREATE FUNCTION dbo.tvf_StudentRWMHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH Env AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    CurYear AS (
        SELECT CASE WHEN MONTH(e.Today) >= 9 THEN CONCAT(YEAR(e.Today), '-', YEAR(e.Today) + 1)
                    ELSE CONCAT(YEAR(e.Today) - 1, '-', YEAR(e.Today)) END AS Yr
        FROM Env e
    ),
    MathWins AS (
        SELECT w.AssessmentWindowID
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
    ),
    -- Only proceed when the caller can see this student.
    Visible AS (
        SELECT s.StudentKey
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.StudentKey = CAST(@StudentKey AS BIGINT)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment en ON en.SectionKey = sec.SectionKey AND en.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND en.StudentKey = s.StudentKey)
          )
    ),
    -- Monthly cycles this school year, up to the current month (no empty future cycles).
    Cycles AS (
        SELECT DISTINCT
               DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1) AS CycleDate,
               EOMONTH(DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1)) AS CycleEnd
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        CROSS JOIN Env e
        WHERE w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1) <= DATEFROMPARTS(YEAR(e.Today), MONTH(e.Today), 1)
    ),
    -- Reading events (dated) with their achievement code.
    ReadEvents AS (
        SELECT far.AssessmentDate, far.ReadingAssessmentID, dal.AchievementLevelCode AS Code
        FROM FactAssessmentReading far
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
        WHERE far.StudentKey = CAST(@StudentKey AS BIGINT)
    ),
    -- Writing events (dated) with their band code.
    WriteEvents AS (
        SELECT faw.AssessmentDate, faw.WritingAssessmentID,
               CASE WHEN avg4.AvgScore IS NULL THEN NULL
                    WHEN avg4.AvgScore >= 3.50 THEN 4
                    WHEN avg4.AvgScore >= 2.75 THEN 3
                    WHEN avg4.AvgScore >= 1.75 THEN 2
                    ELSE 1 END AS Code
        FROM FactAssessmentWriting faw
        CROSS APPLY (SELECT CAST(
                   (COALESCE(faw.IdeasScore, 0) + COALESCE(faw.OrganizationScore, 0) + COALESCE(faw.LanguageScore, 0)
                    + COALESCE(TRY_CAST(faw.ConventionsScore AS INT), 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore IS NOT NULL THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IS NOT NULL THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore IS NOT NULL THEN 1 ELSE 0 END)
                          + (CASE WHEN TRY_CAST(faw.ConventionsScore AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore) avg4
        WHERE faw.StudentKey = CAST(@StudentKey AS BIGINT)
    )
    SELECT
        c.CycleDate,
        DATENAME(MONTH, c.CycleDate) + ' ' + CAST(YEAR(c.CycleDate) AS VARCHAR(4)) AS CycleLabel,
        rc.Code               AS ReadingCode,
        wc.Code               AS WritingCode,
        CAST(mc.RollupPct AS DECIMAL(5,4)) AS MathRollupPct,
        CAST(CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS ReadingMeeting,
        CAST(CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS WritingMeeting,
        CAST(CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)  AS MathMeeting,
        (CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END)          AS RWMScore
    FROM Cycles c
    CROSS JOIN Visible v      -- no rows if the student isn't visible to @UPN
    -- most-recent reading on/before this cycle's month end
    OUTER APPLY (
        SELECT TOP 1 re.Code
        FROM ReadEvents re
        WHERE re.AssessmentDate <= c.CycleEnd
        ORDER BY re.AssessmentDate DESC, re.ReadingAssessmentID DESC
    ) rc
    OUTER APPLY (
        SELECT TOP 1 we.Code
        FROM WriteEvents we
        WHERE we.AssessmentDate <= c.CycleEnd
        ORDER BY we.AssessmentDate DESC, we.WritingAssessmentID DESC
    ) wc
    -- math roll-up as-of this cycle: latest result per task on/before month end -> unit avgs -> mean
    OUTER APPLY (
        SELECT AVG(u.UnitAvg) AS RollupPct
        FROM (
            SELECT mt.UnitName, AVG(CAST(x.Result AS FLOAT)) AS UnitAvg
            FROM (
                SELECT fm.MathTaskKey, fm.Result,
                       ROW_NUMBER() OVER (PARTITION BY fm.MathTaskKey
                                          ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
                FROM FactAssessmentMath fm
                WHERE fm.StudentKey = CAST(@StudentKey AS BIGINT)
                  AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
                  AND fm.AssessmentDate <= c.CycleEnd
            ) x
            INNER JOIN DimMathTask mt ON mt.MathTaskKey = x.MathTaskKey AND mt.ActiveFlag = 1
            WHERE x.rn = 1
            GROUP BY mt.UnitName
        ) u
    ) mc
);
GO

GRANT SELECT ON [dbo].[tvf_StudentRWMHistory] TO [StudentDataAssessment];
GO
