/*******************************************************************************
 * Script:  diag_demo_seed_scope_dev.sql   (DEV synthetic only — READ ONLY)
 * Purpose: seed_demo_results_dev produced 0 rows (blank step-4 summary) after a
 *          full reset + re-ingest. This walks the SAME resolution + join chain the
 *          seed uses and reports a row count at each stage, so the stage that drops
 *          to 0 is the break. No writes — SELECTs only.
 * Mirrors: seed_demo_results_dev.sql (§1 resolve, §3b Reading-SC1 funnel, §3d Math).
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_demo_seed_scope_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

DECLARE @JuneCGID  VARCHAR(36) = '6a11e000-2026-406e-9c17-0de100062026';
DECLARE @SC1CGID   VARCHAR(36);
DECLARE @SeedStaff BIGINT;

SELECT TOP 1 @SC1CGID = CycleGroupID
FROM dbo.DimShortCycle
WHERE ActiveFlag = 1 AND CycleGroupID <> @JuneCGID
ORDER BY StartDate ASC, CycleGroupID;

SELECT TOP 1 @SeedStaff = StaffKey
FROM dbo.DimStaff
WHERE IsCurrent = 1 AND ActiveFlag = 1
ORDER BY CASE WHEN AccessLevel = 'RegionalAnalyst' THEN 0 ELSE 1 END, StaffKey;

------------------------------------------------------------------------------
-- A. What the seed resolved. @SC1CGID / @SeedStaff NULL here = the seed would THROW.
------------------------------------------------------------------------------
SELECT 'A. resolved' AS Stage,
       @SC1CGID   AS SC1_CycleGroupID,
       @SeedStaff AS SeedStaffKey,
       (SELECT COUNT(*) FROM dbo.DimShortCycle WHERE ActiveFlag = 1)        AS ActiveShortCycles,
       (SELECT COUNT(*) FROM dbo.DimStudent WHERE IsCurrent = 1)            AS CurrentStudents;

-- A2. The cycle the seed treats as SC1 (name/date) + ALL active cycles, to confirm it picked the right one.
SELECT 'A2. active cycles' AS Stage, CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag
FROM dbo.DimShortCycle WHERE ActiveFlag = 1 ORDER BY StartDate;

-- A3. The seed staff row (used as EnteredByStaffKey AND the step-4 summary filter).
SELECT 'A3. seed staff' AS Stage, StaffKey, FirstName, LastName, AccessLevel, IsCurrent, ActiveFlag
FROM dbo.DimStaff WHERE StaffKey = @SeedStaff;

------------------------------------------------------------------------------
-- B. DimAssessmentWindow instances for SC1. If this is empty, step 2 copies NO June
--    windows and EVERY reading/writing/math insert joins to nothing => all 0.
------------------------------------------------------------------------------
-- (STRING_AGG dropped — uncertain in Fabric; B2 lists ProgramScope/ScaleSystem per row instead.)
SELECT 'B. SC1 windows' AS Stage, AssessmentType, COUNT(*) AS Windows, MIN(SchoolYear) AS SchoolYear
FROM dbo.DimAssessmentWindow
WHERE CycleGroupID = @SC1CGID AND ActiveFlag = 1
GROUP BY AssessmentType;

-- B2. Full window rows for SC1 (scope/scale/grade band the inserts match on).
SELECT 'B2. SC1 window rows' AS Stage, AssessmentWindowID, AssessmentType, SchoolYear,
       MinGrade, MaxGrade, ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage, BenchmarkMonth
FROM dbo.DimAssessmentWindow
WHERE CycleGroupID = @SC1CGID
ORDER BY AssessmentType, ProgramScope;

-- B3. June windows (created by the seed's step 2). 0 here is expected BEFORE a successful run.
SELECT 'B3. June windows' AS Stage, AssessmentType, COUNT(*) AS Windows
FROM dbo.DimAssessmentWindow WHERE CycleGroupID = @JuneCGID GROUP BY AssessmentType;

------------------------------------------------------------------------------
-- C. ProgramScope match — the seed joins students to windows via
--    (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%').
--    If the ingested students' ProgramCode -> ScopeBucket doesn't appear in any
--    SC1 window's ProgramScope, the join is empty. Lists each ScopeBucket in the
--    data and whether a Reading SC1 window covers it.
------------------------------------------------------------------------------
;WITH Buckets AS (   -- distinct program scope buckets in the ingested students + headcount
    SELECT p.ScopeBucket, COUNT(*) AS StudentsWithBucket
    FROM dbo.DimStudent s
    JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
    WHERE s.IsCurrent = 1
    GROUP BY p.ScopeBucket
),
Covered AS (          -- buckets a Reading SC1 window actually covers (subquery pulled OUT of the aggregate)
    SELECT DISTINCT p.ScopeBucket
    FROM dbo.DimProgram p
    JOIN dbo.DimAssessmentWindow w
          ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
         AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
)
SELECT 'C. scope buckets' AS Stage, b.ScopeBucket, b.StudentsWithBucket,
       CASE WHEN c.ScopeBucket IS NULL THEN 0 ELSE 1 END AS CoveredByReadingWindow
FROM Buckets b
LEFT JOIN Covered c ON c.ScopeBucket = b.ScopeBucket;

-- C2. Students whose ProgramCode has NO DimProgram row (inner join would DROP them entirely).
SELECT 'C2. unmapped ProgramCode' AS Stage, s.ProgramCode, COUNT(*) AS Students
FROM dbo.DimStudent s
LEFT JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
WHERE s.IsCurrent = 1 AND p.ProgramCode IS NULL
GROUP BY s.ProgramCode;

------------------------------------------------------------------------------
-- D. Reading SC1 funnel — count survivors stage by stage (mirrors §3b joins).
--    The first column that falls to 0 is where the seed loses all its rows.
------------------------------------------------------------------------------
SELECT 'D. reading SC1 funnel' AS Stage,
   (SELECT COUNT(*) FROM dbo.DimStudent s WHERE s.IsCurrent = 1)                                    AS s1_students,
   (SELECT COUNT(*) FROM dbo.DimStudent s
      JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
      JOIN dbo.DimGrade cg ON cg.GradeCode = s.Grade
      WHERE s.IsCurrent = 1)                                                                         AS s2_prog_grade,
   (SELECT COUNT(*) FROM dbo.DimStudent s
      JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
      JOIN dbo.DimGrade cg ON cg.GradeCode = s.Grade
      JOIN dbo.DimAssessmentWindow w ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Reading'
            AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
      JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
      JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
      WHERE s.IsCurrent = 1 AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder)           AS s3_in_window,
   (SELECT COUNT(*) FROM dbo.DimStudent s
      JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
      JOIN dbo.DimGrade cg ON cg.GradeCode = s.Grade
      JOIN dbo.DimAssessmentWindow w ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Reading'
            AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
      JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
      JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
      JOIN dbo.DimReadingBenchmark rb ON rb.ScaleSystem = w.ScaleSystem AND rb.GradeCode = s.Grade
            AND rb.AssessmentMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate))
      WHERE s.IsCurrent = 1 AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder)           AS s4_benchmark_match;

-- D2. Reading benchmark coverage — which (ScaleSystem, AssessmentMonth) pairs exist.
SELECT 'D2. benchmark months' AS Stage, ScaleSystem, AssessmentMonth, COUNT(*) AS Rows
FROM dbo.DimReadingBenchmark GROUP BY ScaleSystem, AssessmentMonth ORDER BY ScaleSystem, AssessmentMonth;

------------------------------------------------------------------------------
-- E. Math SC1 funnel — DimMathTask match (§3d: GradeCode + AssessmentMonth + ActiveFlag).
------------------------------------------------------------------------------
SELECT 'E. math SC1 window' AS Stage, COUNT(*) AS MathWindows,
       MIN(COALESCE(BenchmarkMonth, MONTH(StartDate))) AS EffBenchmarkMonth
FROM dbo.DimAssessmentWindow WHERE CycleGroupID = @SC1CGID AND AssessmentType = 'Math' AND ActiveFlag = 1;

SELECT 'E2. math tasks by grade/month' AS Stage, GradeCode, AssessmentMonth, COUNT(*) AS Tasks
FROM dbo.DimMathTask WHERE ActiveFlag = 1 GROUP BY GradeCode, AssessmentMonth ORDER BY GradeCode, AssessmentMonth;
