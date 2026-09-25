/*───────────────────────────────────────────────────────────────────────────────────────────
  diag_math_report_blank_roster.sql — investigate: Math report card shows "23 students" but the
  matrix says "No students in this group" (live 0.7.0; seen at Carleton Consolidated / Homeroom
  Doucette, while other schools render fine).

  HYPOTHESIS: tvf_StudentCohortMath ends with  FROM GroupStudents gs INNER JOIN Tasks t ON
  t.GradeCode = gs.Grade.  Tasks = active DimMathTask for the group's grades AT the current-year
  math benchmark months.  If those grades have NO active tasks configured on live (e.g. only
  Primary is seeded), the INNER JOIN drops EVERY student -> 0 rows -> "No students in this group".
  Meanwhile the PICKER (tvf_MathCohortGroups) counts students regardless of tasks -> card says 23.
  So: a homeroom whose grades have no seeded math tasks = full card count, empty matrix.

  READS ONLY (no writes): DimAssessmentWindow, DimCalendar, DimMathTask, DimStudent, DimGrade,
  DimSchool. Run against LIVE. Reports counts only — no student PII rows.

  Set the two vars if the affected homeroom differs.
───────────────────────────────────────────────────────────────────────────────────────────*/
DECLARE @School   VARCHAR(100) = 'Carleton Consolidated Elementary School';
DECLARE @Homeroom VARCHAR(100) = 'Doucette';

-- current school year (Sep-Aug) + this year's math windows' benchmark months
DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
DECLARE @Yr VARCHAR(9) = CASE WHEN MONTH(@Today) >= 9
                              THEN CONCAT(YEAR(@Today), '-', YEAR(@Today) + 1)
                              ELSE CONCAT(YEAR(@Today) - 1, '-', YEAR(@Today)) END;

WITH MathWins AS (
    SELECT w.AssessmentWindowID,
           COALESCE(w.BenchmarkMonth,
               (SELECT TOP 1 dc.Month FROM DimCalendar dc
                WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
    FROM DimAssessmentWindow w
    WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = @Yr
),
-- active task count per grade at THIS year's math months (the matrix's Tasks universe)
TasksByGrade AS (
    SELECT mt.GradeCode, COUNT(*) AS ActiveTaskCount
    FROM DimMathTask mt
    WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    GROUP BY mt.GradeCode
)
-- the affected homeroom's P-6 students by grade, vs whether that grade has any tasks
SELECT s.Grade,
       COUNT(*)                              AS StudentsInHomeroom,
       COALESCE(tg.ActiveTaskCount, 0)       AS ActiveMathTasksForGrade,
       CASE WHEN COALESCE(tg.ActiveTaskCount, 0) = 0
            THEN '<-- no tasks: these students vanish from the matrix'
            ELSE 'ok' END                    AS Note
FROM DimStudent s
INNER JOIN DimGrade  g   ON g.GradeCode  = s.Grade AND g.GradeOrder BETWEEN 0 AND 6
LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
LEFT  JOIN TasksByGrade tg ON tg.GradeCode = s.Grade
WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
  AND s.Homeroom = @Homeroom
  AND (sch.SchoolName = @School OR @School IS NULL)
GROUP BY s.Grade, COALESCE(tg.ActiveTaskCount, 0)
ORDER BY s.Grade;

-- Also: the full math-task universe on live, by grade + month (is anything past Primary seeded?)
SELECT mt.GradeCode, mt.AssessmentMonth, COUNT(*) AS ActiveTasks
FROM DimMathTask mt
WHERE mt.ActiveFlag = 1
GROUP BY mt.GradeCode, mt.AssessmentMonth
ORDER BY mt.GradeCode, mt.AssessmentMonth;
