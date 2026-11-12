/*******************************************************************************
 * Function: tvf_MissingDataAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for Reports > Missing results (1.3.1): per selected cycle, every
 *          EXPECTED data point (section x student x subject) with an IsMissing bit, so the
 *          client builds the TCRCE -> School -> Lead teacher -> Section roll-up of students
 *          who still need a result entered. Expected = SectionRosterMembership rows for the
 *          cycle's active windows — exactly what the entry grids roster, so "expected" always
 *          matches what a teacher is actually asked to enter.
 * Created: 2026-11-12
 * Region: Canada East (PIIDPA compliant)
 *
 * ACCESS: Administrator / RegionalAnalyst ONLY (per-school StaffSchoolAccess rows — NO
 * region-wide branch; an RA simply has every building listed). Teachers and Specialist
 * Teachers have no branch and get ZERO rows (user decision 2026-11-12).
 *
 * "Reported" per subject:
 *   Reading / Writing — any fact row for (StudentNumber, that cycle window).
 *   Math             — recorded results on >= 80% of the grade's configured tasks for the
 *                      window's benchmark month (the same 80% threshold the entry grid uses
 *                      before it shows a unit achievement level; user decision 2026-11-12).
 *                      A grade with NO configured tasks at that month has nothing to enter,
 *                      so those rows are NOT expected (dropped, not counted missing).
 *
 * EXCLUDED: students with a CONFIRMED IPP (IsCurrent=1 AND IsIPP=1) in a subject are not
 * expected in THAT subject (subject-only match, keyed by StudentNumber — same treatment as
 * tvf_StudentCohortRWM's AnyIPP; a flagged-but-unconfirmed IPP still counts as expected).
 *
 * Lead teacher = FactSectionTeachers TeacherRole='Primary', IsCurrent=1 (first by email when
 * data ever holds two); NULL teacher columns = no current Primary -> client shows a visible
 * "No lead teacher" node, never a silent drop.
 *
 * READS: SectionRosterMembership, DimAssessmentWindow, DimCalendar (benchmark-month fallback),
 * FactAssessmentReading/Writing/Math, DimMathTask, FactStudentIPP + DimStudent (StudentNumber
 * keying), FactSectionTeachers, DimStaff (teacher name), DimSection (course/section label),
 * StaffSchoolAccess (gate). WRITES: nothing.
 *
 * PRIVACY: no student names here — StudentNumber only (needed so a multi-section student
 * counts once in teacher/school totals). Names load per-section via tvf_MissingDataGroup.
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_MissingDataAll;
GO

CREATE FUNCTION dbo.tvf_MissingDataAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36))
RETURNS TABLE
AS
RETURN
(
    WITH CycleWins AS (   -- the selected cycle's active windows + effective benchmark month (math)
        SELECT w.AssessmentWindowID, w.AssessmentType,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1 AND w.CycleGroupID = @CycleGroupID
    ),
    -- Expected data points the caller may see: membership rows for the cycle's windows, gated
    -- per school (Admin/RA only), minus confirmed same-subject IPPs.
    Expected AS (
        SELECT cw.AssessmentType, cw.AssessmentWindowID, cw.BenchMonth,
               m.SectionID, m.SchoolID, m.SchoolName, m.StudentNumber, m.Grade
        FROM SectionRosterMembership m
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = m.AssessmentWindowID
        WHERE EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
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
    -- Math task universe: configured tasks per grade at the math window's benchmark month.
    MathTaskUniverse AS (
        SELECT cw.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        INNER JOIN CycleWins cw ON cw.AssessmentType = 'Math' AND mt.AssessmentMonth = cw.BenchMonth
        WHERE mt.ActiveFlag = 1
        GROUP BY cw.AssessmentWindowID, mt.GradeCode
    ),
    -- Distinct configured tasks each student has a recorded result on, in the math window.
    MathFilled AS (
        SELECT fm.StudentNumber, fm.AssessmentWindowID, mt.GradeCode,
               COUNT(DISTINCT fm.MathTaskKey) AS FilledCount
        FROM FactAssessmentMath fm
        INNER JOIN CycleWins cw ON cw.AssessmentWindowID = fm.AssessmentWindowID
                               AND cw.AssessmentType = 'Math'
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = fm.MathTaskKey
                                 AND mt.ActiveFlag = 1 AND mt.AssessmentMonth = cw.BenchMonth
        GROUP BY fm.StudentNumber, fm.AssessmentWindowID, mt.GradeCode
    ),
    LeadTeacher AS (   -- one Primary per section (rn guards a double-Primary data quirk)
        SELECT fst.SectionID, fst.TeacherEmail,
               ROW_NUMBER() OVER (PARTITION BY fst.SectionID ORDER BY fst.TeacherEmail) AS rn
        FROM FactSectionTeachers fst
        WHERE fst.TeacherRole = 'Primary' AND fst.IsCurrent = 1
    )
    SELECT
        e.AssessmentType,
        e.SchoolID,
        e.SchoolName,
        e.SectionID,
        sec.CourseName,
        sec.SectionNumber,
        lt.TeacherEmail,
        CASE WHEN st.Email IS NULL THEN NULL
             ELSE CONCAT(st.FirstName, ' ', st.LastName) END AS TeacherName,
        e.Grade,
        e.StudentNumber,
        CAST(CASE WHEN e.AssessmentType = 'Reading' AND rr.StudentNumber IS NOT NULL THEN 0
                  WHEN e.AssessmentType = 'Writing' AND wr.StudentNumber IS NOT NULL THEN 0
                  WHEN e.AssessmentType = 'Math'
                       AND COALESCE(mf.FilledCount, 0) * 1.0 >= 0.8 * tu.ConfiguredCount THEN 0
                  ELSE 1 END AS BIT) AS IsMissing
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
    LEFT JOIN LeadTeacher lt ON lt.SectionID = e.SectionID AND lt.rn = 1
    LEFT JOIN DimStaff st ON LOWER(st.Email) = lt.TeacherEmail AND st.IsCurrent = 1
    LEFT JOIN DimSection sec ON sec.SectionID = e.SectionID AND sec.IsCurrent = 1
    -- A math grade with no configured tasks this cycle has nothing to enter: not expected.
    WHERE (e.AssessmentType <> 'Math' OR tu.ConfiguredCount IS NOT NULL)
);
GO

GRANT SELECT ON [dbo].[tvf_MissingDataAll] TO [StudentDataAssessment];
GO
