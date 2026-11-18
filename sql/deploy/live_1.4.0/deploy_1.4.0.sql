/*******************************************************************************
 * Deploy: 1.4.0 live bundle (reports release)
 * Date: 2026-11-18
 * Target: Assessment_Warehouse (LIVE). Run the WHOLE file in one session, during a
 * maintenance window, BEFORE swapping the container to assessment-webapp:1.4.0
 * (the 1.4.0 app expects these functions; the running 1.3.0 app keeps working
 * against them — every change is additive columns or a new function).
 * Idempotent - every object is DROP IF EXISTS + CREATE + GRANT; safe to run again.
 *
 * PREREQUISITE (added after the 2026-11-18 live run): run
 * deploy_1.4.0_prereq_expected_table.sql FIRST. Parts 1-6 read
 * dbo.StudentExpectedAssessment, which the 1.3.0 live bundle never created; without
 * it those six CREATEs fail (Msg 208) AFTER their DROPs have already run.
 *
 * WHAT IT DOES: replaces 9 report functions and creates 3 new ones. Assembled
 * verbatim from the sql/security sources at this commit; each part's own header
 * documents its change history.
 *    1. tvf_StudentCohort              (Reading student list)          replace
 *    2. tvf_StudentCohortWriting       (Writing student list)          replace
 *    3. tvf_StudentCohortReadingAll    (Reading summary tree feed)     replace
 *    4. tvf_StudentCohortReadingGroup  (Reading expanded roster view)  replace
 *    5. tvf_StudentCohortWritingAll    (Writing summary tree feed)     replace
 *    6. tvf_StudentCohortWritingGroup  (Writing expanded roster view)  replace
 *    7. tvf_StudentCohortRWM           (RWM report feed)               replace
 *    8. tvf_StudentCohortMathAll       (Math summary tree feed)        replace
 *    9. tvf_StudentCohortMath          (Math expanded roster view)     replace
 *   10. tvf_StudentCohortMathTrend     (Math by-cycle bar chart feed)  NEW
 *   11. tvf_MissingDataAll             (Missing results tree feed)     NEW
 *   12. tvf_MissingDataGroup           (Missing results section list)  NEW
 *
 * Carries, cumulatively since the 1.3.0 bundle: cycle-scoped historical school
 * attribution on the report READ path (2026-10-30), summary-tree demographic
 * columns + expected-language rows + lifetime "Current" + IPP not measured
 * (2026-11-10/12), Missing results (2026-11-12), the measured/chart-eligible
 * flags of the IPP display model (2026-11-17), and the Math filter columns +
 * by-cycle feed (2026-11-18).
 *
 * WRITES: no table data. Only DROP/CREATE of the 12 inline table-valued
 * functions + GRANT SELECT on each to StudentDataAssessment. No tables, columns,
 * procedures or views are created or altered.
 * READS (by the functions, at query time): DimStudent, DimSchool, DimGrade,
 * DimProgram, DimSection, DimStaff, DimCalendar, DimShortCycle,
 * DimAssessmentWindow, DimAchievementLevel, DimReadingScale, DimReadingBenchmark,
 * DimMathTask, DimCourseAssessment, FactAssessmentReading/Writing/Math,
 * FactEnrollment, FactSectionTeachers, FactStudentIPP, StaffSchoolAccess,
 * StudentExpectedAssessment, SectionRosterMembership, WritingTraitExclusion and
 * vw_StudentReadingStartingPoint - see each part's header for its exact set.
 *
 * NOT IN THIS BUNDLE (deliberately): the section-school binding change to the
 * three usp_Upsert*Assessment procedures (coded 2026-10-30; no record of a dev
 * run or test) - a WRITE-path change, held for an explicit decision.
 *
 * The LAST batch is a read-only check: it lists the 12 functions with their
 * modify dates - expect 12 rows, all stamped at this run.
 ******************************************************************************/

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

/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: @UPN-parameterized writing cohort for the web-app student list. Writing counterpart of
 *          tvf_StudentCohort — the 4-trait scores + their average map to an achievement band by the
 *          fixed cut scores (>=3.50 / >=2.75 / >=1.75), reusing DimAchievementLevel name+colour by code.
 * Created: 2026-06-25
 * Modified: 2026-10-20 — DUAL-LANGUAGE: ONE ROW PER (student x writing language). Language set =
 *           expected writing languages (StudentExpectedAssessment) UNION any language with a result;
 *           a student in neither gets one NULL-language row. Writing's AssessmentLanguage IS the
 *           language ('English'/'French'), so the latest-pick partitions by (StudentNumber,
 *           AssessmentLanguage). IDENTITY = StudentNumber throughout; demographics from the CURRENT
 *           DimStudent by StudentNumber.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (see its
 *           header + tvf_StudentCohortReadingAll for the full rationale), CYCLE-SCOPED: with a cycle
 *           selected, a student WITH a writing result in it takes their demographics from the frozen
 *           DimStudent version of their MOST RECENT writing result in that cycle (one attribution per
 *           student) and the scope gate follows the ATTRIBUTED school; students with no result in the
 *           cycle stay current students. With NO cycle (the "Current" view) everything anchors on the
 *           current version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *           version; WritingIPP no longer requires a current DimStudent join.
 * Region: Canada East (PIIDPA compliant)
 *
 * @CycleGroupID: NULL = lifetime most-recent per language ("Current"); a cycle id scopes the
 *   latest-pick, the expected set AND the attribution to that cycle. SECURITY: SELECT granted to the SP alone.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH
    Expected AS (
        SELECT DISTINCT StudentNumber, Language
        FROM StudentExpectedAssessment
        WHERE AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR CycleGroupID = @CycleGroupID)
    ),
    -- Latest writing per (StudentNumber, AssessmentLanguage) + its average over the SCORED traits
    -- (only '1'-'4' count; SCR / '-' / NULL drop from BOTH numerator and denominator).
    LatestWriting AS (
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.AssessmentWindowID, faw.AssessmentDate,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
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
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn,
               -- rnAny ranks across BOTH languages: the student's single most recent writing result in
               -- scope, whose frozen StudentKey is the student's ATTRIBUTION for a cycle-scoped call.
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rnAny
        FROM FactAssessmentWriting faw
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    LW AS (SELECT * FROM LatestWriting WHERE rn = 1),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent result in the cycle
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous, fv.Homeroom
        FROM LatestWriting lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rnAny = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous, s.Homeroom
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestWriting lt2 WHERE lt2.StudentNumber = s.StudentNumber))
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
    -- No IsCurrent filter on the DimStudent hop (2026-10-30): the hop only translates
    -- StudentKey -> StudentNumber, so a district leaver's IPP row resolves too.
    WritingIPP AS (
        SELECT ds.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY ds.StudentNumber
    ),
    -- (student x language): expected UNION has-result, PLUS a NULL-language fallback for neither.
    LangSet AS (
        SELECT sc.StudentNumber, lang.Language,
               CAST(CASE WHEN e.Language IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsExpected
        FROM Scope sc
        CROSS JOIN (VALUES ('English'), ('French')) AS lang(Language)
        LEFT JOIN Expected e ON e.StudentNumber = sc.StudentNumber AND e.Language = lang.Language
        LEFT JOIN LW w        ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = lang.Language
        WHERE e.Language IS NOT NULL OR w.AssessmentLanguage IS NOT NULL
        UNION ALL
        SELECT sc.StudentNumber, CAST(NULL AS VARCHAR(10)), CAST(0 AS BIT)
        FROM Scope sc
        WHERE NOT EXISTS (SELECT 1 FROM Expected e WHERE e.StudentNumber = sc.StudentNumber)
          AND NOT EXISTS (SELECT 1 FROM LW w WHERE w.StudentNumber = sc.StudentNumber)
    )
    SELECT
        CAST(sc.StudentKey AS VARCHAR(20)) AS StudentKey,
        sc.StudentNumber,
        sc.FirstName, sc.LastName, sc.FirstName + ' ' + sc.LastName AS FullName,
        sc.Grade, sc.GradeOrder, sc.SchoolID, sc.SchoolName, sc.SchoolAbbreviation,
        sc.ProgramCode, sc.ProgramFamily, sc.Gender, sc.SelfIDAfrican, sc.SelfIDIndigenous, sc.Homeroom,
        ls.Language                       AS AssessmentLanguage,
        ls.IsExpected                     AS IsExpected,
        wip.IsIPP                         AS IsIPP_Writing,
        CASE WHEN wip.StudentNumber IS NULL THEN 'N/A'
             WHEN wip.IsIPP IS NULL         THEN 'Unresolved'
             WHEN wip.IsIPP = 1             THEN 'IPP'
             ELSE 'Not IPP' END           AS IPPStatus_Writing,
        CAST(CASE WHEN wip.StudentNumber IS NULL THEN 1 WHEN wip.IsIPP = 0 THEN 1 ELSE 0 END AS BIT) AS IsChartEligibleWriting,
        w.AssessmentDate                  AS MostRecentAssessmentDate,
        aw.WindowName                     AS MostRecentWindowName,
        aw.SchoolYear                     AS MostRecentSchoolYear,
        w.IdeasScore                      AS MostRecentIdeasScore,
        w.OrganizationScore               AS MostRecentOrganizationScore,
        w.LanguageScore                   AS MostRecentLanguageScore,
        w.ConventionsScore                AS MostRecentConventionsScore,
        w.AvgScore                        AS MostRecentAvgScore,
        dal.AchievementLevelCode          AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName          AS MostRecentAchievementLevelName,
        dal.HexColor                      AS MostRecentAchievementHexColor,
        dal.HexColorTint                  AS MostRecentAchievementHexColorTint
    FROM Scope sc
    INNER JOIN LangSet ls ON ls.StudentNumber = sc.StudentNumber
    LEFT JOIN LW w ON w.StudentNumber = sc.StudentNumber AND w.AssessmentLanguage = ls.Language
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND w.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    LEFT JOIN WritingIPP wip ON wip.StudentNumber = sc.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Modified: 2026-11-17 — + IsChartEligibleReading output (see the column comment): the tree tallies
 *          exclude unconfirmed IPPs from every measure and name them in the hovers.
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only — NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Modified: 2026-11-12 (b) — "CURRENT" = LIFETIME + IPP NOT MEASURED, aligning this feed with the
 *          ON-SPEC flat list (tvf_StudentCohort; user ruling 2026-11-12 — "Current" has always meant
 *          the most current evidence available for every student): (1) with @CycleGroupID NULL the
 *          latest-pick has NO window restriction — each student's most recent reading result ON
 *          RECORD, any school year (the GradeSpan population gate stays current-year: who appears is
 *          this year's assessed grades; what shows is their latest evidence, however old); the
 *          expected/fallback NOT EXISTS probes follow the same scope so an old result isn't double-
 *          reported as expected-only. (2) AchievementLevelCode is now really NULL for reading-IPP /
 *          unresolved students — this header always claimed it; the band join never enforced it —
 *          so the donut, % Meeting/Exceeding and trend match the list's chart-eligible rule.
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows (fixes the Language of Assessment filter dropping
 *          expected-but-unassessed students): the per-student language set is now EXPECTED
 *          (StudentExpectedAssessment, cycle-scoped) UNION assessed — the same union as
 *          tvf_StudentCohort's LangSet. An expected language with no result emits a row with
 *          ScaleSystem set, NULL date/delta, IsExpectedOnly=1 (the client counts the STUDENT under
 *          that language but no result); the NULL-language "No data" fallback row now only fires
 *          when a student is neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters). Attributed rows carry the FROZEN version's demographics, unassessed/current
 *          rows the current version's — same source row as the rest of the attribution.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (restores the documented design; server-side
 *          patch under 1.3.0), CYCLE-SCOPED: when @CycleGroupID is set, a row WITH a result attributes
 *          School/Grade/Homeroom from the RESULT's frozen DimStudent version (fact.StudentKey — the
 *          version in force when it was recorded), NOT the student's current version — so a transfer
 *          no longer moves recorded history to the new school, and a district leaver keeps their
 *          recorded results in the cycles where they were assessed; a student with NO result in that
 *          cycle shows from their CURRENT version ("No data", current+enrolled only), and the access
 *          gate follows the ATTRIBUTED school. With NO cycle selected (the "Current" view) everything
 *          anchors on the CURRENT version, as before. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a reading result they have this year):
 *   - a student with an EN and an FR reading result => TWO rows (ScaleSystem 'EN_Reading' / 'FR_Reading');
 *   - a student with one => ONE row; a student with NO reading result => ONE row, ScaleSystem NULL
 *     (so the tree shows them as "No data" instead of dropping them).
 *   A mover assessed at two schools shows under EACH school that recorded a (latest-per-language) result.
 *   Reading language is DERIVED from ReadingScaleID -> DimReadingScale.ScaleSystem (the reading fact has
 *   no AssessmentLanguage column — unlike writing). Dual-language reading is real: entry routes through the
 *   section's cycle instance, whose ScaleSystem the save stores (see project_assessment_language_tracks).
 *
 * MEASURE: AchievementLevelCode is the band for THIS result's ReadingDelta (same DimAchievementLevel logic
 *   as tvf_StudentCohort). NULL when the student has no result, no delta, or is a reading-IPP/unresolved
 *   student (not measured). The client computes % Meeting/Exceeding = rows with a Meeting-or-above band
 *   (code >= 3) / rows with ANY band; IPP / no-data are excluded from the % and shown in the hover.
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 *   StaffSchoolAccess, matched against the row's ATTRIBUTED school (identical gate shape to
 *   tvf_StudentCohortMathAll). A plain teacher gets no rows; teachers keep the flat per-student list.
 *
 * @CycleGroupID NULL = LIFETIME most-recent reading per language ("Current" — any school year, lockstep
 *   with tvf_StudentCohort); a cycle id restricts the latest-pick to that cycle's Reading instances.
 *   Grades included = the span of the CURRENT-YEAR (or selected cycle's) Reading windows'
 *   MinGrade..MaxGrade (config-driven, not hardcoded), checked against the ATTRIBUTED grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
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
    GradeSpan AS (  -- assessed reading grade-order range across the selected windows (who should appear)
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against (insert-time
        -- effective-date/section-school resolution) — it carries the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, drs.ScaleSystem,
               far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        -- No cycle ("Current") = NO window restriction: the most recent result ON RECORD, any year —
        -- lockstep with tvf_StudentCohort (user ruling 2026-11-12). A cycle restricts to its windows.
        WHERE @CycleGroupID IS NULL OR far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- one value per STUDENT NUMBER (1 = reading IPP in any family, 0 = not, NULL =
        -- unresolved). Keyed by StudentNumber because attributed rows carry FROZEN StudentKeys,
        -- which predate the IPP rows' current-version repointing.
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- Expected reading languages per student (cycle-scoped; config-derived from mapped-course
    -- enrolment — see StudentExpectedAssessment), as the reading ScaleSystem the facts carry.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber,
               CASE sea.Language WHEN 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, an assessed row attributes to the RESULT's
    -- frozen student version (the school/grade/homeroom that recorded it — includes movers' old-school
    -- rows and district leavers); with NO cycle selected (the "Current" view) every row anchors on the
    -- CURRENT version, as before — the current view reflects the schools as they are today. A
    -- non-mover's frozen version IS their current version — identical output either way.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed (tvf_StudentCohort's LangSet union): an
    -- expected language with no result emits an IsExpectedOnly row from the CURRENT version (there is
    -- no result to attribute by); the NULL-language fallback fires only when neither expected nor
    -- assessed. The NOT EXISTS probes hit the fact directly — cheaper than re-running LatestReading
    -- (Fabric inlines a CTE at every reference).
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lr.ScaleSystem, lr.AssessmentDate, lr.ReadingDelta, CAST(0 AS BIT) AS IsExpectedOnly
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lr3.ScaleSystem, lr3.AssessmentDate, lr3.ReadingDelta, CAST(0 AS BIT)
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.ScaleSystem, CAST(NULL AS DATE), CAST(NULL AS INT), CAST(1 AS BIT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx
                          INNER JOIN DimReadingScale dx ON dx.ReadingScaleID = fx.ReadingScaleID
                          WHERE fx.StudentNumber = s.StudentNumber AND dx.ScaleSystem = el.ScaleSystem
                            AND (@CycleGroupID IS NULL
                                 OR fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(20)), CAST(NULL AS DATE), CAST(NULL AS INT), CAST(0 AS BIT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND (@CycleGroupID IS NULL
                                 OR fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        b.SchoolID,
        sch.SchoolName,
        b.Gender,                                           -- summary-view demographic filters (2026-11-10)
        b.SelfIDAfrican,
        b.SelfIDIndigenous,
        ipp.IsIPP                         AS ReadingIPPStatus,
        -- Measured flag (2026-11-17), lockstep with the dal join below + the Group/list feeds: the
        -- client can't tell "no IPP row" from "unresolved" via ReadingIPPStatus (both NULL), and the
        -- tree tallies need it so unconfirmed IPPs are excluded from EVERY measure and counted in
        -- the hovers (trait/band denominators diverged without it).
        CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END AS IsChartEligibleReading,
        b.ScaleSystem,                                      -- language of THIS row; NULL = neither expected nor assessed
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        dal.AchievementLevelCode          AS AchievementLevelCode, -- band for THIS result; NULL = none/IPP/unresolved
        b.IsExpectedOnly                  AS IsExpectedOnly  -- 1 = expected in this language, no result yet (counts the student, not a result)
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN ReadingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    -- Achievement band for this result's delta — same bound logic as tvf_StudentCohort (mutually exclusive
    -- bounds => at most one band per delta). No delta (no result / NULL) => no band.
    LEFT  JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND (ipp.StudentNumber IS NULL OR ipp.IsIPP = 0)   -- IPP/unresolved: not measured, no band
          AND b.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND b.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND b.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND b.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND b.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND b.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND b.ReadingDelta =  dal.UpperBound))
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingAll] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortReadingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP reading detail for the Reports > Reading roll-up tree (1.3.0, Slice 1b).
 *          Loaded on demand when a Grade / Homeroom node is expanded — the individual students in that
 *          group with their LATEST reading level + achievement band PER LANGUAGE (EN/FR). One row per
 *          (student x reading-result language) + a NULL-language row for a student with no reading
 *          result (so they show as "No data"). The client pivots to one row per student (EN + FR cells).
 * Created: 2026-10-16
 * Modified: 2026-11-17 — + IsChartEligibleReading output (the dal-join measured predicate), so the
 *          drill can blank Expected/Diff for IPP/unresolved students in lockstep with the flat list.
 * Modified: 2026-11-12 (b) — "CURRENT" = LIFETIME + IPP NOT MEASURED, in lockstep with
 *          tvf_StudentCohortReadingAll (see its header for the full rationale): @CycleGroupID NULL
 *          now puts NO window restriction on the latest-pick (most recent reading result ON RECORD,
 *          any year; GradeSpan stays current-year) and the NOT EXISTS probes follow the same scope;
 *          WindowMonth covers ALL active Reading windows (a prior-year result must still resolve its
 *          Expected range — mirrors tvf_StudentCohort); AchievementLevelCode/Name/colours are NULL
 *          for reading-IPP / unresolved students (not measured — the drill shows "IPP" instead).
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortReadingAll (see
 *          its header): an expected language (StudentExpectedAssessment) with no result emits a row
 *          with ScaleSystem set and NULL level/delta, so the drill under a Language of Assessment
 *          filter shows expected-but-unassessed students as "—" instead of dropping them; the
 *          NULL-language "No data" row fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters: the drill table must match the filtered node counts above it).
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
    -- Effective benchmark month per ACTIVE reading window, ANY year (BenchmarkMonth, else dominant
    -- calendar month) — matched against DimReadingBenchmark for the Expected range. Not restricted to
    -- ReadWins: in "Current" (lifetime) mode a latest result can sit in a prior-year window and its
    -- Expected range must still resolve (mirrors tvf_StudentCohort's WindowMonth).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, far.AssessmentWindowID,
               drs.ScaleSystem, drs.LevelCode, drs.LevelOrder, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        -- No cycle ("Current") = NO window restriction: the most recent result ON RECORD, any year —
        -- lockstep with the *All feed and tvf_StudentCohort. A cycle restricts to its windows.
        WHERE @CycleGroupID IS NULL OR far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- Expected reading languages per student (cycle-scoped) — see StudentExpectedAssessment.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber,
               CASE sea.Language WHEN 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortReadingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed, in lockstep with the *All feed.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lr.AssessmentWindowID, lr.ScaleSystem, lr.LevelCode, lr.LevelOrder, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lr3.AssessmentWindowID, lr3.ScaleSystem, lr3.LevelCode, lr3.LevelOrder, lr3.ReadingDelta
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS BIGINT), el.ScaleSystem, CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx
                          INNER JOIN DimReadingScale dx ON dx.ReadingScaleID = fx.ReadingScaleID
                          WHERE fx.StudentNumber = s.StudentNumber AND dx.ScaleSystem = el.ScaleSystem
                            AND (@CycleGroupID IS NULL
                                 OR fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS BIGINT), CAST(NULL AS VARCHAR(20)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND (@CycleGroupID IS NULL
                                 OR fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    ),
    -- The group's attributed rows (in the reading grade span), intersected with the caller's scope.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,
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
        gs.Gender,                                    -- summary-view demographic filters (2026-11-10)
        gs.SelfIDAfrican,
        gs.SelfIDIndigenous,
        ipp.IsIPP                 AS ReadingIPPStatus,
        -- Lockstep with the dal join below + the *All/list feeds: 1 = measured against the benchmark.
        -- The client can't derive this from ReadingIPPStatus alone (NULL = no IPP row OR unresolved),
        -- and it gates the drill's Expected/Diff cells exactly like the flat list (2026-11-17).
        CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END AS IsChartEligibleReading,
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
          AND (ipp.StudentNumber IS NULL OR ipp.IsIPP = 0)   -- IPP/unresolved: not measured, no band
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

/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Modified: 2026-11-17 — + IsChartEligibleWriting output (see the column comment): the tree tallies
 *          exclude unconfirmed IPPs from every measure and name them in the hovers.
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only — no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Modified: 2026-11-12 (b) — "CURRENT" = LIFETIME + IPP NOT MEASURED, in lockstep with
 *          tvf_StudentCohortReadingAll (see its header for the full rationale): @CycleGroupID NULL
 *          now puts NO window restriction on the latest-pick (most recent writing result ON RECORD,
 *          any year; GradeSpan stays current-year) and the NOT EXISTS probes follow the same scope;
 *          AchievementLevelCode is NULL for writing-IPP / unresolved students (not measured).
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortReadingAll (see
 *          its header): language set = expected (StudentExpectedAssessment, Writing) UNION assessed;
 *          an expected language with no result emits an IsExpectedOnly=1 row (NULL date/traits/avg);
 *          the NULL-language fallback fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters), in lockstep with tvf_StudentCohortReadingAll.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom comes from the RESULT's frozen DimStudent version and the
 *          oversight gate follows the ATTRIBUTED school; a student with no writing result in that cycle
 *          stays a current, enrolled student at their current school. With no cycle (the "Current"
 *          view) everything anchors on the current version, as before. Non-movers are unchanged.
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a writing result they have this year):
 *   - FactAssessmentWriting.AssessmentLanguage IS part of the grain (unlike reading, which derives it
 *     from the scale), so a student with an English and a French writing result has TWO fact rows and
 *     gets TWO rows here ('English' / 'French'); one language => one row; no writing result => ONE row,
 *     AssessmentLanguage NULL ("No data"). A mover assessed at two schools shows under EACH school that
 *     recorded a (latest-per-language) result.
 *
 * MEASURE: the band CODE of the latest writing AVERAGE for that (student, language), by the SAME cut
 *   scores as tvf_StudentCohortWriting (avg>=3.50->4, >=2.75->3, >=1.75->2, else 1; NULL avg->NULL code).
 *   Client % Meeting/Exceeding = rows with code >= 3 / rows with ANY code, IPP excluded (via the flag).
 *   Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped from numerator AND denominator).
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess,
 *   matched against the row's ATTRIBUTED school.
 * @CycleGroupID NULL = LIFETIME most-recent writing per language ("Current" — any school year, lockstep
 *   with the flat list); a cycle id restricts the latest-pick. Grades = the span of the CURRENT-YEAR
 *   (or selected cycle's) Writing windows' MinGrade..MaxGrade, checked against the ATTRIBUTED grade.
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
    LatestWriting AS (   -- latest result per (student, language) across the selected windows + its average.
        -- faw.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage, faw.AssessmentDate,
            faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,  -- per-trait rollup (score >= 3 = Meeting/Exceeding)
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
        -- No cycle ("Current") = NO window restriction: the most recent result ON RECORD, any year —
        -- lockstep with the flat list (user ruling 2026-11-12). A cycle restricts to its windows.
        WHERE @CycleGroupID IS NULL OR faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- Expected writing languages per student (cycle-scoped; config-derived — StudentExpectedAssessment).
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber, sea.Language
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed rows come from the RESULT's frozen
    -- student version (includes movers' old-school rows and district leavers) and unassessed rows are
    -- CURRENT, enrolled students ("No data" at their current school); with NO cycle (the "Current"
    -- view) everything anchors on the current version, as before.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed (tvf_StudentCohort's LangSet union): an
    -- expected language with no result emits an IsExpectedOnly row from the CURRENT version; the
    -- NULL-language fallback fires only when neither expected nor assessed. The NOT EXISTS probes hit
    -- the fact directly — cheaper than re-running LatestWriting (Fabric inlines a CTE per reference).
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lw.AssessmentLanguage, lw.AssessmentDate,
               lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore, lw.ConventionsScore, lw.AvgScore,
               CAST(0 AS BIT) AS IsExpectedOnly
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lw3.AssessmentLanguage, lw3.AssessmentDate,
               lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore, lw3.ConventionsScore, lw3.AvgScore,
               CAST(0 AS BIT)
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.Language, CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2)),
               CAST(1 AS BIT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx
                          WHERE fx.StudentNumber = s.StudentNumber
                            AND fx.AssessmentLanguage = el.Language
                            AND (@CycleGroupID IS NULL
                                 OR fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2)),
               CAST(0 AS BIT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND (@CycleGroupID IS NULL
                                 OR fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,
        b.SchoolID,
        sch.SchoolName,
        b.Gender,                                            -- summary-view demographic filters (2026-11-10)
        b.SelfIDAfrican,
        b.SelfIDIndigenous,
        ipp.IsIPP                         AS WritingIPPStatus,
        -- Measured flag (2026-11-17), lockstep with the band CASE below + the Group/list feeds: the
        -- client can't tell "no IPP row" from "unresolved" via WritingIPPStatus (both NULL), and the
        -- tree tallies need it so unconfirmed IPPs are excluded from EVERY measure and counted in
        -- the hovers (trait/band denominators diverged without it).
        CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END AS IsChartEligibleWriting,
        b.AssessmentLanguage,                                -- 'English' | 'French'; NULL = no writing result
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        b.IdeasScore                      AS IdeasScore,        -- the four trait scores ('1'-'4'/'SCR'/'-'/NULL)
        b.OrganizationScore               AS OrganizationScore, -- for the per-trait roll-up (% Meeting/Exceeding or Mean)
        b.LanguageScore                   AS LanguageScore,
        b.ConventionsScore                AS ConventionsScore,
        b.AvgScore                        AS AvgScore,          -- the 4-trait average (for the Mean measure)
        CASE WHEN b.AvgScore IS NULL THEN NULL
             -- IPP/unresolved: not measured, no band (lockstep with the flat list's chart-eligible rule)
             WHEN ipp.StudentNumber IS NOT NULL AND (ipp.IsIPP IS NULL OR ipp.IsIPP = 1) THEN NULL
             WHEN b.AvgScore >= 3.50 THEN 4
             WHEN b.AvgScore >= 2.75 THEN 3
             WHEN b.AvgScore >= 1.75 THEN 2
             ELSE 1 END                   AS AchievementLevelCode,
        b.IsExpectedOnly                  AS IsExpectedOnly  -- 1 = expected in this language, no result yet (counts the student, not a result)
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN WritingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingAll] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded — the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Modified: 2026-11-17 — + IsChartEligibleWriting output (the dal-join measured predicate), so the
 *          drill can mark unconfirmed IPPs ("IPP?") in lockstep with the flat list.
 * Modified: 2026-11-12 (b) — "CURRENT" = LIFETIME + IPP NOT MEASURED, in lockstep with
 *          tvf_StudentCohortReadingAll (see its header for the full rationale): @CycleGroupID NULL
 *          now puts NO window restriction on the latest-pick (most recent writing result ON RECORD,
 *          any year; GradeSpan stays current-year) and the NOT EXISTS probes follow the same scope;
 *          AchievementLevelCode/Name/colours are NULL for writing-IPP / unresolved students (not
 *          measured — the drill shows "IPP" instead).
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortWritingAll (see
 *          the reading All header for the rationale): an expected language (StudentExpectedAssessment)
 *          with no result emits a row with the language set and NULL traits/avg, so the drill under a
 *          Language of Assessment filter shows expected-but-unassessed students as "—" instead of
 *          dropping them; the NULL-language row fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters: the drill table must match the filtered node counts above it).
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortWritingAll /
 *          tvf_StudentCohortReadingAll (see the reading All header for the full rationale), CYCLE-
 *          SCOPED: with a cycle selected, an assessed row's School/Grade/Homeroom (and so its @GroupKey
 *          membership) comes from the RESULT's frozen DimStudent version and the oversight gate follows
 *          the ATTRIBUTED school; unassessed rows stay current students. With no cycle ("Current" view)
 *          everything anchors on the current version, as before. Display names come from the student's
 *          CURRENT version when one exists, falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup, matched on the ATTRIBUTED version's values. Average counts ONLY explicit
 * '1'-'4' traits (SCR / '-' / NULL dropped); band CODE by the writing cut scores (reused name + colour
 * from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
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
    LatestWriting AS (   -- latest result per (student, language); faw.StudentKey = the FROZEN version
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
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
        -- No cycle ("Current") = NO window restriction: the most recent result ON RECORD, any year —
        -- lockstep with the *All feed and the flat list. A cycle restricts to its windows.
        WHERE @CycleGroupID IS NULL OR faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- Expected writing languages per student (cycle-scoped) — see StudentExpectedAssessment.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber, sea.Language
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortWritingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed, in lockstep with the *All feed.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lw.AssessmentLanguage, lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore,
               lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lw3.AssessmentLanguage, lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore,
               lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.Language, CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx
                          WHERE fx.StudentNumber = s.StudentNumber
                            AND fx.AssessmentLanguage = el.Language
                            AND (@CycleGroupID IS NULL
                                 OR fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND (@CycleGroupID IS NULL
                                 OR fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    ),
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,
               a.AssessmentLanguage, a.IdeasScore, a.OrganizationScore, a.LanguageScore,
               a.ConventionsScore, a.AvgScore
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
        gs.Gender,                                 -- summary-view demographic filters (2026-11-10)
        gs.SelfIDAfrican,
        gs.SelfIDIndigenous,
        ipp.IsIPP                 AS WritingIPPStatus,
        -- Lockstep with the dal join below + the reading group feed (2026-11-17): 1 = measured. The
        -- client can't tell "no IPP row" from "unresolved" via WritingIPPStatus (both NULL); this
        -- drives the drill's unconfirmed-IPP ("IPP?") marker.
        CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END AS IsChartEligibleWriting,
        gs.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        gs.IdeasScore,
        gs.OrganizationScore,
        gs.LanguageScore,
        gs.ConventionsScore,
        gs.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- Avg-cell background tint (parity with the flat list)
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND (ipp.StudentNumber IS NULL OR ipp.IsIPP = 0)   -- IPP/unresolved: not measured, no band
          AND gs.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN gs.AvgScore >= 3.50 THEN 4
                   WHEN gs.AvgScore >= 2.75 THEN 3
                   WHEN gs.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortRWM  (INLINE table-valued function)
 * Purpose: READ-ONLY Reading·Writing·Math achievement roll-up for Reports > RWM
 *          (0.7.0, item 5). One row per in-scope Primary-6 student with a 0-3 score:
 *          how many of {Reading, Writing, Math} the student is CURRENTLY meeting or
 *          exceeding (their most-recent result in each area).
 * Created: 2026-09-24
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (RWM Summary tree's filter
 *          section, in lockstep with the Reading/Writing *All TVFs). Attributed rows carry the
 *          FROZEN version's demographics, unassessed/current rows the current version's.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (full
 *          rationale in tvf_StudentCohortReadingAll), CYCLE-SCOPED: with a cycle selected, a student
 *          WITH any R/W/M result in it takes their demographics from the frozen DimStudent version of
 *          their MOST RECENT result across the three subjects in that cycle (one attribution per
 *          student) and the scope gate follows the ATTRIBUTED school; students with no result stay
 *          current students. With NO cycle (the "Current" view) everything anchors on the current
 *          version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *          version. AnyIPP is keyed by StudentNumber (frozen keys predate IPP repointing).
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
    -- Cycle-scoped attribution source: the student's most recent result across R/W/M in the selected
    -- cycle, whose frozen StudentKey supplies the demographics. Empty when no cycle is selected.
    AnyTouch AS (
        SELECT x.StudentNumber, x.StudentKey,
               ROW_NUMBER() OVER (PARTITION BY x.StudentNumber
                                  ORDER BY x.AssessmentDate DESC, x.LastUpdated DESC) AS rn
        FROM (
            SELECT far.StudentNumber, far.StudentKey, far.AssessmentDate, far.LastUpdated
            FROM FactAssessmentReading far
            WHERE @CycleGroupID IS NOT NULL
              AND far.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT faw.StudentNumber, faw.StudentKey, faw.AssessmentDate, faw.LastUpdated
            FROM FactAssessmentWriting faw
            WHERE @CycleGroupID IS NOT NULL
              AND faw.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT fm.StudentNumber, fm.StudentKey, fm.AssessmentDate, fm.LastUpdated
            FROM FactAssessmentMath fm
            WHERE @CycleGroupID IS NOT NULL
              AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
        ) x
    ),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent R/W/M result
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Homeroom, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM AnyTouch t
        INNER JOIN DimStudent fv ON fv.StudentKey = t.StudentKey
        WHERE t.rn = 1
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Homeroom, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM AnyTouch t2 WHERE t2.StudentNumber = s.StudentNumber))
    ),
    -- In-scope, attributed, P-5 students (role-gated against the ATTRIBUTED school).
    InScope AS (
        SELECT COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
               a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
               a.Grade, sg.GradeOrder,
               a.SchoolID, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation,
               a.ProgramCode, p.ProgramFamily, a.Homeroom,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous
        FROM AttrBase a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE sg.GradeOrder BETWEEN 0 AND 5  -- RWM P..5 (grade 6 math not ready 2026-27)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- Any confirmed IPP in ANY of the three subjects removes the student from this report.
    -- Keyed by StudentNumber (2026-10-30): an attributed row carries a frozen StudentKey, which the
    -- IPP rows' current-version repointing no longer matches.
    AnyIPP AS (
        SELECT DISTINCT ds.StudentNumber
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.IsIPP = 1 AND fsi.Subject IN ('Reading', 'Writing', 'Math')
    ),
    -- Most-recent reading -> achievement code (delta mapped through DimAchievementLevel bounds).
    ReadLatest AS (
        SELECT far.StudentNumber, far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Reading window(s).
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    ReadAch AS (
        SELECT rl.StudentNumber, dal.AchievementLevelCode AS Code
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
        SELECT faw.StudentNumber,
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
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Writing window(s).
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    WriteAch AS (
        SELECT wl.StudentNumber,
               CASE WHEN wl.AvgScore IS NULL   THEN NULL
                    WHEN wl.AvgScore >= 3.50   THEN 4
                    WHEN wl.AvgScore >= 2.75   THEN 3
                    WHEN wl.AvgScore >= 1.75   THEN 2
                    ELSE 1 END AS Code
        FROM WriteLatest wl WHERE wl.rn = 1
    ),
    -- Math roll-up: latest result per task (current-year windows) -> per-unit avg -> avg of unit avgs.
    MathLatest AS (
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathUnit AS (
        SELECT ml.StudentNumber, mt.UnitName, AVG(CAST(ml.Result AS FLOAT)) AS UnitAvg
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.UnitName
    ),
    MathRoll AS (   -- blanks EXCLUDED: unit avg over recorded tasks only
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathUnit GROUP BY StudentNumber
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
        SELECT ml.StudentNumber, mt.GradeCode, mt.UnitName, SUM(CAST(ml.Result AS INT)) AS Ones
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.GradeCode, mt.UnitName
    ),
    MathZeroUnit AS (   -- one row per (student, configured unit): ones / configured (fully-blank unit = 0)
        SELECT isc.StudentNumber,
               CAST(COALESCE(mo.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
        FROM InScope isc
        INNER JOIN TaskUniverse tu ON tu.GradeCode = isc.Grade
        LEFT  JOIN MathUnitOnes mo ON mo.StudentNumber = isc.StudentNumber AND mo.GradeCode = isc.Grade AND mo.UnitName = tu.UnitName
    ),
    MathZeroRoll AS (
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathZeroUnit GROUP BY StudentNumber
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
        isc.Gender,
        isc.SelfIDAfrican,
        isc.SelfIDIndigenous,
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
        CAST(CASE WHEN ra.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasReading,
        CAST(CASE WHEN wa.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasWriting,
        CAST(CASE WHEN mr.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasMath
    FROM InScope isc
    LEFT JOIN ReadAch   ra ON ra.StudentNumber = isc.StudentNumber
    LEFT JOIN WriteAch  wa ON wa.StudentNumber = isc.StudentNumber
    LEFT JOIN MathRoll  mr ON mr.StudentNumber = isc.StudentNumber
    LEFT JOIN MathZeroRoll mz ON mz.StudentNumber = isc.StudentNumber
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentNumber = isc.StudentNumber)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortMathAll  (INLINE table-valued function)
 * Modified: 2026-11-18 — + Gender / SelfIDAfrican / SelfIDIndigenous outputs (Math summary-tree
 *          demographic filter section, in lockstep with the Reading/Writing/RWM feeds of 2026-11-10).
 *          Taken from the SAME DimStudent version that supplies School/Grade/Homeroom (frozen for
 *          attributed rows, current otherwise). Scope, grain and counts unchanged.
 * Modified: 2026-11-17 — + IsChartEligibleMath output: unresolved math IPPs are unmeasured (no band),
 *          matching Reading/Writing (user ruling); the marks stay visible.
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
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with the reading/writing All TVFs
 *          (see tvf_StudentCohortReadingAll's header for the full rationale), CYCLE-SCOPED: with a
 *          cycle selected, a student WITH math results in it attributes School/Grade/Homeroom from the
 *          frozen DimStudent version of their MOST RECENT math result in scope (ONE attribution per
 *          student — the task matrix never splits across schools), so transfers don't move recorded
 *          history and district leavers keep their recorded cycles; students with NO math result stay
 *          current, enrolled students. With no cycle (the "Current" view) everyone anchors on the
 *          current version, as before. The oversight gate follows the ATTRIBUTED school; the TAUGHT
 *          arm stays current-roster. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * Scope: OVERSIGHT (Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 * StaffSchoolAccess, matched against the ATTRIBUTED school) OR TAUGHT (a plain teacher's own students,
 * via FactSectionTeachers — current roster) — so /reports/math renders the same roll-up tree for
 * teachers (2026-10-27). Formerly oversight-only, which returned a teacher no rows and sent them to the
 * card picker — now retired. Math = Primary..Grade 5 (grade 6 not ready 2026-27).
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
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- one value per STUDENT NUMBER (1 = math IPP, 0 = not, NULL = unresolved);
        -- keyed by StudentNumber because attributed rows carry FROZEN StudentKeys
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed students attribute from their
    -- latest result's frozen version and unassessed students are CURRENT, enrolled students; with NO
    -- cycle (the "Current" view) everyone anchors on the current version, as before.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by the latest result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    )
    SELECT
        CAST(a.StudentKey AS VARCHAR(20)) AS StudentKey,
        a.Grade,
        a.Homeroom,
        a.GroupKey                        AS HomeroomKey,   -- the homeroom's tvf_StudentCohortMath key
        a.SchoolID,
        sch.SchoolName,
        a.Gender,                                           -- summary-tree demographic filters (2026-11-18)
        a.SelfIDAfrican,
        a.SelfIDIndigenous,
        ipp.IsIPP                         AS MathIPPStatus,
        -- Measured flag (2026-11-17): 0 = confirmed OR unresolved IPP -> no band anywhere (the client
        -- can't tell "no IPP row" from "unresolved" via MathIPPStatus — both NULL). MAX() only to stay
        -- out of the GROUP BY; it is constant per student.
        MAX(CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END) AS IsChartEligibleMath,
        t.UnitName,                                         -- NULL = no tasks configured for this grade
        MAX(t.UnitOrder)                  AS UnitOrder,
        COUNT(t.MathTaskKey)              AS TaskCount,
        COUNT(lm.Result)                  AS ScoredCount,   -- tasks with a latest 0/1
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM AttrStudents a
    INNER JOIN DimGrade  g   ON g.GradeCode  = a.Grade
    LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
    LEFT  JOIN MathIPP   ipp ON ipp.StudentNumber = a.StudentNumber
    LEFT  JOIN Tasks     t   ON t.GradeCode  = a.Grade
    LEFT  JOIN LatestMath lm
           ON lm.StudentNumber = a.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: the schools the caller covers via StaffSchoolAccess — matched against the
          -- row's ATTRIBUTED school, so recorded history stays with the school that recorded it.
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a plain teacher sees their OWN students in the tree — anyone enrolled in a current
          -- section they teach (current roster; a departed student leaves the teacher's tree). Lets
          -- /reports/math render the same roll-up (Grade/Homeroom toggle) for teachers instead of a
          -- card picker. A teaching-admin matches via either arm.
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = a.StudentKey)
      )
    GROUP BY a.StudentKey, a.Grade, a.Homeroom, a.GroupKey, a.SchoolID, sch.SchoolName,
             a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,   -- constant per StudentKey (no MAX: BIT)
             ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathAll] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortMath  (INLINE table-valued function)
 * Modified: 2026-11-18 — + Gender / SelfIDAfrican / SelfIDIndigenous outputs so the Math summary
 *          tree's drill rows can be filtered on their own data (lockstep with tvf_StudentCohortMathAll).
 *          From the ATTRIBUTED DimStudent version, like School/Grade/Homeroom. Scope and grain unchanged.
 * Modified: 2026-11-17 — + IsChartEligibleMath output: unresolved math IPPs are unmeasured (no band),
 *          matching Reading/Writing (user ruling); the marks stay visible.
 * Purpose: READ-ONLY math cohort matrix for the Reports > Math view (0.7.0, item 4).
 *          One row per (student x applicable task) for ONE group (homeroom / grade /
 *          section) across ALL of the CURRENT school year's math cycles, carrying the
 *          student's LATEST recorded result for that task. The client pivots these into
 *          the read-only matrix (styled like the data-entry grid), groups tasks by unit,
 *          and rolls up class % / per-student averages for the colour-coding + charts.
 * Created: 2026-09-24
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortMathAll
 *          (see tvf_StudentCohortReadingAll's header for the full rationale), CYCLE-SCOPED: with a
 *          cycle selected, a student WITH math results in it attributes School/Grade/Homeroom (and so
 *          their @GroupKey membership) from the frozen DimStudent version of their MOST RECENT math
 *          result in scope (one attribution per student) and the oversight gate follows the ATTRIBUTED
 *          school; students with no math result stay current students. With no cycle ("Current" view)
 *          everyone anchors on the current version, as before. Display names come from the CURRENT
 *          version when one exists (frozen for district leavers). MathIPP + the section-language
 *          lookup are keyed by StudentNumber (frozen keys predate repointing).
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped (a whole school/region matrix would be unusable) + @UPN-scoped: the same
 * OR-across-EXISTS role gate as the entry/Programming TVFs (analyst/admin via
 * StaffSchoolAccess; teacher via FactSectionTeachers). @GroupKey shapes: 'GRADE:<School>:<Grade>',
 * 'SEC:<SectionID>', else a homeroom DimStudent.GroupKey — matched on the ATTRIBUTED version's values.
 * Math is P-5 only, so the cohort is restricted to GradeOrder 0-5.
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
    LatestMathTouch AS ( -- the student's single MOST RECENT math result in scope — its frozen
        -- StudentKey carries the student's attribution (one per student)
        SELECT fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortMathAll so drill rows agree with roll-up
    -- counts): cycle selected -> assessed students from their latest result's frozen version, unassessed
    -- current; no cycle ("Current" view) -> everyone anchors on the current version, as before.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by the latest result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey, fv.ProgramCode,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey, s.ProgramCode,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2 WHERE lt2.StudentNumber = s.StudentNumber))
    ),
    -- The group's attributed students, P-5, intersected with the caller's SCOPE.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName, p.ProgramFamily, ml.MathSectionLanguage,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous
        FROM AttrStudents a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   g  ON g.GradeCode   = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        -- Task text language = the student's MATH SECTION's COURSE language (DimCourseAssessment.Language),
        -- NOT their program: a student physically in an English math section sees English tasks even if FI
        -- (fixes an all-English section flipping to French for one FI student in its roster). A student's
        -- math sections are one language, so MAX(Language) over them is that language. 2026-10-27.
        -- Keyed by StudentNumber (2026-10-30): active enrolments point at the CURRENT StudentKey, which an
        -- attributed (frozen) row no longer carries. A district leaver has no active math enrolment -> NULL
        -- -> English fallback.
        LEFT JOIN (
            SELECT ds.StudentNumber, MAX(ca.Language) AS MathSectionLanguage
            FROM FactEnrollment e
            INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
            INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode
                                             AND ca.Kind = 'Math' AND ca.ActiveFlag = 1
            INNER JOIN DimStudent ds ON ds.StudentKey = e.StudentKey
            WHERE e.ActiveFlag = 1
            GROUP BY ds.StudentNumber
        ) ml ON ml.StudentNumber = a.StudentNumber
        WHERE g.GradeOrder BETWEEN 0 AND 5  -- Math P..5 (grade 6 not ready 2026-27)
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
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathIPP AS (    -- keyed by StudentNumber (frozen keys predate IPP repointing); aggregated so a
        -- multi-family IPP can't fan the matrix out, BIT-cast to keep the output type unchanged
        SELECT dsi.StudentNumber, CAST(MAX(CAST(fsi.IsIPP AS INT)) AS BIT) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
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
        gs.Gender,                                -- summary-tree demographic filters (2026-11-18)
        gs.SelfIDAfrican,
        gs.SelfIDIndigenous,
        CAST(t.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        t.UnitName,
        t.UnitOrder,
        t.QuestionNumber,
        t.DisplayOrder,
        t.OutcomeCode,
        -- Description in the student's MATH SECTION's course language (FR immersion -> FR w/ EN fallback),
        -- NOT their program — matches the entry roster so a cross-program student can't flip the text.
        CASE WHEN gs.MathSectionLanguage = 'French'
             THEN COALESCE(t.TaskDescriptionFR, t.TaskDescriptionEN)
             ELSE t.TaskDescriptionEN END AS TaskDescription,
        lm.Result           AS ExistingResult,   -- BIT: latest 0/1, or NULL if never marked
        ipp.IsIPP           AS MathIPPStatus,     -- 1 = math IPP, 0 = not, NULL = unresolved
        -- Measured flag (2026-11-17): the client can't tell "no IPP row" from "unresolved" via
        -- MathIPPStatus (both NULL). 0 = confirmed OR unresolved IPP -> no band anywhere, in
        -- lockstep with the Reading/Writing chart-eligibility rule.
        CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END AS IsChartEligibleMath
    FROM GroupStudents gs
    INNER JOIN Tasks t ON t.GradeCode = gs.Grade   -- each student gets THEIR grade's tasks
    LEFT JOIN LatestMath lm
           ON lm.StudentNumber = gs.StudentNumber
          AND lm.MathTaskKey   = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentNumber = gs.StudentNumber
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO

/*******************************************************************************
 * Function: tvf_StudentCohortMathTrend  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Math summary tree's "Achievement by cycle" bar chart
 *          (1.4.0). One row per (CYCLE x student x unit) for every STARTED short cycle of the
 *          current school year, carrying the same COUNTS as tvf_StudentCohortMathAll — the unit's
 *          task count, how many of those tasks have a latest result IN THAT CYCLE, and how many of
 *          those are 1 (can do). The client turns the counts into each student's overall
 *          Achievement Level per cycle (same rules as the tree: 80% threshold, IPP handling, Blanks
 *          mode) and stacks one bar per cycle — so the rules live in ONE place (the web model),
 *          not in a second SQL copy.
 * Created: 2026-11-18
 * Region: Canada East (PIIDPA compliant)
 *
 * PER-CYCLE SEMANTICS = tvf_StudentCohortMathAll(@UPN, <that cycle>), for every started cycle in
 * one query. For each cycle: the tasks are the active P-5 tasks at that cycle's math benchmark
 * month(s); a cell is the student's LATEST result per task among that cycle's math windows; a
 * student WITH a math result in the cycle attributes Grade/School (and Gender/Self-ID) from the
 * frozen DimStudent version of their MOST RECENT result in the cycle; students with no result in
 * the cycle are the CURRENT enrolled students. So each bar reproduces what the tree shows with
 * that cycle selected. A student whose grade has no configured tasks for a cycle still returns ONE
 * row (UnitName NULL / TaskCount 0) and lands in "No data" — never silently dropped.
 *
 * "Started cycle" = the Reports cycle selector's own list: DimShortCycle, ActiveFlag = 1, current
 * school year, StartDate <= today (Atlantic). Cycles with no active Math window return no rows.
 *
 * Carries NO names / student numbers (counts + the demographic filter columns only).
 * Scope: identical to tvf_StudentCohortMathAll — OVERSIGHT (Administrator / SpecialistTeacher /
 * RegionalAnalyst via StaffSchoolAccess, matched on the ATTRIBUTED school) OR TAUGHT (a teacher's
 * own current roster via FactSectionTeachers). Math = Primary..Grade 5.
 *
 * READS: DimShortCycle, DimAssessmentWindow, DimCalendar, DimMathTask, DimGrade,
 *        FactAssessmentMath, FactStudentIPP, DimStudent, StaffSchoolAccess, FactSectionTeachers,
 *        DimSection, FactEnrollment. WRITES: nothing.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortMathTrend;
GO

CREATE FUNCTION dbo.tvf_StudentCohortMathTrend(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug) + today (Atlantic)
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr,
               d.Today
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- active math windows of every STARTED current-year cycle + effective benchmark month
        SELECT w.CycleGroupID, w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        INNER JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND sc.ActiveFlag = 1 AND sc.SchoolYear = cy.Yr AND cy.Today >= sc.StartDate
    ),
    Cycles AS (     -- the cycles that have at least one active math window
        SELECT DISTINCT CycleGroupID FROM MathWins
    ),
    CycleTasks AS ( -- active P-5 tasks at each cycle's benchmark month(s); DISTINCT because a cycle
                    -- can hold several math windows on the same month
        SELECT DISTINCT mw.CycleGroupID, mt.MathTaskKey, mt.GradeCode, mt.UnitName
        FROM MathWins mw
        INNER JOIN DimMathTask mt ON mt.AssessmentMonth = mw.BenchMonth
        INNER JOIN DimGrade tg ON tg.GradeCode = mt.GradeCode
        WHERE mt.ActiveFlag = 1
          AND tg.GradeOrder BETWEEN 0 AND 5
    ),
    LatestMath AS ( -- latest result per (cycle, student, task) among that cycle's windows
        SELECT mw.CycleGroupID, fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY mw.CycleGroupID, fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        INNER JOIN MathWins mw ON mw.AssessmentWindowID = fm.AssessmentWindowID
    ),
    LatestMathTouch AS ( -- per cycle, the student's single MOST RECENT math result — its frozen
        -- StudentKey carries the student's attribution for that cycle (one per student per cycle)
        SELECT mw.CycleGroupID, fm.StudentNumber, fm.StudentKey AS FactStudentKey,
               ROW_NUMBER() OVER (PARTITION BY mw.CycleGroupID, fm.StudentNumber
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        INNER JOIN MathWins mw ON mw.AssessmentWindowID = fm.AssessmentWindowID
    ),
    MathIPP AS (    -- one value per STUDENT NUMBER (1 = math IPP, 0 = not, NULL = unresolved)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Math'
        GROUP BY dsi.StudentNumber
    ),
    AttrStudents AS (
        -- assessed in the cycle: attributed by that cycle's latest result's frozen version
        SELECT lt.CycleGroupID, fv.StudentKey, fv.StudentNumber, fv.Grade, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM LatestMathTouch lt
        INNER JOIN DimStudent fv ON fv.StudentKey = lt.FactStudentKey
        WHERE lt.rn = 1
        UNION ALL
        -- not assessed in the cycle: the CURRENT enrolled students
        SELECT c.CycleGroupID, s.StudentKey, s.StudentNumber, s.Grade, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        CROSS JOIN Cycles c
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestMathTouch lt2
                          WHERE lt2.CycleGroupID = c.CycleGroupID
                            AND lt2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(a.CycleGroupID AS VARCHAR(36)) AS CycleGroupID,
        CAST(a.StudentKey AS VARCHAR(20))   AS StudentKey,
        a.Grade,
        a.Gender,
        a.SelfIDAfrican,
        a.SelfIDIndigenous,
        ipp.IsIPP                           AS MathIPPStatus,
        -- Measured flag, same rule as tvf_StudentCohortMathAll: 0 = confirmed OR unresolved IPP.
        MAX(CASE WHEN ipp.StudentNumber IS NULL OR ipp.IsIPP = 0 THEN 1 ELSE 0 END) AS IsChartEligibleMath,
        t.UnitName,                                         -- NULL = no tasks configured for this grade/cycle
        COUNT(t.MathTaskKey)                AS TaskCount,
        COUNT(lm.Result)                    AS ScoredCount,   -- tasks with a latest 0/1 in this cycle
        SUM(CASE WHEN lm.Result = 1 THEN 1 ELSE 0 END) AS CanDoCount
    FROM AttrStudents a
    INNER JOIN DimGrade   g   ON g.GradeCode = a.Grade
    LEFT  JOIN MathIPP    ipp ON ipp.StudentNumber = a.StudentNumber
    LEFT  JOIN CycleTasks t   ON t.CycleGroupID = a.CycleGroupID
                             AND t.GradeCode    = a.Grade
    LEFT  JOIN LatestMath lm
           ON lm.CycleGroupID  = a.CycleGroupID
          AND lm.StudentNumber = a.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
          AND lm.rn = 1
    WHERE g.GradeOrder BETWEEN 0 AND 5   -- Math P..5 (grade 6 not ready 2026-27)
      AND (
          -- OVERSIGHT: schools the caller covers, matched against the row's ATTRIBUTED school
          EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
          -- TAUGHT: a teacher's OWN students — anyone enrolled in a current section they teach
       OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                  INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                  INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                  WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1
                    AND e.StudentKey = a.StudentKey)
      )
    GROUP BY a.CycleGroupID, a.StudentKey, a.Grade,
             a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,   -- constant per StudentKey (no MAX: BIT)
             ipp.IsIPP, t.UnitName
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMathTrend] TO [StudentDataAssessment];
GO

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

/*******************************************************************************
 * VERIFY (read-only): expect 12 rows, every modify_date = this run.
 ******************************************************************************/
SELECT o.name, o.modify_date
FROM sys.objects o
WHERE o.name IN ('tvf_StudentCohort', 'tvf_StudentCohortWriting', 'tvf_StudentCohortReadingAll',
                 'tvf_StudentCohortReadingGroup', 'tvf_StudentCohortWritingAll',
                 'tvf_StudentCohortWritingGroup', 'tvf_StudentCohortRWM', 'tvf_StudentCohortMathAll',
                 'tvf_StudentCohortMath', 'tvf_StudentCohortMathTrend', 'tvf_MissingDataAll',
                 'tvf_MissingDataGroup')
ORDER BY o.name;
GO
