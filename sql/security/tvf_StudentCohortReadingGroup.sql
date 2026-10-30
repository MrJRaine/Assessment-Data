/*******************************************************************************
 * Function: tvf_StudentCohortReadingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP reading detail for the Reports > Reading roll-up tree (1.3.0, Slice 1b).
 *          Loaded on demand when a Grade / Homeroom node is expanded — the individual students in that
 *          group with their LATEST reading level + achievement band PER LANGUAGE (EN/FR). One row per
 *          (student x reading-result language) + a NULL-language row for a student with no reading
 *          result (so they show as "No data"). The client pivots to one row per student (EN + FR cells).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom (and so its @GroupKey membership) comes from the RESULT's frozen
 *          DimStudent version and the oversight gate follows the ATTRIBUTED school; unassessed rows
 *          stay current students. With no cycle ("Current" view) everything anchors on the current
 *          version, as before. Display names come from the student's CURRENT version when one exists
 *          (people keep their current name), falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same OR-across-EXISTS gate as tvf_StudentCohortMath (oversight via
 * StaffSchoolAccess against the ATTRIBUTED school; teacher via FactSectionTeachers — kept for parity
 * though the reading tree is oversight-only; the teacher branch remains current-roster, so it never
 * surfaces a departed student). @GroupKey shapes: 'GRADE:<SchoolID>:<Grade>', 'SEC:<SectionID>', else a
 * homeroom DimStudent.GroupKey — matched against the ATTRIBUTED version's values, so the drill's rows
 * agree with the roll-up's counts. Students restricted to the selected Reading windows' grade span.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    -- Effective benchmark month per selected reading window (BenchmarkMonth, else dominant calendar
    -- month) — matched against DimReadingBenchmark for the Expected range (mirrors tvf_StudentCohort).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, far.AssessmentWindowID,
               drs.ScaleSystem, drs.LevelCode, drs.LevelOrder, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortReadingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               lr.AssessmentWindowID, lr.ScaleSystem, lr.LevelCode, lr.LevelOrder, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               CAST(NULL AS BIGINT), CAST(NULL AS VARCHAR(20)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestReading lr2 WHERE lr2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               lr3.AssessmentWindowID, lr3.ScaleSystem, lr3.LevelCode, lr3.LevelOrder, lr3.ReadingDelta
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    ),
    -- The group's attributed rows (in the reading grade span), intersected with the caller's scope.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.AssessmentWindowID, a.ScaleSystem, a.LevelCode, a.LevelOrder, a.ReadingDelta
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        ipp.IsIPP                 AS ReadingIPPStatus,
        gs.ScaleSystem,                               -- language of THIS result; NULL = no reading result
        gs.LevelCode,                                 -- the reading level (e.g. 'M'); NULL = no result
        gs.LevelOrder,
        gs.ReadingDelta,                              -- signed difference from the expected benchmark
        drb.ExpectedMinLevel      AS ExpectedMinLevel, -- expected benchmark range for THIS result's language
        drb.ExpectedMaxLevel      AS ExpectedMaxLevel,
        expMin.LevelOrder         AS ExpectedMinOrder, -- order of ExpectedMinLevel (for sorting the Expected column)
        sp.StartingLevelCode      AS JuneReadingLevel,  -- prior-June starting level (same language); parity with the flat list
        CASE WHEN gs.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN gs.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,  -- signed growth since prior June
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- cell-background tint (coloured cell, not text)
    FROM GroupStudents gs
    LEFT JOIN ReadingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    -- Expected benchmark range for THIS result's window month + the language's family (EN_Reading ->
    -- English, FR_Reading -> French Immersion), so a French result shows the French expectation.
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = gs.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = gs.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE gs.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin
           ON expMin.LevelCode  = drb.ExpectedMinLevel
          AND expMin.ScaleSystem = gs.ScaleSystem
    -- Prior-June starting point for THIS result's language (mirrors tvf_StudentCohort) → Diff from Prev June.
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = gs.StudentNumber AND sp.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimReadingScale jrs
           ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND gs.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND gs.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND gs.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND gs.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND gs.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND gs.ReadingDelta =  dal.UpperBound))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingGroup] TO [StudentDataAssessment];
GO
