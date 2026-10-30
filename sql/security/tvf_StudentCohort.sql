/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized reading cohort for the web-app student list (Phase 3b). The app
 *          connects as the StudentDataAssessment SP, so the OR-across-EXISTS role branches
 *          (Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess, Teacher via
 *          FactSectionTeachers) scope each caller to their own cohort.
 * Created: 2026-06-22
 * Modified: 2026-10-20 — DUAL-LANGUAGE: emits ONE ROW PER (student x reading language). The language
 *           set = the student's EXPECTED reading languages (StudentExpectedAssessment, config-derived
 *           from course enrolment x cycle instances) UNION any language they already have a result in;
 *           a student with neither gets a single NULL-language row so they still appear. Each row carries
 *           AssessmentLanguage + IsExpected and that language's latest reading (level/expected/delta/
 *           achievement/June). The client stacks the rows per student. IDENTITY IS StudentNumber
 *           throughout (stack / dedupe / fact + expected joins) — never the mutable StudentKey
 *           (project_assessment_fact_scd_policy). Demographics come from the CURRENT DimStudent by
 *           StudentNumber, one consistent set per student.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (server-side patch under 1.3.0; full rationale
 *           in tvf_StudentCohortReadingAll), CYCLE-SCOPED: with a cycle selected, a student WITH a
 *           reading result in it takes their demographics (School/Grade/Homeroom/program/flags) from
 *           the frozen DimStudent version of their MOST RECENT reading result in that cycle — ONE
 *           attribution per student, so the client's per-student stacking keeps one consistent
 *           demographic set — and the scope gate follows the ATTRIBUTED school; movers stop dragging
 *           recorded history to the new school and district leavers stay listed in the cycles they
 *           were assessed in. Students with no result in the cycle stay current students. With NO
 *           cycle (the "Current" view) everything anchors on the current version, as before. Display
 *           names prefer the CURRENT version (frozen for leavers); the emitted StudentKey (detail link
 *           only) prefers the CURRENT version so the link lands on the live record. ReadingIPP no
 *           longer requires a current DimStudent join (a leaver's IPP row resolves too).
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent reading per language ("Current"); a cycle id scopes the
 *   latest-result pick, the expected-language set AND the attribution to that cycle. Callers pass both args.
 * SECURITY: trusts a truthful @UPN; SELECT granted to the SP alone (the client never supplies the UPN).
 * ORDER BY omitted — the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    -- Latest reading per (StudentNumber, ScaleSystem). Cycle-scoped when a cycle is selected.
    LatestReading AS (
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, drs.ScaleSystem,
               far.AssessmentWindowID, far.AssessmentDate,
               far.ReadingDelta, drs.LevelCode, drs.LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn,
               -- rnAny ranks across BOTH languages: the student's single most recent reading result in
               -- scope, whose frozen StudentKey is the student's ATTRIBUTION for a cycle-scoped call.
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rnAny
        FROM FactAssessmentReading far
        JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    LR AS (SELECT * FROM LatestReading WHERE rn = 1),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent result in the cycle
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous, fv.Homeroom
        FROM LatestReading lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rnAny = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestReading lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- Students in the caller's scope — the ATTRIBUTED version, identity = StudentNumber.
    Scope AS (
        SELECT
            COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
            a.StudentNumber,
            COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
            COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
            a.Grade, a.SchoolID, a.ProgramCode,
            a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous, a.Homeroom,
            sg.GradeOrder, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation, p.ProgramFamily
        FROM AttrBase a
        JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- Effective benchmark month per reading window (BenchmarkMonth, else dominant calendar month).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
    ),
    -- Expected reading languages per student (cycle-scoped). Identity = StudentNumber.
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Per-student reading IPP (any family), by StudentNumber. HasRow distinguishes N/A from Unresolved.
    -- No IsCurrent filter on the DimStudent hop (2026-10-30): a leaver's IPP row points at a non-current
    -- version; the hop only translates StudentKey -> StudentNumber, and the GROUP BY keeps one row.
    ReadingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY ds.StudentNumber
    ),
    -- The (student x language) rows to emit: expected languages UNION languages with a result; PLUS a
    -- single NULL-language fallback row for students in neither (so they still appear once).
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language, lang.ScaleSystem,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English', 'EN_Reading'), ('French', 'FR_Reading')) AS lang(Language, ScaleSystem)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LR r        ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = lang.ScaleSystem
        WHERE e.Language IS NOT NULL OR r.ScaleSystem IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(20)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LR r WHERE r.StudentNumber = sc.StudentNumber)
    )
    -- ===== One row per (student x language); a NULL-language row = student not expected + no result =====
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,  -- carried for the detail link ONLY; NOT an identity
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,  -- 'English' | 'French'
        ls.IsExpected                     AS IsExpected,
        rip.IsIPP                         AS IsIPP_Reading,
        CASE WHEN rip.StudentNumber IS NULL THEN 'N/A'
             WHEN rip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN rip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Reading,
        CAST(CASE WHEN rip.StudentNumber IS NULL THEN 1 WHEN rip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleReading,
        r.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        r.LevelCode                       AS MostRecentLevelCode,
        r.LevelOrder                      AS MostRecentLevelOrder,
        r.ReadingDelta                    AS MostRecentReadingDelta,
        drb.ExpectedMinLevel              AS ExpectedMinLevel,
        drb.ExpectedMaxLevel              AS ExpectedMaxLevel,
        expMin.LevelOrder                 AS ExpectedMinOrder,
        sp.StartingLevelCode              AS JuneReadingLevel,
        CASE WHEN r.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN r.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LR r ON r.StudentNumber = sc.StudentNumber AND r.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = r.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = sc.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE ls.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin ON expMin.LevelCode = drb.ExpectedMinLevel AND expMin.ScaleSystem = ls.ScaleSystem
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp ON sp.StudentNumber = sc.StudentNumber AND sp.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimReadingScale jrs ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = ls.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND r.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND r.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND r.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND r.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND r.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND r.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND r.ReadingDelta =  dal.UpperBound))
    LEFT JOIN ReadingIPP rip ON rip.StudentNumber = sc.StudentNumber
);
GO

-- DROP+CREATE drops object grants; re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO
