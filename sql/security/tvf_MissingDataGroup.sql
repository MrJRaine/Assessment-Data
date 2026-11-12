/*******************************************************************************
 * Function: tvf_MissingDataGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY drill for Reports > Missing results (1.3.1): ONE section's students who
 *          still need a result entered for the selected cycle — one row per (student x missing
 *          subject), WITH names (the roll-up feed tvf_MissingDataAll is deliberately name-free;
 *          names load here on expand, same two-tier pattern as the Reading/Writing trees).
 * Created: 2026-11-12
 * Region: Canada East (PIIDPA compliant)
 *
 * SAME DEFINITIONS as tvf_MissingDataAll — keep the two in LOCKSTEP:
 *   expected = SectionRosterMembership rows for the cycle's active windows;
 *   reported = any Reading/Writing fact in the window; Math >= 80% of the grade's configured
 *              benchmark-month tasks (entry-grid threshold);
 *   excluded = confirmed same-subject IPP (IsCurrent=1 AND IsIPP=1, by StudentNumber);
 *   access   = Administrator / RegionalAnalyst per-school StaffSchoolAccess rows ONLY.
 *
 * READS: SectionRosterMembership, DimAssessmentWindow, DimCalendar, FactAssessmentReading/
 * Writing/Math, DimMathTask, FactStudentIPP + DimStudent, StaffSchoolAccess. WRITES: nothing.
 * SECURITY: trusts @UPN; SELECT granted to the SP only. A @SectionID outside the caller's
 * scope returns no rows. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_MissingDataGroup;
GO

CREATE FUNCTION dbo.tvf_MissingDataGroup(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36), @SectionID VARCHAR(50))
RETURNS TABLE
AS
RETURN
(
    WITH CycleWins AS (
        SELECT w.AssessmentWindowID, w.AssessmentType,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1 AND w.CycleGroupID = @CycleGroupID
    ),
    Expected AS (   -- this section's expected data points the caller may see
        SELECT cw.AssessmentType, cw.AssessmentWindowID, cw.BenchMonth,
               m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom
        FROM SectionRosterMembership m
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = m.AssessmentWindowID
        WHERE m.SectionID = @SectionID
          AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                      WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = m.SchoolID
                        AND ssa.AccessLevel IN ('Administrator', 'RegionalAnalyst'))
          AND NOT EXISTS (SELECT 1 FROM FactStudentIPP fsi
                          INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
                          WHERE ds.StudentNumber = m.StudentNumber
                            AND fsi.Subject = cw.AssessmentType
                            AND fsi.IsCurrent = 1 AND fsi.IsIPP = 1)
    ),
    ReadReported AS (
        SELECT DISTINCT far.StudentNumber, far.AssessmentWindowID
        FROM FactAssessmentReading far
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = far.AssessmentWindowID
                               AND cw.AssessmentType = 'Reading'
    ),
    WriteReported AS (
        SELECT DISTINCT faw.StudentNumber, faw.AssessmentWindowID
        FROM FactAssessmentWriting faw
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = faw.AssessmentWindowID
                               AND cw.AssessmentType = 'Writing'
    ),
    MathTaskUniverse AS (
        SELECT cw.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        INNER JOIN CycleWins cw ON cw.AssessmentType = 'Math' AND mt.AssessmentMonth = cw.BenchMonth
        WHERE mt.ActiveFlag = 1
        GROUP BY cw.AssessmentWindowID, mt.GradeCode
    ),
    MathFilled AS (
        SELECT fm.StudentNumber, fm.AssessmentWindowID, mt.GradeCode,
               COUNT(DISTINCT fm.MathTaskKey) AS FilledCount
        FROM FactAssessmentMath fm
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = fm.AssessmentWindowID
                               AND cw.AssessmentType = 'Math'
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = fm.MathTaskKey
                                 AND mt.ActiveFlag = 1 AND mt.AssessmentMonth = cw.BenchMonth
        GROUP BY fm.StudentNumber, fm.AssessmentWindowID, mt.GradeCode
    )
    SELECT
        e.AssessmentType,
        e.StudentNumber,
        e.FirstName,
        e.LastName,
        e.Grade,
        e.Homeroom
    FROM Expected e
    LEFT JOIN ReadReported rr  ON e.AssessmentType = 'Reading'
                              AND rr.StudentNumber = e.StudentNumber
                              AND rr.AssessmentWindowID = e.AssessmentWindowID
    LEFT JOIN WriteReported wr ON e.AssessmentType = 'Writing'
                              AND wr.StudentNumber = e.StudentNumber
                              AND wr.AssessmentWindowID = e.AssessmentWindowID
    LEFT JOIN MathTaskUniverse tu ON e.AssessmentType = 'Math'
                                 AND tu.AssessmentWindowID = e.AssessmentWindowID
                                 AND tu.GradeCode = e.Grade
    LEFT JOIN MathFilled mf ON e.AssessmentType = 'Math'
                           AND mf.StudentNumber = e.StudentNumber
                           AND mf.AssessmentWindowID = e.AssessmentWindowID
                           AND mf.GradeCode = e.Grade
    -- Only the MISSING rows (this drill answers "who needs data entered here"), and a math
    -- grade with no configured tasks this cycle is not expected at all.
    WHERE (e.AssessmentType <> 'Math' OR tu.ConfiguredCount IS NOT NULL)
      AND CASE WHEN e.AssessmentType = 'Reading' AND rr.StudentNumber IS NOT NULL THEN 0
               WHEN e.AssessmentType = 'Writing' AND wr.StudentNumber IS NOT NULL THEN 0
               WHEN e.AssessmentType = 'Math'
                    AND COALESCE(mf.FilledCount, 0) * 1.0 >= 0.8 * tu.ConfiguredCount THEN 0
               ELSE 1 END = 1
);
GO

GRANT SELECT ON [dbo].[tvf_MissingDataGroup] TO [StudentDataAssessment];
GO
