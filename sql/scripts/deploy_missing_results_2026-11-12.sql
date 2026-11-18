/*******************************************************************************
 * Deploy: Missing-results report TVFs (Reports > Missing results, 1.4.0)
 * Date: 2026-11-12 (rev b 2026-11-13)   Target: Assessment_Warehouse_Dev FIRST, then live
 * Creates the two inline TVFs behind the new Administrator/RegionalAnalyst-only
 * Missing results roll-up (TCRCE -> School -> Lead teacher -> Section -> students
 * still needing a result for the selected cycle):
 *   1. tvf_MissingDataAll    (roll-up feed - expected x missing bits, no names)
 *   2. tvf_MissingDataGroup  (per-section drill - missing students, with names)
 * Rev b (2026-11-13): lead teacher is now the CYCLE's Primary - most recent
 * FactSectionTeachers Primary whose effective dates overlap the cycle span -
 * instead of IsCurrent=1 (user ruling: teacher attribution on reports is
 * historic, as-of the cycle viewed). RERUN REQUIRED even if rev a already ran.
 * READS: SectionRosterMembership, DimAssessmentWindow, DimCalendar,
 * FactAssessmentReading/Writing/Math, DimMathTask, FactStudentIPP, DimStudent,
 * FactSectionTeachers, DimStaff, DimSection, StaffSchoolAccess.
 * WRITES: nothing - DROP/CREATE of the two iTVFs + re-GRANT to
 * StudentDataAssessment only. Idempotent: safe to re-run.
 * Assembled verbatim from sql/security sources.
 ******************************************************************************/
/*******************************************************************************
 * Function: tvf_MissingDataAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for Reports > Missing results (1.4.0): per selected cycle, every
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
 * Lead teacher = the CYCLE's Primary (user ruling 2026-11-13: any report that displays a
 * teacher resolves them as of the cycle being viewed, never "today"): the most recent
 * FactSectionTeachers TeacherRole='Primary' row whose EffectiveStartDate/EndDate overlap the
 * cycle's span (latest start wins a mid-cycle handover; email tiebreak guards a double-Primary
 * quirk). The name comes from the teacher's current DimStaff identity row, so a since-departed
 * teacher still shows by name. NULL teacher columns = NO Primary overlapped the cycle at all ->
 * client shows a visible "No lead teacher" node, never a silent drop.
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
    CycleSpan AS (   -- the selected cycle's overall date span, for historic teacher resolution
        SELECT MIN(w.StartDate) AS CycleStart, MAX(w.EndDate) AS CycleEnd
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1 AND w.CycleGroupID = @CycleGroupID
    ),
    LeadTeacher AS (   -- the CYCLE's Primary per section: most recent Primary whose assignment
                       -- overlaps the cycle span (user ruling 2026-11-13 — teacher attribution on
                       -- reports is historic, as-of the cycle; rn breaks a mid-cycle handover
                       -- toward the later teacher and guards the double-Primary data quirk)
        SELECT fst.SectionID, fst.TeacherEmail,
               ROW_NUMBER() OVER (PARTITION BY fst.SectionID
                                  ORDER BY fst.EffectiveStartDate DESC, fst.TeacherEmail) AS rn
        FROM FactSectionTeachers fst
        CROSS JOIN CycleSpan cs
        WHERE fst.TeacherRole = 'Primary'
          AND fst.EffectiveStartDate <= cs.CycleEnd
          AND (fst.EffectiveEndDate IS NULL OR fst.EffectiveEndDate >= cs.CycleStart)
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
/*******************************************************************************
 * Function: tvf_MissingDataGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY drill for Reports > Missing results (1.4.0): ONE section's students who
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
