/*******************************************************************************
 * 1.2.0 LIVE deploy — Math scope Primary-5 + Math reports oversight roll-up tree.
 * Run once against Assessment_Warehouse (live), in one paste. Re-run safe:
 *   - the four functions are DROP-IF-EXISTS + CREATE + GRANT;
 *   - the Math band step only touches Math windows still at MaxGrade '6'.
 * READS ONLY except Step 5 (DimAssessmentWindow.MaxGrade / LastUpdated, Math rows).
 * Region: Canada East (PIIDPA compliant)
 *
 *   1. tvf_MathCohortGroups      (redeploy — P-5)
 *   2. tvf_StudentCohortMath     (redeploy — P-5)
 *   3. tvf_StudentCohortRWM      (redeploy — P-5)
 *   4. tvf_StudentCohortMathAll  (NEW — oversight roll-up tree feed)
 *   5. Math cycle windows MaxGrade 6 -> 5
 *   6. Verify (counts only — no student rows)
 *
 * NOTE: Step 5 is deliberately NARROWER than sql/scripts/set_cycle_grade_ranges_by_subject.sql,
 * which also resets every Reading/Writing window's band and would overwrite bands configured
 * per cycle instance on /cycles.
 ******************************************************************************/

-- ==================== sql/security/tvf_MathCohortGroups.sql ====================
/*******************************************************************************
 * Function: tvf_MathCohortGroups  (INLINE table-valued function)
 * Purpose: @UPN choose-a-group resolution for the Reports > Math cohort (0.7.0, item 4).
 *          The math cohort matrix is group-scoped (a whole school/region is unusable), so the
 *          caller first picks a HOMEROOM or a GRADE cohort; this returns those groups. Same shape
 *          as tvf_TeacherGroups / tvf_ProgrammingGroups so the existing GroupCards renders it.
 *          Over ALL current P-6 students (math is P-6) — NOT flagged-only like Programming.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * TWO SCOPES (client toggles): 'Taught' = the caller's own current sections' students;
 * 'Oversight' = Administrator/SpecialistTeacher/RegionalAnalyst -> the students in the schools they
 * cover via StaffSchoolAccess. GroupKey scheme matches tvf_StudentCohortMath's resolver: a homeroom
 * key is DimStudent.GroupKey; a grade cohort is 'GRADE:'+SchoolID+':'+Grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_MathCohortGroups;
GO

CREATE FUNCTION dbo.tvf_MathCohortGroups(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    -- P-6 current students in scope, tagged Taught / Oversight.
    Students AS (
        SELECT DISTINCT s.StudentKey, s.Grade, s.Homeroom, s.GroupKey AS HomeroomKey, s.SchoolID,
               sch.SchoolName, CAST('Taught' AS VARCHAR(10)) AS Scope
        FROM Caller c
        INNER JOIN FactSectionTeachers fst ON LOWER(fst.TeacherEmail) = c.Email AND fst.IsCurrent = 1
        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        INNER JOIN DimGrade sg ON sg.GradeCode = s.Grade
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE sg.GradeOrder BETWEEN 0 AND 5   -- Math = Primary..Grade 5 (grade 6 not ready 2026-27)

        UNION ALL

        SELECT DISTINCT s.StudentKey, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               sch.SchoolName, CAST('Oversight' AS VARCHAR(10))
        FROM Caller c
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s ON s.SchoolID = ssa.SchoolID AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        INNER JOIN DimGrade sg ON sg.GradeCode = s.Grade
        LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
          AND sg.GradeOrder BETWEEN 0 AND 5   -- Math = Primary..Grade 5 (grade 6 not ready 2026-27)
    ),
    -- Homeroom lens + Grade lens (the two the user asked for).
    GroupRows AS (
        SELECT Scope, StudentKey, Grade, SchoolName,
               CAST('Homeroom' AS VARCHAR(10)) AS GroupType,
               HomeroomKey AS GroupKey,
               CONCAT('Homeroom', ' ', COALESCE(Homeroom, '(none)')) AS GroupLabel
        FROM Students
        UNION ALL
        SELECT Scope, StudentKey, Grade, SchoolName,
               CAST('Grade' AS VARCHAR(10)),
               'GRADE:' + SchoolID + ':' + Grade,
               CASE Grade WHEN 'P' THEN 'Primary' WHEN 'PP' THEN 'Pre-Primary'
                          ELSE CONCAT('Grade', ' ', Grade) END
        FROM Students
    ),
    GroupGrades AS (
        SELECT Scope, GroupType, GroupKey, STRING_AGG(Grade, ',') AS Grades
        FROM (SELECT DISTINCT Scope, GroupType, GroupKey, Grade FROM GroupRows WHERE GroupKey IS NOT NULL AND Grade IS NOT NULL) d
        GROUP BY Scope, GroupType, GroupKey
    )
    SELECT
        gr.Scope,
        gr.GroupType,
        gr.GroupKey,
        gr.GroupLabel,
        MAX(gr.SchoolName) AS SchoolName,
        MAX(gr.Grade)      AS Grade,
        MAX(gg.Grades)     AS Grades,
        COUNT(DISTINCT gr.StudentKey) AS ApplicableStudentCount,
        CAST(0 AS INT)                AS EnteredStudentCount   -- reports picker: no entered count
    FROM GroupRows gr
    LEFT JOIN GroupGrades gg
           ON gg.Scope = gr.Scope AND gg.GroupType = gr.GroupType AND gg.GroupKey = gr.GroupKey
    WHERE gr.GroupKey IS NOT NULL
    GROUP BY gr.Scope, gr.GroupType, gr.GroupKey, gr.GroupLabel
);
GO

GRANT SELECT ON [dbo].[tvf_MathCohortGroups] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_StudentCohortMath.sql ====================
/*******************************************************************************
 * Function: tvf_StudentCohortMath  (INLINE table-valued function)
 * Purpose: READ-ONLY math cohort matrix for the Reports > Math view (0.7.0, item 4).
 *          One row per (student x applicable task) for ONE group (homeroom / grade /
 *          section) across ALL of the CURRENT school year's math cycles, carrying the
 *          student's LATEST recorded result for that task. The client pivots these into
 *          the read-only matrix (styled like the data-entry grid), groups tasks by unit,
 *          and rolls up class % / per-student averages for the colour-coding + charts.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped (a whole school/region matrix would be unusable) + @UPN-scoped: the same
 * OR-across-EXISTS role gate as the entry/Programming TVFs (analyst/admin via
 * StaffSchoolAccess; teacher via FactSectionTeachers). @GroupKey shapes: 'GRADE:<School>:<Grade>',
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey — resolved exactly like tvf_ProgrammingRoster.
 * Math is P-6 only, so the cohort is restricted to GradeOrder 0-6.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMath;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMath(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows (lifetime "Current");
        -- a cycle id narrows to that cycle's Math window(s). Mirrors tvf_StudentCohort.
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    -- The group's students, current + P-6, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, sch.SchoolName, p.ProgramFamily
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = s.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND g.GradeOrder BETWEEN 0 AND 5  -- Math P..5 (grade 6 not ready 2026-27)
          -- group membership by @GroupKey shape
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + s.SchoolID + ':' + s.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = s.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND s.GroupKey = @GroupKey)
          )
          -- caller scope gate (mirrors tvf_ProgrammingRoster)
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
    -- Active tasks for the group's grades at the current-year math months (the matrix's columns/rows).
    Tasks AS (
        SELECT DISTINCT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder, mt.QuestionNumber,
               mt.DisplayOrder, mt.OutcomeCode, mt.TaskDescriptionEN, mt.TaskDescriptionFR
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1
          AND mt.GradeCode IN (SELECT DISTINCT Grade FROM GroupStudents)
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    -- Latest result per (student, task) across ALL of the year's math windows.
    LatestMath AS (
        SELECT fm.StudentKey, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentKey, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (
        SELECT fsi.StudentKey, fsi.IsIPP FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        gs.ProgramFamily,
        CAST(t.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        t.UnitName,
        t.UnitOrder,
        t.QuestionNumber,
        t.DisplayOrder,
        t.OutcomeCode,
        -- Description in the student's family language (FI -> FR w/ EN fallback), like the entry roster.
        CASE WHEN gs.ProgramFamily = 'French Immersion'
             THEN COALESCE(t.TaskDescriptionFR, t.TaskDescriptionEN)
             ELSE t.TaskDescriptionEN END AS TaskDescription,
        lm.Result           AS ExistingResult,   -- BIT: latest 0/1, or NULL if never marked
        ipp.IsIPP           AS MathIPPStatus      -- 1 = math IPP, 0 = not, NULL = unresolved
    FROM GroupStudents gs
    INNER JOIN Tasks t ON t.GradeCode = gs.Grade   -- each student gets THEIR grade's tasks
    LEFT JOIN LatestMath lm
           ON lm.StudentKey  = gs.StudentKey
          AND lm.MathTaskKey = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentKey = gs.StudentKey
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_StudentCohortRWM.sql ====================
/*******************************************************************************
 * Function: tvf_StudentCohortRWM  (INLINE table-valued function)
 * Purpose: READ-ONLY Reading·Writing·Math achievement roll-up for Reports > RWM
 *          (0.7.0, item 5). One row per in-scope Primary-6 student with a 0-3 score:
 *          how many of {Reading, Writing, Math} the student is CURRENTLY meeting or
 *          exceeding (their most-recent result in each area).
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * "Meeting+" per area:
 *   Reading  - most-recent FactAssessmentReading delta -> DimAchievementLevel code IN (3,4).
 *   Writing  - most-recent FactAssessmentWriting trait average -> band code IN (3,4)
 *              (same cut scores as tvf_StudentCohortWriting: avg >= 2.75).
 *   Math     - current-year roll-up = AVERAGE of the student's per-unit averages
 *              (unit avg = AVG(Result) over recorded tasks; blanks are absent rows, so
 *              already excluded) >= 0.75 (Meeting / In-depth).
 *
 * SCOPE: P-6 only (math is P-6; the whole score is defined P-6). EXCLUDES any student
 * with a CONFIRMED IPP (IsIPP = 1) in Reading, Writing, OR Math -- an IPP student is on an
 * individualized plan and isn't measured against these benchmarks. @UPN role gate is the
 * same OR-across-EXISTS branch as the other cohort TVFs (analyst/admin via StaffSchoolAccess;
 * teacher via FactSectionTeachers) -- NO region-wide branch.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortRWM;
GO

CREATE FUNCTION dbo.tvf_StudentCohortRWM(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows; a cycle id narrows to that cycle's Math window(s).
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    -- In-scope, current, P-6 students (role-gated).
    InScope AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, sg.GradeOrder,
               s.SchoolID, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation,
               s.ProgramCode, p.ProgramFamily, s.Homeroom
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        INNER JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND sg.GradeOrder BETWEEN 0 AND 5  -- RWM P..5 (grade 6 math not ready 2026-27)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = s.StudentKey)
          )
    ),
    -- Any confirmed IPP in ANY of the three subjects removes the student from this report.
    AnyIPP AS (
        SELECT DISTINCT fsi.StudentKey FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.IsIPP = 1 AND fsi.Subject IN ('Reading', 'Writing', 'Math')
    ),
    -- Most-recent reading -> achievement code (delta mapped through DimAchievementLevel bounds).
    ReadLatest AS (
        SELECT far.StudentKey, far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentKey
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Reading window(s).
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    ReadAch AS (
        SELECT rl.StudentKey, dal.AchievementLevelCode AS Code
        FROM ReadLatest rl
        LEFT JOIN DimAchievementLevel dal
               ON dal.ActiveFlag = 1
              AND rl.ReadingDelta IS NOT NULL
              AND (dal.LowerBound IS NULL
                   OR (dal.LowerOp = '>=' AND rl.ReadingDelta >= dal.LowerBound)
                   OR (dal.LowerOp = '>'  AND rl.ReadingDelta >  dal.LowerBound)
                   OR (dal.LowerOp = '='  AND rl.ReadingDelta =  dal.LowerBound))
              AND (dal.UpperBound IS NULL
                   OR (dal.UpperOp = '<=' AND rl.ReadingDelta <= dal.UpperBound)
                   OR (dal.UpperOp = '<'  AND rl.ReadingDelta <  dal.UpperBound)
                   OR (dal.UpperOp = '='  AND rl.ReadingDelta =  dal.UpperBound))
        WHERE rl.rn = 1
    ),
    -- Most-recent writing -> trait average -> band code (same cut scores as tvf_StudentCohortWriting).
    -- Traits are VARCHAR: count one ONLY when it is explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
    -- all drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
    -- would hard-CAST '-' and error — so gate on the explicit allow-list.
    WriteLatest AS (
        SELECT faw.StudentKey,
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
               ROW_NUMBER() OVER (PARTITION BY faw.StudentKey
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Writing window(s).
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    WriteAch AS (
        SELECT wl.StudentKey,
               CASE WHEN wl.AvgScore IS NULL   THEN NULL
                    WHEN wl.AvgScore >= 3.50   THEN 4
                    WHEN wl.AvgScore >= 2.75   THEN 3
                    WHEN wl.AvgScore >= 1.75   THEN 2
                    ELSE 1 END AS Code
        FROM WriteLatest wl WHERE wl.rn = 1
    ),
    -- Math roll-up: latest result per task (current-year windows) -> per-unit avg -> avg of unit avgs.
    MathLatest AS (
        SELECT fm.StudentKey, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentKey, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathUnit AS (
        SELECT ml.StudentKey, mt.UnitName, AVG(CAST(ml.Result AS FLOAT)) AS UnitAvg
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentKey, mt.UnitName
    ),
    MathRoll AS (   -- blanks EXCLUDED: unit avg over recorded tasks only
        SELECT StudentKey, AVG(UnitAvg) AS RollupPct FROM MathUnit GROUP BY StudentKey
    ),
    -- blanks COUNT-AS-0: denominator = every configured task for the grade's units this year, so an
    -- un-recorded task counts as a miss. Universe = active tasks at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
    ),
    MathUnitOnes AS (   -- recorded 1s per (student, unit)
        SELECT ml.StudentKey, mt.GradeCode, mt.UnitName, SUM(CAST(ml.Result AS INT)) AS Ones
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentKey, mt.GradeCode, mt.UnitName
    ),
    MathZeroUnit AS (   -- one row per (student, configured unit): ones / configured (fully-blank unit = 0)
        SELECT isc.StudentKey,
               CAST(COALESCE(mo.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
        FROM InScope isc
        INNER JOIN TaskUniverse tu ON tu.GradeCode = isc.Grade
        LEFT  JOIN MathUnitOnes mo ON mo.StudentKey = isc.StudentKey AND mo.GradeCode = isc.Grade AND mo.UnitName = tu.UnitName
    ),
    MathZeroRoll AS (
        SELECT StudentKey, AVG(UnitAvg) AS RollupPct FROM MathZeroUnit GROUP BY StudentKey
    )
    SELECT
        CAST(isc.StudentKey AS VARCHAR(20))            AS StudentKey,
        isc.StudentNumber,
        isc.FirstName,
        isc.LastName,
        isc.FirstName + ' ' + isc.LastName             AS FullName,
        isc.Grade,
        isc.GradeOrder,
        isc.SchoolID,
        isc.SchoolName,
        isc.SchoolAbbreviation,
        isc.ProgramCode,
        isc.ProgramFamily,
        isc.Homeroom,
        ra.Code                                        AS ReadingCode,
        wa.Code                                        AS WritingCode,
        CAST(mr.RollupPct AS DECIMAL(5,4))             AS MathRollupPct,      -- blanks excluded
        CAST(mz.RollupPct AS DECIMAL(5,4))             AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS ReadingMeeting,
        CAST(CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS WritingMeeting,
        CAST(CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)       AS MathMeeting,
        -- 0-3: how many areas are currently meeting/exceeding.
        (CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END)               AS RWMScore,
        -- "has any evidence" per area, so the UI can tell "not meeting" from "no result yet".
        CAST(CASE WHEN ra.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasReading,
        CAST(CASE WHEN wa.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasWriting,
        CAST(CASE WHEN mr.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasMath
    FROM InScope isc
    LEFT JOIN ReadAch   ra ON ra.StudentKey = isc.StudentKey
    LEFT JOIN WriteAch  wa ON wa.StudentKey = isc.StudentKey
    LEFT JOIN MathRoll  mr ON mr.StudentKey = isc.StudentKey
    LEFT JOIN MathZeroRoll mz ON mz.StudentKey = isc.StudentKey
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentKey = isc.StudentKey)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO

-- ==================== sql/security/tvf_StudentCohortMathAll.sql ====================
/*******************************************************************************
 * Function: tvf_StudentCohortMathAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Math OVERSIGHT roll-up tree (math-reports #2,
 *          Phase 1, 1.2.0). One row per (student x unit) for EVERY P-5 student in the
 *          caller's oversight scope, carrying COUNTS only — the unit's task count, how many
 *          of those tasks have a latest result, and how many of those are 1 (can do). The
 *          client turns the counts into each student's unit / overall Achievement Level and
 *          rolls them up School -> Grade|Homeroom (% Meeting-or-In-depth).
 *          Task-level detail is NOT here: expanding a grade/homeroom loads that one group's
 *          matrix through tvf_StudentCohortMath (same scope gate), so this stays small
 *          (~students x units) and carries no names / student numbers.
 * Created: 2026-10-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 * StaffSchoolAccess (identical to tvf_StudentCohortMath's oversight branch). A plain teacher
 * gets no rows; teachers keep the card picker. Math = Primary..Grade 5 (grade 6 not ready 2026-27).
 *
 * Counting matches MathCohortView: a cell is the student's LATEST result per task across the
 * selected math window(s) (@CycleGroupID NULL = all current-year math windows). A student whose
 * grade has no configured tasks still returns ONE row with UnitName NULL / TaskCount 0, so the
 * tree can show them as "No data" instead of dropping them.
 *
 * Single reference to the student scan (Fabric inlines a CTE at every reference — skill #17).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMathAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMathAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows (optionally one cycle) + effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    Tasks AS (      -- active P-5 tasks at the selected months
        SELECT mt.MathTaskKey, mt.GradeCode, mt.UnitName, mt.UnitOrder
        FROM DimMathTask mt
        INNER JOIN DimGrade tg ON tg.GradeCode = mt.GradeCode
        WHERE mt.ActiveFlag = 1
          AND tg.GradeOrder BETWEEN 0 AND 5
          AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
    ),
    LatestMath AS ( -- latest result per (student, task) across the selected windows
        SELECT fm.StudentKey, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentKey, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- one value per student (1 = math IPP, 0 = not, NULL = unresolved)
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,   -- the homeroom's tvf_StudentCohortMath key
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS MathIPPStatus,
        t.UnitName,                                         -- NULL = no tasks configured for this grade
        MAX(t.UnitOrder)                  AS UnitOrder,
        COUNT(t.MathTaskKey)              AS TaskCount,
        COUNT(lm.Result)                  AS ScoredCount,   -- tasks with a latest 0/1
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM DimStudent s
    INNER JOIN DimGrade  g   ON g.GradeCode  = s.Grade
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN MathIPP   ipp ON ipp.StudentKey = s.StudentKey
    LEFT  JOIN Tasks     t   ON t.GradeCode  = s.Grade
    LEFT  JOIN LatestMath lm
           ON lm.StudentKey  = s.StudentKey
          AND lm.MathTaskKey = t.MathTaskKey
          AND lm.rn = 1
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
    GROUP BY s.StudentKey, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID, sch.SchoolName, ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathAll] TO [StudentDataAssessment];
GO

-- ==================== Step 5: Math cycle windows P-6 -> P-5 ====================
UPDATE DimAssessmentWindow
SET MaxGrade    = '5',
    LastUpdated = GETDATE()
WHERE AssessmentType = 'Math'
  AND MaxGrade = '6';
GO

-- ==================== Step 6: Verify ====================
-- Expect: Math rows all MaxGrade '5' (Reading/Writing unchanged from before).
SELECT AssessmentType, MinGrade, MaxGrade, COUNT(*) AS WindowRows
FROM DimAssessmentWindow
GROUP BY AssessmentType, MinGrade, MaxGrade
ORDER BY AssessmentType, MinGrade, MaxGrade;

-- Expect 4 rows (all four functions present).
SELECT name, create_date
FROM sys.objects
WHERE name IN ('tvf_MathCohortGroups', 'tvf_StudentCohortMath', 'tvf_StudentCohortRWM', 'tvf_StudentCohortMathAll')
ORDER BY name;
GO
