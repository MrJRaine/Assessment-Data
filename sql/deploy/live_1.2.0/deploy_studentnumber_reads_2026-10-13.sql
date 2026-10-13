/*******************************************************************************
 * Server-side patch (warehouse-only) — STAGE 3 of 3 of the StudentNumber durable fix.
 * See deploy_studentnumber_fact_relink_2026-10-13.sql (Stage 1) for full rationale.
 *
 * Switches every web-app READ that ties an assessment fact to the CURRENT student
 * from the mutable StudentKey (SCD surrogate, frozen at entry) to the stable
 * StudentNumber. After an SCD re-version, a student's results used to strand (the
 * read joined current StudentKey = fact StudentKey and missed the old rows). Now the
 * join / PARTITION / per-student filter is on StudentNumber, so results follow the
 * student across re-versions. Behaviour is otherwise identical.
 *
 * Objects redeployed (DROP-IF-EXISTS + CREATE + GRANT; the view is first because the
 * cohort/roster/history TVFs reference it):
 *   vw_StudentReadingStartingPoint
 *   tvf_StudentCohort / tvf_StudentCohortWriting / tvf_StudentCohortMath /
 *   tvf_StudentCohortMathAll / tvf_StudentCohortRWM
 *   tvf_TeacherRoster / tvf_TeacherRosterOwn / tvf_TeacherRosterMath / tvf_TeacherRosterWriting
 *   tvf_UserAssessmentWindows / tvf_TeacherGroups
 *   tvf_StudentAssessmentHistory / tvf_StudentAssessmentHistoryWriting / tvf_StudentRWMHistory
 *
 * Reads only (no table writes). Idempotent. PREREQUISITE: Stages 1 & 2 first
 * (StudentNumber must exist + be populated on the facts). Dev first, then live.
 *
 * NOTE: the LEGACY Power Apps views (vw_StudentCohort, vw_TeacherRoster,
 * vw_UserAssessmentWindows, vw_StudentAssessmentHistory, vw_TeacherGroups, bridge_views)
 * are NOT converted — the web app does not read them; they go when the Power App retires.
 * IPP / Adaptation / Enrollment reads are out of scope (they key on StudentKey too, but
 * are re-pointed on ingest / current-filtered; a separate review if they ever strand).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/


/* ============================ vw_StudentReadingStartingPoint ============================ */
/*******************************************************************************
 * View: vw_StudentReadingStartingPoint
 * Purpose: Each student's READING "starting point" for the current school year —
 *          the last recorded reading level from the PREVIOUS school year — so the
 *          roster can show where a student began and the cumulative progress since.
 * Created: 2026-09-10
 * Region:  Canada East (PIIDPA compliant)
 *
 * YEAR-FLIP ABSTRACTION (must stay this shape): the starting point is
 *   COALESCE( latest prior-school-year FactAssessmentReading , PriorYearBaseline seed ).
 * This school year (2026-2027) the prior year (2025-2026) has NO in-system facts, so
 * it resolves to the PriorYearBaseline seed. From Sept 2027 the prior year IS in the
 * facts, so it resolves there automatically — ZERO code change at the flip; the seed
 * is only for the pre-system year. "Previous year" is derived from Atlantic today
 * (school year = Sep..Aug). Grain: one row per (StudentNumber, ScaleSystem).
 *
 * StartingLevelOrder is NULL when the level doesn't map to a DimReadingScale level
 * (e.g. a baseline code ABS/INS/EAL) — the caller then shows the level with no Δ.
 ******************************************************************************/

DROP VIEW IF EXISTS dbo.vw_StudentReadingStartingPoint;
GO

CREATE VIEW dbo.vw_StudentReadingStartingPoint
AS
WITH Today AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS d
),
Yr AS (
    SELECT
        CASE WHEN MONTH(d) >= 9 THEN CONCAT(CAST(YEAR(d)-1 AS VARCHAR(4)), '-', CAST(YEAR(d)   AS VARCHAR(4)))
             ELSE CONCAT(CAST(YEAR(d)-2 AS VARCHAR(4)), '-', CAST(YEAR(d)-1 AS VARCHAR(4))) END AS PriorYear
    FROM Today
),
-- Latest prior-school-year reading fact per (StudentNumber, ScaleSystem).
PriorFact AS (
    SELECT
        far.StudentNumber, drs.ScaleSystem, drs.LevelCode, drs.LevelOrder,
        ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                           ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
    FROM FactAssessmentReading far
    INNER JOIN DimAssessmentWindow w   ON w.AssessmentWindowID = far.AssessmentWindowID
    INNER JOIN Yr                       ON w.SchoolYear        = Yr.PriorYear
    INNER JOIN DimReadingScale drs      ON drs.ReadingScaleID  = far.ReadingScaleID
),
-- Baseline seed: only exists for the pre-system prior year (2025-2026). Map the
-- assessment language to the reading scale system; level code joins DimReadingScale.
BaselineSeed AS (
    SELECT
        b.StudentNumber,
        CASE WHEN b.AssessmentLanguage = 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem,
        b.ReadingLevel AS LevelCode
    FROM PriorYearBaseline b
    INNER JOIN Yr ON b.SchoolYear = Yr.PriorYear
    WHERE b.ReadingLevel IS NOT NULL
)
SELECT
    COALESCE(pf.StudentNumber, bs.StudentNumber) AS StudentNumber,
    COALESCE(pf.ScaleSystem,   bs.ScaleSystem)   AS ScaleSystem,
    COALESCE(pf.LevelCode,     bs.LevelCode)     AS StartingLevelCode,
    COALESCE(pf.LevelOrder,    bsrs.LevelOrder)  AS StartingLevelOrder,
    CASE WHEN pf.StudentNumber IS NOT NULL THEN 'fact' ELSE 'baseline' END AS StartingSource
FROM (SELECT * FROM PriorFact WHERE rn = 1) pf
FULL OUTER JOIN BaselineSeed bs
       ON bs.StudentNumber = pf.StudentNumber
      AND bs.ScaleSystem   = pf.ScaleSystem
LEFT JOIN DimReadingScale bsrs
       ON bsrs.ScaleSystem = bs.ScaleSystem
      AND bsrs.LevelCode   = bs.LevelCode;
GO

GRANT SELECT ON [dbo].[vw_StudentReadingStartingPoint] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentCohort ============================ */
/*******************************************************************************
 * Function: tvf_StudentCohort  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentCohort for the web app
 *          (Phase 3b). The app connects as the StudentDataAssessment service
 *          principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped view returns nothing. This iTVF takes the signed-in
 *          UPN and runs the SAME OR-across-EXISTS role branches (RegionalAnalyst
 *          / Administrator+SpecialistTeacher / Teacher), so admins/analysts get
 *          their full multi-school cohort.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * One row per student in scope + most-recent (lifetime) reading evidence, the
 * Reading-IPP gate, and the achievement band/colour for that latest delta.
 * Mirrors vw_StudentCohort verbatim except CURRENT_USER -> LOWER(@UPN). Keep the
 * two in sync until the Power App is retired.
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (the
 * client never supplies it). See tvf_UserAssessmentWindows header.
 * ORDER BY intentionally omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohort;
GO

-- @CycleGroupID (added 2026-10-05): NULL = lifetime most-recent reading (the "Current" view, unchanged);
-- a DimShortCycle.CycleGroupID scopes the latest-pick to that cycle's Reading window(s) so the report
-- is time-bound to one cycle. Callers must pass both args (TVF params can't be omitted even with a default).
CREATE FUNCTION dbo.tvf_StudentCohort(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH LatestReading AS (
        SELECT
            far.StudentNumber,   -- match the latest result to the student by the STABLE key (survives SCD re-version)
            far.ReadingAssessmentID,
            far.AssessmentWindowID,
            far.ReadingScaleID,
            far.ReadingDelta,
            far.AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY far.StudentNumber
                ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading far
        -- Cycle scoping: NULL = lifetime most-recent; a cycle id restricts to that cycle's Reading
        -- window(s), so the latest-pick becomes the latest result WITHIN the selected cycle.
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
              )
    ),
    CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    ),
    -- Effective benchmark month per reading window (BenchmarkMonth, else the window's dominant calendar
    -- month) — matched against DimReadingBenchmark for the Expected range (item 2).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        crd.IsIPP                                               AS IsIPP_Reading,
        CASE
            WHEN crd.StudentKey IS NULL THEN 'N/A'
            WHEN crd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN crd.IsIPP = 1          THEN 'IPP'
            WHEN crd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Reading,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        lr.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        drs.LevelCode                                           AS MostRecentLevelCode,
        drs.LevelOrder                                          AS MostRecentLevelOrder,
        lr.ReadingDelta                                         AS MostRecentReadingDelta,
        -- Expected benchmark range for the MOST-RECENT evidence's window month + the student's reading
        -- family (item 2) — so a SCoR 1 level shows the SCoR 1 expectation.
        drb.ExpectedMinLevel                                    AS ExpectedMinLevel,
        drb.ExpectedMaxLevel                                    AS ExpectedMaxLevel,
        -- Prev-June prior-year starting point + Diff from it (item 1); Reading only. NULL when either
        -- the June anchor or the current level is missing.
        sp.StartingLevelCode                                    AS JuneReadingLevel,
        CASE WHEN drs.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN drs.LevelOrder - jrs.LevelOrder END           AS DiffFromPrevJune,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestReading lr ON lr.StudentNumber = s.StudentNumber AND lr.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lr.AssessmentWindowID
    LEFT JOIN DimReadingScale drs ON drs.ReadingScaleID = lr.ReadingScaleID
    -- Expected range for the most-recent window's month + the student's reading family (J020 -> English).
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = lr.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = s.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE WHEN s.ProgramCode = 'J020' THEN 'English' ELSE p.ProgramFamily END
    -- Prev-June anchor (by family scale, J020 -> EN_Reading) + its order, for Diff from Prev June.
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = s.StudentNumber
          AND sp.ScaleSystem   = CASE WHEN s.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                      WHEN p.ProgramFamily = 'English'          THEN 'EN_Reading'
                                      WHEN p.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END
    LEFT JOIN DimReadingScale jrs
           ON jrs.LevelCode   = sp.StartingLevelCode
          AND jrs.ScaleSystem = CASE WHEN s.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                     WHEN p.ProgramFamily = 'English'          THEN 'EN_Reading'
                                     WHEN p.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentCohort] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentCohortWriting ============================ */
/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentCohort for the web app's cohort
 *          screen (Reading|Writing toggle). One row per student in the signed-in
 *          user's scope + their MOST-RECENT writing evidence: the four trait
 *          scores (Ideas/Organization/Language/Conventions), their average, and
 *          the achievement band that average falls in. Plus the Writing-IPP gate.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Achievement band: writing has NO benchmark/delta. The average of the four
 * 1-4 traits maps to a band CODE by fixed cut scores, and that code joins
 * DimAchievementLevel to reuse the SAME band names + colours as reading:
 *     avg >= 3.50 -> 4 Exceeding | >= 2.75 -> 3 Meeting | >= 1.75 -> 2 Approaching | else 1 Not Yet Meeting
 * (No Domain filter needed: we join DimAchievementLevel by code, for name/colour
 * only -- its reading delta bounds are not used here.)
 *
 * Role branches (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher)
 * are identical to tvf_StudentCohort -- caller passed as @UPN. SECURITY: trusts
 * @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH LatestWriting AS (
        SELECT
            faw.StudentNumber,   -- stable key: match latest result to the student across SCD re-versions
            faw.WritingAssessmentID,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
            -- denominator (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha): TRY_CAST('-' AS
            -- INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
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
            ROW_NUMBER() OVER (
                PARTITION BY faw.StudentNumber
                ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting faw
        -- @CycleGroupID (2026-10-07): NULL = lifetime latest ("Current"); a cycle id scopes the
        -- latest-pick to that cycle's Writing window(s). Mirrors tvf_StudentCohort.
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        cwd.IsIPP                                               AS IsIPP_Writing,
        CASE
            WHEN cwd.StudentKey IS NULL THEN 'N/A'
            WHEN cwd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN cwd.IsIPP = 1          THEN 'IPP'
            WHEN cwd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Writing,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        lw.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        lw.IdeasScore                                           AS MostRecentIdeasScore,
        lw.OrganizationScore                                    AS MostRecentOrganizationScore,
        lw.LanguageScore                                        AS MostRecentLanguageScore,
        lw.ConventionsScore                                     AS MostRecentConventionsScore,
        lw.AvgScore                                             AS MostRecentAvgScore,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestWriting lw ON lw.StudentNumber = s.StudentNumber AND lw.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lw.AssessmentWindowID
    -- Map the average to a band CODE, then reuse DimAchievementLevel's name + colour by code.
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentCohortMath ============================ */
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
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result, fm.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
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
           ON lm.StudentNumber = gs.StudentNumber
          AND lm.MathTaskKey   = CAST(t.MathTaskKey AS BIGINT)
          AND lm.rn = 1
    LEFT JOIN MathIPP ipp ON ipp.StudentKey = gs.StudentKey
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortMath] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentCohortMathAll ============================ */
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
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
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
           ON lm.StudentNumber = s.StudentNumber
          AND lm.MathTaskKey   = t.MathTaskKey
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

/* ============================ tvf_StudentCohortRWM ============================ */
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
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentKey = isc.StudentKey)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO

/* ============================ tvf_TeacherRoster ============================ */
/*******************************************************************************
 * Function: tvf_TeacherRoster  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web app entry grid (Phase 3b).
 *          Combines vw_TeacherRoster's three role branches (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst) with the per-student
 *          entry context the grid shows (existing level + delta, expected
 *          benchmark range for the window's dominant month, reading-IPP status).
 *          Returns one row per student for the given window + group.
 * Created: 2026-06-22
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName
 *          so the roster page can show a friendly header.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic: a student is
 *          matched by their homeroom key OR (HS) a section key, so the oversight
 *          picker's Homeroom lens resolves an HS homeroom card instead of empty.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key (oversight
 *          Grade lens = a whole school+grade cohort). SchoolID threaded through.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution — see the block comment below.
 *          Homeroom / 'GRADE:' keys are no longer resolved here (course-scoped entry only ever
 *          sends 'SEC:'); recover from git if ever needed.
 *          2026-09-23 — MATERIALIZED membership. The ingest-stable half (which students sit in
 *          which subject-mapped section per window + their static attrs) now comes pre-joined from
 *          SectionRosterMembership, rebuilt each ingest by usp_RebuildRosterMembership. This TVF
 *          reads that table + a LIVE access predicate (FactSectionTeachers / StaffSchoolAccess),
 *          replacing the per-request DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join
 *          that measured ~2s for 20 students. The VOLATILE half below (reading results, deltas,
 *          benchmark, IPP, achievement, starting point) is unchanged and still live. Membership
 *          logic lives in usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). Role logic mirrors
 * vw_TeacherRoster; benchmark/IPP enrichment mirrors vw_BridgeTeacherRosterAll.
 * No section columns are projected, so SELECT DISTINCT collapses the PP-9
 * per-section fan-out to one row per student. ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRoster;
GO

-- @GroupKeys: a COMMA-DELIMITED list of group keys, so several same-language course sections can be
-- entered as one combined roster. A single key is just a list of one (back-compatible).
CREATE FUNCTION dbo.tvf_TeacherRoster(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage, w.BenchmarkMonth
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    -- ------------------------------------------------------------------------------------------
    -- MATERIALIZED membership (2026-09-23). The heavy section->student SCD join is gone; the rows
    -- for the requested classes come pre-joined from SectionRosterMembership (rebuilt each ingest).
    -- Access is still resolved LIVE, as a predicate on that handful of sections: a teacher via
    -- FactSectionTeachers, an oversight role via StaffSchoolAccess on the section's school. Same
    -- rules as before, none of the per-request enrolment/dimension joins.
    -- ------------------------------------------------------------------------------------------
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom,
               m.SchoolName, m.ProgramCode, m.ProgramFamily
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.ProgramCode, m.ProgramFamily, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        -- RegionalAnalyst scoped by StaffSchoolAccess like Admin (NO region-wide branch;
        -- a region-wide analyst simply has every building listed).
        WHERE (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = m.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                      AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    -- Latest reading entry per (student, window). Multiple dated entries per window are now
    -- allowed (ongoing-assessment model), so the roster shows the MOST RECENT one -- without this
    -- rn=1 pick the join would fan a student out to one grid row per entry date.
    LatestReadingInWindow AS (
        SELECT
            StudentNumber, AssessmentWindowID, ReadingScaleID, ReadingDelta, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentNumber, AssessmentWindowID
                ORDER BY AssessmentDate DESC, ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- Cross-cycle reading history per student: the latest level in EACH window (wrn=1),
    -- then windows ranked newest-first (rn). rn=1 = last recorded level (any cycle);
    -- rn=2 = the previous cycle's level. Keyed by StudentNumber so it survives SCD
    -- versioning. Drives "Since June" (last vs June) and "Diff from Prev Cycle" (rn1 vs rn2).
    ReadingByWindow AS (
        SELECT ds.StudentNumber, far.AssessmentWindowID, drs.LevelCode, drs.LevelOrder, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY ds.StudentNumber, far.AssessmentWindowID
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS wrn
        FROM FactAssessmentReading far
        INNER JOIN DimStudent          ds  ON ds.StudentKey        = far.StudentKey
        INNER JOIN DimReadingScale     drs ON drs.ReadingScaleID   = far.ReadingScaleID
        INNER JOIN DimAssessmentWindow rw  ON rw.AssessmentWindowID = far.AssessmentWindowID
        -- Scope to the current cycle's SCHOOL YEAR (previous cycle is within the year) so the
        -- cross-cycle scan stays small instead of ranking all reading history for every student.
        WHERE rw.SchoolYear = (SELECT w2.SchoolYear FROM DimAssessmentWindow w2
                               WHERE w2.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT))
    ),
    ReadingCycleRank AS (
        SELECT StudentNumber, LevelCode, LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY AssessmentDate DESC) AS rn
        FROM ReadingByWindow
        WHERE wrn = 1
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        sg.Homeroom,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.SchoolName,
        -- Effective reading scale: the cycle's declared scale when it's language-scoped,
        -- else per-student by family -- with J020 (late immersion) always EN_Reading.
        COALESCE(wed.ScaleSystem,
                 CASE WHEN sg.ProgramCode      = 'J020'             THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'English'          THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'French Immersion' THEN 'FR_Reading' END) AS ScaleSystem,
        drs.LevelCode        AS ExistingScaleValue,
        far.AssessmentDate   AS ExistingAssessmentDate,
        drb.ExpectedMinLevel AS ExpectedMinLevel,
        drb.ExpectedMaxLevel AS ExpectedMaxLevel,
        ipp.IsIPP            AS ReadingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ReadingIPPNeedsConfirmation,
        -- Reading family the app confirms an IPP under (matches the ipp join above); cycle language wins, J020 -> English.
        CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
             WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
             WHEN sg.ProgramCode = 'J020'            THEN 'English'
             ELSE sg.ProgramFamily END AS IPPProgramFamily,
        -- Achievement band (delta -> colour/name) is computed CLIENT-SIDE in RosterEntry (it must
        -- update live as the teacher picks a level), so the old DimAchievementLevel join + its
        -- columns were dead server work and were removed 2026-09-23.
        -- "Prev June" prior-year starting level (auto-flips to prior-year facts from
        -- Sept 2027 — see vw_StudentReadingStartingPoint):
        sp.StartingLevelCode     AS JuneReadingLevel,     -- "Prev June" anchor
        lastR.LevelCode          AS LastReadingLevel,     -- last recorded level, ANY cycle (fallback current)
        prevR.LevelCode          AS PrevCycleReadingLevel -- the cycle before the last (for Diff)
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestReadingInWindow far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentNumber      = sg.StudentNumber
          AND far.rn = 1
    LEFT JOIN DimReadingScale drs
           ON drs.ReadingScaleID = far.ReadingScaleID
    -- Benchmark + reading-IPP resolve by the EFFECTIVE reading family: the cycle's language when
    -- scoped ('English'/'French Immersion'), else per-student, with J020 (late immersion) -> 'English'.
    LEFT JOIN DimReadingBenchmark drb
           ON drb.ProgramFamily   =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND drb.GradeCode       = sg.Grade
          AND drb.AssessmentMonth = wdm.DominantMonth
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Reading'
          AND ipp.ProgramFamily =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND ipp.IsCurrent     = 1
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = sg.StudentNumber
          AND sp.ScaleSystem   = COALESCE(wed.ScaleSystem,
                                     CASE WHEN sg.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'English'          THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END)
    LEFT JOIN ReadingCycleRank lastR ON lastR.StudentNumber = sg.StudentNumber AND lastR.rn = 1
    LEFT JOIN ReadingCycleRank prevR ON prevR.StudentNumber = sg.StudentNumber AND prevR.rn = 2
    -- Access + group match already applied in StudentGroups, so every row reaching here is wanted.
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO

/* ============================ tvf_TeacherRosterOwn ============================ */
/*******************************************************************************
 * Function: tvf_TeacherRosterOwn  (INLINE table-valued function)
 * Purpose: FAST-PATH Reading roster for a TEACHER opening their OWN class (Taught
 *          scope). Reads the pre-projected TeacherRosterMembership table directly by
 *          (TeacherEmail, GroupKey) — no DimStaff Caller lookup and NO access-check
 *          subqueries (FactSectionTeachers / StaffSchoolAccess): a row's presence in
 *          that table IS the authorization (it was built as base ⨝ the teacher's own
 *          sections). The volatile reading-enrichment half is identical to
 *          tvf_TeacherRoster, so the two return the same shape.
 *
 *          The app routes here when the selected group card's Scope = 'Taught';
 *          Oversight cards go to tvf_TeacherRoster (base table + live school check).
 *          Membership logic lives in usp_RebuildRosterMembership — keep in lockstep.
 * Created: 2026-09-23
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN (the app passes the authenticated caller). The teacher table
 * is keyed by TeacherEmail, so filtering on @UPN returns ONLY that teacher's own
 * students — the scoping is baked into the table, not re-derived here.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterOwn;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterOwn(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
RETURNS TABLE
AS
RETURN
(
    WITH WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage, w.BenchmarkMonth
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    -- FAST membership: read the teacher's own pre-projected rows. No Caller lookup, no access
    -- predicate — the row exists in TeacherRosterMembership only because this teacher teaches
    -- that section (base ⨝ FactSectionTeachers at rebuild time).
    StudentGroups AS (
        SELECT DISTINCT
            t.AssessmentWindowID, t.StudentKey, t.StudentNumber, t.FirstName, t.LastName,
            t.Grade, t.Homeroom, t.SchoolName, t.ProgramCode, t.ProgramFamily, t.GroupKey
        FROM TeacherRosterMembership t
        WHERE LOWER(t.TeacherEmail) = LOWER(@UPN)
          AND t.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + t.GroupKey + ',%')
    ),
    -- Latest reading entry per (student, window) — most recent wins (ongoing-assessment model).
    LatestReadingInWindow AS (
        SELECT
            StudentNumber, AssessmentWindowID, ReadingScaleID, ReadingDelta, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentNumber, AssessmentWindowID
                ORDER BY AssessmentDate DESC, ReadingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentReading
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- Cross-cycle reading history per student: latest level in EACH window (wrn=1), windows
    -- ranked newest-first (rn). rn=1 = last recorded level; rn=2 = previous cycle. Keyed by
    -- StudentNumber so it survives SCD versioning.
    ReadingByWindow AS (
        SELECT ds.StudentNumber, far.AssessmentWindowID, drs.LevelCode, drs.LevelOrder, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY ds.StudentNumber, far.AssessmentWindowID
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS wrn
        FROM FactAssessmentReading far
        INNER JOIN DimStudent          ds  ON ds.StudentKey        = far.StudentKey
        INNER JOIN DimReadingScale     drs ON drs.ReadingScaleID   = far.ReadingScaleID
        INNER JOIN DimAssessmentWindow rw  ON rw.AssessmentWindowID = far.AssessmentWindowID
        WHERE rw.SchoolYear = (SELECT w2.SchoolYear FROM DimAssessmentWindow w2
                               WHERE w2.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT))
    ),
    ReadingCycleRank AS (
        SELECT StudentNumber, LevelCode, LevelOrder,
               ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY AssessmentDate DESC) AS rn
        FROM ReadingByWindow
        WHERE wrn = 1
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.Grade,
        sg.Homeroom,
        sg.GroupKey,
        sg.SchoolName,
        COALESCE(wed.ScaleSystem,
                 CASE WHEN sg.ProgramCode      = 'J020'             THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'English'          THEN 'EN_Reading'
                      WHEN sg.ProgramFamily     = 'French Immersion' THEN 'FR_Reading' END) AS ScaleSystem,
        drs.LevelCode        AS ExistingScaleValue,
        far.AssessmentDate   AS ExistingAssessmentDate,
        drb.ExpectedMinLevel AS ExpectedMinLevel,
        drb.ExpectedMaxLevel AS ExpectedMaxLevel,
        ipp.IsIPP            AS ReadingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ReadingIPPNeedsConfirmation,
        CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
             WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
             WHEN sg.ProgramCode = 'J020'            THEN 'English'
             ELSE sg.ProgramFamily END AS IPPProgramFamily,
        -- Achievement band computed CLIENT-SIDE (see tvf_TeacherRoster); join removed 2026-09-23.
        sp.StartingLevelCode     AS JuneReadingLevel,
        lastR.LevelCode          AS LastReadingLevel,
        prevR.LevelCode          AS PrevCycleReadingLevel
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN LatestReadingInWindow far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentNumber      = sg.StudentNumber
          AND far.rn = 1
    LEFT JOIN DimReadingScale drs
           ON drs.ReadingScaleID = far.ReadingScaleID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.ProgramFamily   =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND drb.GradeCode       = sg.Grade
          AND drb.AssessmentMonth = wdm.DominantMonth
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Reading'
          AND ipp.ProgramFamily =
              CASE WHEN wed.AssessmentLanguage = 'English' THEN 'English'
                   WHEN wed.AssessmentLanguage = 'French'  THEN 'French Immersion'
                   WHEN sg.ProgramCode = 'J020'            THEN 'English'
                   ELSE sg.ProgramFamily END
          AND ipp.IsCurrent     = 1
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = sg.StudentNumber
          AND sp.ScaleSystem   = COALESCE(wed.ScaleSystem,
                                     CASE WHEN sg.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'English'          THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END)
    LEFT JOIN ReadingCycleRank lastR ON lastR.StudentNumber = sg.StudentNumber AND lastR.rn = 1
    LEFT JOIN ReadingCycleRank prevR ON prevR.StudentNumber = sg.StudentNumber AND prevR.rn = 2
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterOwn] TO [StudentDataAssessment];
GO

/* ============================ tvf_TeacherRosterMath ============================ */
/*******************************************************************************
 * Function: tvf_TeacherRosterMath  (INLINE table-valued function)
 * Purpose: @UPN-parameterized roster for the web-app MATH entry grid. Returns ONE
 *          ROW PER (student x applicable task): each student joined to THEIR grade's
 *          DimMathTask set for the cycle's month, with the latest recorded result and
 *          Math-IPP status. The web app pivots these into the student x task matrix.
 * Created: 2026-09-03
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for homerooms.
 *          2026-09-15b — @GroupKey resolves homeroom / section / 'GRADE:' cohort keys.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST; DimMathTask join INNER -> LEFT so a
 *          student whose grade/month has no tasks still appears; three role branches replaced by
 *          SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The per-student TASK
 *          enrichment (DimMathTask by grade/month, latest result, Math-IPP) is unchanged and still
 *          live. Membership logic lives in usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Task selection: DimMathTask WHERE GradeCode = student.Grade AND AssessmentMonth = the cycle's
 *   benchmark/dominant month AND ActiveFlag = 1. Description/answer key chosen by program (FI -> FR
 *   text, falling back to EN until FR is seeded).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. Role logic mirrors tvf_TeacherRoster.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterMath;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterMath(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
               w.BenchmarkMonth, w.ProgramFamily
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND w.AssessmentType = 'Math'
    ),
    WindowDominantMonth AS (
        SELECT
            wed.AssessmentWindowID,
            COALESCE(
                wed.BenchmarkMonth,
                (SELECT TOP 1 dc.Month
                 FROM DimCalendar dc
                 WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
                 GROUP BY dc.Month
                 ORDER BY COUNT(*) DESC, dc.Month)
            ) AS DominantMonth
        FROM WindowEffectiveDates wed
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes; access
    -- resolved LIVE as a predicate on that handful of sections.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom,
               m.SchoolName, m.ProgramFamily
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.ProgramFamily, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        WHERE (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = m.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                      AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    -- Latest math result per (student, window, task). Dated history is kept, so pick the most recent.
    LatestMathPerTask AS (
        SELECT
            StudentNumber, AssessmentWindowID, MathTaskKey, Result, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentNumber, AssessmentWindowID, MathTaskKey
                ORDER BY AssessmentDate DESC, MathAssessmentID DESC
            ) AS rn
        FROM FactAssessmentMath
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        sg.ProgramFamily,
        CAST(mt.MathTaskKey AS VARCHAR(20)) AS MathTaskKey,
        mt.UnitName,
        mt.UnitOrder,
        mt.QuestionNumber,
        mt.DisplayOrder,
        mt.OutcomeCode,
        -- Program picks the language of the task text (one task key, two descriptions).
        CASE WHEN sg.ProgramFamily = 'French Immersion'
             THEN COALESCE(mt.TaskDescriptionFR, mt.TaskDescriptionEN)
             ELSE mt.TaskDescriptionEN END AS TaskDescription,
        -- Answer key follows the task's language (the FR answer key shows with the FR task text).
        CASE WHEN sg.ProgramFamily = 'French Immersion'
             THEN COALESCE(mt.AnswerKeyFR, mt.AnswerKey)
             ELSE mt.AnswerKey END AS AnswerKey,
        fam.Result            AS ExistingResult,          -- BIT: latest 0/1, or NULL if never marked
        fam.AssessmentDate    AS ExistingAssessmentDate,
        ipp.IsIPP             AS MathIPPStatus,           -- 1 = math IPP, 0 = not, NULL = unresolved gate
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS MathIPPNeedsConfirmation,
        COALESCE(wed.ProgramFamily, sg.ProgramFamily)    AS IPPProgramFamily
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
    -- Each student gets THEIR grade's tasks for the cycle's month. LEFT so a student whose grade has
    -- no active tasks still comes back (with NULL task columns) instead of vanishing.
    LEFT JOIN DimMathTask mt
           ON mt.GradeCode       = sg.Grade
          AND mt.AssessmentMonth = wdm.DominantMonth
          AND mt.ActiveFlag      = 1
    LEFT JOIN LatestMathPerTask fam
           ON fam.StudentNumber      = sg.StudentNumber
          AND fam.AssessmentWindowID = sg.AssessmentWindowID
          AND fam.MathTaskKey        = CAST(mt.MathTaskKey AS BIGINT)
          AND fam.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Math'
          AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
          AND ipp.IsCurrent     = 1
);
GO

-- DROP+CREATE drops object-level grants. Re-grant so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_TeacherRosterMath] TO [StudentDataAssessment];
GO

/* ============================ tvf_TeacherRosterWriting ============================ */
/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping — only the per-student entry context differs: the MOST
 *          RECENT writing entry's four trait scores + their average + achievement
 *          band, plus Writing-IPP status. No benchmark / delta (writing has none).
 *          One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key.
 *          2026-09-17 — DUAL-LANGUAGE writing: @Language ('English'|'French') param
 *          (the EN/FR toggle). Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The EN/FR toggle now filters
 *          by the SECTION's language (SectionRosterMembership.SectionLanguage, from
 *          DimCourseAssessment) — the section decides the language, NOT the student's program. The
 *          volatile writing-scores half is unchanged. Membership logic lives in
 *          usp_RebuildRosterMembership — keep the two in lockstep.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour. SECURITY: trusts @UPN; SELECT
 * granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT w.AssessmentWindowID, w.AssessmentLanguage, w.BenchmarkMonth, w.StartDate
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes, access
    -- resolved LIVE as a predicate. The EN/FR toggle filters by the SECTION's language.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.SectionLanguage, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom, m.SchoolName
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE (
                (c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
                 AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                             WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                        WHERE fst.SectionID = m.SectionID
                          AND LOWER(fst.TeacherEmail) = c.Email
                          AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                        AND COALESCE(fst.EffectiveEndDate, '9999-12-31')))
          -- Language track = the SECTION's course language. Effective language is the cycle's scope
          -- when set, else the EN/FR toggle. (For a scoped window the base already holds only that
          -- language's sections; the predicate is a harmless no-op then and does the real work when
          -- the window is unscoped and @GroupKeys could span languages.)
          AND m.SectionLanguage = COALESCE(wed.AssessmentLanguage, @Language)
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentNumber, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded = deliberately not assessed), 'SCR' (scribed) and NULL all drop from
            -- BOTH the sum and the count (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha):
            -- TRY_CAST('-' AS INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN IdeasScore        IN ('1','2','3','4') THEN CAST(IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN OrganizationScore IN ('1','2','3','4') THEN CAST(OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN LanguageScore     IN ('1','2','3','4') THEN CAST(LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN CAST(ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentNumber, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          -- Show the score for the effective track: the cycle's language when scoped, else the toggle.
          AND AssessmentLanguage = COALESCE(
                (SELECT w.AssessmentLanguage FROM DimAssessmentWindow w
                 WHERE w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)), @Language)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        faw.IdeasScore         AS ExistingIdeasScore,
        faw.OrganizationScore  AS ExistingOrganizationScore,
        faw.LanguageScore      AS ExistingLanguageScore,
        faw.ConventionsScore   AS ExistingConventionsScore,
        faw.AvgScore           AS ExistingAvgScore,
        faw.AssessmentDate     AS ExistingAssessmentDate,
        ipp.IsIPP              AS WritingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS WritingIPPNeedsConfirmation,
        -- Writing IPP family follows the effective language track (cycle scope, else toggle).
        -- Achievement band is computed CLIENT-SIDE in WritingRosterEntry (writingBand), so the
        -- DimAchievementLevel join + its columns were dead server work; removed 2026-09-23.
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily,
        -- Data-driven trait exclusions for this student's grade x ACTUAL program family x the cycle's
        -- benchmark month (WritingTraitExclusion) — the grid hides these dropdowns; the upsert enforces
        -- the NULL. Keyed on the student's real ProgramFamily (matches the upsert), not the language track.
        (SELECT STRING_AGG(wte.Trait, ',')
         FROM WritingTraitExclusion wte
         WHERE wte.ActiveFlag = 1
           AND wte.GradeCode      = sg.Grade
           AND wte.ProgramFamily  = dp.ProgramFamily
           AND wte.BenchmarkMonth = COALESCE(wed.BenchmarkMonth, MONTH(wed.StartDate))) AS ExcludedTraits
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN DimStudent ds ON ds.StudentKey = sg.StudentKey AND ds.IsCurrent = 1
    LEFT JOIN DimProgram dp ON dp.ProgramCode = ds.ProgramCode
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentNumber      = sg.StudentNumber
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END
          AND ipp.IsCurrent     = 1
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO

/* ============================ tvf_UserAssessmentWindows ============================ */
/*******************************************************************************
 * Function: tvf_UserAssessmentWindows  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_UserAssessmentWindows for the
 *          web app (Phase 3b). The web app connects as the StudentDataAssessment
 *          service principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped views return nothing. This iTVF takes the signed-in
 *          user's UPN and runs the SAME role-branched logic (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst), so admins/analysts
 *          get their full multi-school scope (coverage when a teacher is out).
 * Created: 2026-06-22
 * Modified: 2026-09-18 — +CycleGroupID/CycleName so /enter collapses a cycle's instances into ONE
 *          card per subject. Applied the instance's PROGRAM SCOPE (it was selected but never
 *          filtered on, so an English-scope and an Early-Immersion-scope instance both counted the
 *          SAME students and the collapsed card's total came out double), and course-scoped the
 *          teacher branch to agree with the course-scoped group picker.
 *          2026-09-22 — COURSE-SCOPED the ADMIN + ANALYST branches too (2026-09-18 did only the
 *          teacher branch). They counted straight off DimStudent by grade+scope, so an oversight
 *          user's /enter card overcounted (students with no literacy section) and mis-read as
 *          English-only. Now they resolve through mapped-course sections, language-matched to the
 *          instance, exactly like tvf_TeacherGroups — the card equals the sum of the group cards for
 *          every role. Also changed EnteredStudentCount to "a result on ANY instance of the cycle"
 *          (CycleEntered) so a result on a sibling-language window still counts (matches the picker).
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an inline TVF (not a proc): reads should be QUERYABLE -- the app does
 *   SELECT ... FROM dbo.tvf_UserAssessmentWindows(@UPN) [WHERE/ORDER BY ...]
 * keeping the role logic in one place in SQL while staying composable. Inline
 * TVFs are expanded into the calling query by the optimizer (view-like perf).
 * Reads = iTVFs; writes stay stored procs (they INSERT/UPDATE + audit).
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (same
 * boundary as the @UPN write procs). Never expose with a client-supplied UPN.
 * Mirrors vw_UserAssessmentWindows (CURRENT_USER -> @UPN); keep in sync until the
 * Power App is retired. ORDER BY is intentionally omitted (the caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_UserAssessmentWindows;
GO

CREATE FUNCTION dbo.tvf_UserAssessmentWindows(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)         AS Today,
               CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0))  AS NowTs
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
            w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage, w.ScaleSystem,
            w.CycleGroupID,
            sc.DisplayName AS CycleName,   -- the HEADER's name ("SCoR 1"); the collapsed card's title
            -- Grace-lock (0.7.0): a window stays EDITABLE through EndDate + the cycle's GraceHours
            -- (default 168h), counted from the close moment (midnight after EndDate, Atlantic). Past
            -- that it is Locked (read-only). GraceEndsAt is surfaced so the card can count down "N left".
            DATEADD(HOUR, COALESCE(sc.GraceHours, 168), CAST(DATEADD(DAY, 1, w.EndDate) AS DATETIME2(0))) AS GraceEndsAt,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
            CASE WHEN at.Today  < w.StartDate THEN 'Upcoming'
                 WHEN at.Today  < w.EndDate   THEN 'Open'
                 WHEN at.Today  = w.EndDate   THEN 'ClosesToday'
                 WHEN at.NowTs <= DATEADD(HOUR, COALESCE(sc.GraceHours, 168), CAST(DATEADD(DAY, 1, w.EndDate) AS DATETIME2(0))) THEN 'Closed'
                 ELSE 'Locked' END AS WindowStatus
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
        WHERE w.ActiveFlag = 1
    ),
    TeacherStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.Grade
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        -- The section's COURSE has to be one we assess for this subject, and in the instance's
        -- language. Without this a teacher whose only literacy course is ELA still got a French
        -- Reading card (their immersion students matched it by program), which then opened an empty
        -- group picker -- the picker is course-scoped and this count has to agree with it.
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        -- Teacher route: plain teachers AND SpecialistTeacher (2026-10-13 — specialists enter only the
        -- sections they teach, so they need this route now that the oversight route excludes them).
        WHERE (c.AccessLevel IS NULL OR c.AccessLevel = 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Oversight (Administrator / RegionalAnalyst; NOT SpecialistTeacher) — COURSE-SCOPED and
    -- SCHOOL-SCOPED: only students in MAPPED-COURSE sections (ELA/FLA/Math) in the schools the caller
    -- covers via StaffSchoolAccess (= their CanChangeSchool buildings), language-matched to the
    -- instance. RegionalAnalyst is gated the SAME way — NO region-wide branch; a region-wide analyst
    -- simply has every building in their list. Mirrors tvf_TeacherGroups' Oversight path.
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.Grade
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    ApplicableStudents AS (
        SELECT * FROM TeacherStudents
        UNION ALL SELECT * FROM AdminStudents
    ),
    -- "Entered" = a result on ANY instance of the same cycle+subject, not just this one window. A
    -- student's result can sit on a sibling-language instance (e.g. immersion reading entered on the
    -- English window before the French instance existed); the collapsed /enter card and the group
    -- picker both treat that as entered, so this must too. Keyed by CycleGroupID + AssessmentType.
    CycleEntered AS (
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentNumber
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentReading f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Reading' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentNumber
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentWriting f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Writing' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        -- Math (added 2026-09-23): a student counts as entered once they have ANY task result -
        -- FactAssessmentMath is one row per (student x task), so DISTINCT StudentNumber gives "has begun",
        -- the same "has a result" meaning used for Reading/Writing. Without this, Math cards read 0.
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentNumber
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentMath f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Math' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
    ),
    -- Math COMPLETION ("done", 0.6.4): a Math student is "done" when they have a latest result for
    -- MORE THAN 80% of the tasks applicable to their grade at the window's benchmark month (DimMathTask
    -- by GradeCode + AssessmentMonth). Reading/Writing have a single result, so done == entered and
    -- these CTEs stay empty for them (MathBench is @AssessmentType-guarded to Math windows).
    MathBench AS (   -- effective benchmark month per Math window (BenchmarkMonth, else dominant calendar month)
        SELECT wed.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN wed.StartDate AND wed.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM WindowEffectiveDates wed
        INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = wed.AssessmentWindowID
        WHERE wed.AssessmentType = 'Math'
    ),
    MathApplicable AS (   -- # active tasks for a (window, grade) at that window's benchmark month
        SELECT mb.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ApplicableTasks
        FROM MathBench mb
        INNER JOIN DimMathTask mt ON mt.ActiveFlag = 1 AND mt.AssessmentMonth = mb.BenchMonth
        GROUP BY mb.AssessmentWindowID, mt.GradeCode
    ),
    MathEnteredTasks AS (   -- distinct tasks each applicable student has a result for, with their grade
        -- Grade is CARRIED from ApplicableStudents (which already joined DimStudent to grade-band the
        -- student) -- no re-join. Gated to Math windows (INNER JOIN MathBench) so a Reading/Writing load
        -- pays NOTHING here: MathBench is empty for non-Math windows, pruning the scan before it touches
        -- FactAssessmentMath. (A clear DELETEs its row, so a distinct-task count is a true "has a mark"
        -- count -- no NULL tombstones to over-count.)
        SELECT a.AssessmentWindowID, a.StudentNumber, a.Grade,
               COUNT(DISTINCT fm.MathTaskKey) AS EnteredTasks
        FROM ApplicableStudents a
        INNER JOIN MathBench mb ON mb.AssessmentWindowID = a.AssessmentWindowID
        INNER JOIN FactAssessmentMath fm
                ON fm.StudentNumber = a.StudentNumber AND fm.AssessmentWindowID = a.AssessmentWindowID
        GROUP BY a.AssessmentWindowID, a.StudentNumber, a.Grade
    ),
    MathDone AS (   -- (window, student) over the >80% bar; empty for R/W (MathApplicable empty there)
        SELECT met.AssessmentWindowID, met.StudentNumber
        FROM MathEnteredTasks met
        INNER JOIN MathApplicable ma
                ON ma.AssessmentWindowID = met.AssessmentWindowID AND ma.GradeCode = met.Grade
        WHERE ma.ApplicableTasks > 0
          AND CAST(met.EnteredTasks AS DECIMAL(9,4)) / ma.ApplicableTasks > 0.8
    )
    SELECT
        CAST(wed.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
        wed.WindowName,
        wed.AssessmentType,
        wed.SchoolYear,
        wed.StartDate,
        wed.EndDate,
        wed.MinGrade,
        wed.MaxGrade,
        wed.ProgramFamily,
        wed.ProgramScope,
        wed.AssessmentLanguage,
        wed.ScaleSystem,
        wed.CycleGroupID,   -- lets /enter collapse a cycle's instances into ONE card per subject
        wed.CycleName,      -- header name for that collapsed card (instance names differ per scope)
        wed.WindowStatus,
        wed.GraceEndsAt,    -- when a Closed (in-grace) window flips to Locked; drives the "N left" countdown
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        -- Entered if the student has a result on ANY instance of this cycle+subject (see CycleEntered),
        -- so a result on a sibling-language instance still counts and the card matches the group picker.
        COUNT(DISTINCT CASE WHEN ce.StudentNumber IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount,
        -- Math "done" (0.6.4): >80% of the student's benchmark-month tasks marked. 0 for Reading/Writing.
        COUNT(DISTINCT CASE WHEN mdn.StudentNumber IS NOT NULL THEN a.StudentKey END) AS DoneStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN CycleEntered ce
           ON ce.CycleGroupID   = wed.CycleGroupID
          AND ce.AssessmentType = wed.AssessmentType
          AND ce.StudentNumber  = a.StudentNumber
    LEFT JOIN MathDone mdn
           ON mdn.AssessmentWindowID = a.AssessmentWindowID
          AND mdn.StudentNumber      = a.StudentNumber
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ProgramScope, wed.AssessmentLanguage, wed.ScaleSystem, wed.CycleGroupID, wed.CycleName,
        wed.WindowStatus, wed.GraceEndsAt
);
GO

-- Re-grant here so a standalone redeploy (DROP+CREATE) never leaves the web-app SP without SELECT.
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows] TO [StudentDataAssessment];
GO

/* ============================ tvf_TeacherGroups ============================ */
/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: Choose-a-group resolution for Data Entry, keyed on the CYCLE + SUBJECT
 *          (NOT a single instance). You pick a Cycle, not an instance — a SCoR's
 *          Reading work is ONE card on /enter, and this resolves the sections
 *          behind it across ALL of that cycle's instances of that subject.
 *
 *          Returns one row per SECTION whose course is mapped in
 *          DimCourseAssessment and which is in play for this cycle+subject:
 *            AssessmentType 'Reading'/'Writing' -> Kind 'Literacy'
 *            AssessmentType 'Math'              -> Kind 'Math'
 *            the course's Language must match SOME instance of the cycle (an
 *            instance with AssessmentLanguage NULL admits any language).
 *          A student counts toward a section's card when they satisfy at least one
 *          instance's grade band + program scope — i.e. they'll actually be assessed.
 *
 *          The COURSE supplies the language, so there is no EN/FR toggle: a teacher
 *          of an FLA section enters French, an ELA section enters English. Their
 *          non-literacy/non-math sections (gym, science, homeroom) never appear.
 *
 *          TWO SCOPES (a row can be in both — dual-role; the client toggles):
 *            'Taught'    — sections the caller personally teaches, ANY AccessLevel.
 *            'Oversight' — above-teacher roles see EVERY mapped-course section they
 *                          would normally see: Administrator ->
 *                          their school(s); RegionalAnalyst -> region-wide. (A
 *                          principal sees all ELA/FLA/Math sections in their school.)
 *          TeacherNames says WHOSE class a card is (co-taught sections list all) —
 *          the point of the Oversight cards.
 *
 * Created: 2026-06-22
 * Modified: 2026-09-08 — homeroom GroupKey = stored DimStudent.GroupKey.
 *          2026-09-15 — Taught/Oversight scopes + Homeroom/Section/Grade lenses.
 *          2026-09-18 — COURSE-SCOPED: groups are mapped-course SECTIONS (lenses
 *          retired here; a course section IS the group). +Language/CourseCode/
 *          TeacherNames; GroupType always 'Course'.
 *          2026-09-18b — CYCLE-KEYED: params are now (@CycleGroupID, @AssessmentType)
 *          instead of @AssessmentWindowID, so a collapsed /enter card resolves across
 *          all of the cycle's instances. A card could not key off one instance — a
 *          collapsed "Writing" card pointing at the English instance would show an
 *          FLA teacher nothing.
 *          NOTE: Programming uses its OWN tvf_ProgrammingGroups — unaffected.
 * Modified: 2026-10-13 — SpecialistTeacher REMOVED from the oversight path (user: specialist teachers
 *          ARE teachers -> Data Entry only for the sections they teach, via the FactSectionTeachers
 *          route; they keep whole-school VIEW in Reports and whole-school Programming, which use
 *          other TVFs). Oversight entry = Administrator / RegionalAnalyst only.
 * Region: Canada East (PIIDPA compliant)
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 * NOTE: EnteredStudentCount covers Reading, Writing, AND Math (Math added 2026-09-23; a student is
 *       "entered"/"started" once they have any task result). Deploy the updated TVF to live + dev.
 *       2026-09-24 — +DoneStudentCount (0.6.4): Math COMPLETION = distinct students with a latest
 *       result for >80% of their grade's tasks at the window's benchmark month. 0 for Reading/Writing
 *       (their single result already means done). The Math card shows "N started · M done".
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherGroups;
GO

CREATE FUNCTION dbo.tvf_TeacherGroups
(
    @UPN            VARCHAR(255),
    @CycleGroupID   VARCHAR(36),   -- the SCoR header key
    @AssessmentType VARCHAR(20)    -- 'Reading' | 'Writing' | 'Math'
)
RETURNS TABLE
AS
RETURN
(
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    -- EVERY instance of this cycle for this subject (they differ by language / program scope /
    -- grade band). A section or student only has to match ONE of them to be in play.
    Wins AS (
        SELECT
            w.AssessmentWindowID,
            w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.CycleGroupID   = @CycleGroupID
          AND w.AssessmentType = @AssessmentType
    ),
    -- Sections visible to the caller whose course is mapped for this subject. Kept at section
    -- granularity (DISTINCT) — instance matching happens per-student below.
    VisibleSections AS (
        -- TAUGHT: the caller's own sections, ANY AccessLevel (dual-role fix).
        SELECT DISTINCT
            CAST('Taught' AS VARCHAR(10)) AS Scope,
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Wins win
        INNER JOIN FactSectionTeachers fst
                ON LOWER(fst.TeacherEmail) = c.Email
               AND win.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimSection sec
                ON sec.SectionID = fst.SectionID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        WHERE ((@AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (@AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)

        UNION

        -- OVERSIGHT (Administrator / RegionalAnalyst; NOT SpecialistTeacher): mapped-course sections in
        -- the schools they cover via StaffSchoolAccess.
        SELECT DISTINCT
            CAST('Oversight' AS VARCHAR(10)),
            sec.SectionKey, sec.SectionID, sec.SectionNumber, sec.CourseName, sec.CourseCode,
            ca.Language
        FROM Caller c
        CROSS JOIN Wins win
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
        -- Both oversight roles (Administrator / RegionalAnalyst) are scoped to the
        -- schools in their StaffSchoolAccess (= their CanChangeSchool buildings). NO region-wide
        -- analyst branch; a region-wide analyst simply has every building in their list.
        WHERE c.AccessLevel IN ('Administrator', 'RegionalAnalyst')   -- NOT SpecialistTeacher: entry = own sections only (2026-10-13)
          AND ((@AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
            OR (@AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
          AND (win.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = win.AssessmentLanguage)
    ),
    -- Whose class each section is. CONCAT (never '+') — Fabric trims a literal's space next to a
    -- VARCHAR column. Co-taught sections list every current teacher.
    SectionTeacherNames AS (
        SELECT fst.SectionID, STRING_AGG(CONCAT(d.FirstName, ' ', d.LastName), ', ') AS TeacherNames
        FROM FactSectionTeachers fst
        INNER JOIN DimStaff d ON LOWER(d.Email) = LOWER(fst.TeacherEmail) AND d.IsCurrent = 1
        WHERE fst.IsCurrent = 1
        GROUP BY fst.SectionID
    ),
    -- A student belongs to a section's card if they satisfy AT LEAST ONE instance of the cycle
    -- (that instance's language vs the course, grade band, and program scope). DISTINCT collapses a
    -- student who matches several instances — e.g. a dual-language writer — to ONE per section.
    SectionStudents AS (
        SELECT DISTINCT
            vs.Scope, vs.SectionID, vs.SectionNumber, vs.CourseName, vs.CourseCode, vs.Language,
            win.AssessmentWindowID,   -- WHICH instance this student is assessed under (see SectionWindows)
            s.StudentKey, s.StudentNumber, s.Grade, sch.SchoolName
        FROM VisibleSections vs
        CROSS JOIN Wins win
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = vs.SectionKey
               AND e.StartDate  <= win.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= win.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = win.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = win.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE (win.AssessmentLanguage IS NULL OR vs.Language IS NULL OR vs.Language = win.AssessmentLanguage)
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (win.ProgramFamily IS NULL OR dp.ProgramFamily = win.ProgramFamily)
          -- Cycle PROGRAM-SCOPE buckets (English / Early Immersion / Late Immersion);
          -- delimiter-guarded LIKE, no STRING_SPLIT dependency. NULL scope = all programs.
          AND (win.ProgramScope IS NULL
               OR (',' + win.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Students with an entry already, for ANY instance of this cycle+subject.
    EnteredStudents AS (
        SELECT DISTINCT f.StudentNumber
        FROM Wins win
        INNER JOIN FactAssessmentReading f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Reading'
        UNION
        SELECT DISTINCT f.StudentNumber
        FROM Wins win
        INNER JOIN FactAssessmentWriting f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Writing'
        UNION
        -- Math (added 2026-09-23): entered = has ANY task result (FactAssessmentMath is one row per
        -- student x task). Was the "Math entry count TBD" gap that made Math group cards read 0.
        SELECT DISTINCT f.StudentNumber
        FROM Wins win
        INNER JOIN FactAssessmentMath f ON f.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Math'
    ),
    -- Math COMPLETION ("done") for the card. A Math student is "done" when they have a latest result
    -- for MORE THAN 80% of the tasks applicable to their grade at the cycle's benchmark month
    -- (DimMathTask by GradeCode + AssessmentMonth). Reading/Writing have a single result, so their
    -- "done" == "entered"; these CTEs stay empty for them (MathBench is @AssessmentType-guarded).
    MathBench AS (   -- effective benchmark month per Math window (BenchmarkMonth, else dominant calendar month)
        SELECT win.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN win.WindowStartDate AND win.WindowEndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM Wins win
        INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = win.AssessmentWindowID
        WHERE @AssessmentType = 'Math'
    ),
    MathApplicable AS (   -- # active tasks for a (window, grade) at that window's benchmark month
        SELECT mb.AssessmentWindowID, mt.GradeCode, COUNT(*) AS ApplicableTasks
        FROM MathBench mb
        INNER JOIN DimMathTask mt ON mt.ActiveFlag = 1 AND mt.AssessmentMonth = mb.BenchMonth
        GROUP BY mb.AssessmentWindowID, mt.GradeCode
    ),
    MathStudentWindow AS (   -- (student, window, grade) triples in play, de-duped
        SELECT DISTINCT StudentKey, StudentNumber, AssessmentWindowID, Grade FROM SectionStudents
    ),
    MathEnteredTasks AS (   -- distinct tasks each student has a result for, per window
        -- Gated to Math windows (INNER JOIN MathBench, itself @AssessmentType='Math'-guarded) so a
        -- Reading/Writing picker pays NOTHING here -- MathBench is empty then, pruning this scan.
        SELECT msw.StudentNumber, msw.AssessmentWindowID, COUNT(DISTINCT fm.MathTaskKey) AS EnteredTasks
        FROM MathStudentWindow msw
        INNER JOIN MathBench mb ON mb.AssessmentWindowID = msw.AssessmentWindowID
        INNER JOIN FactAssessmentMath fm
                ON fm.StudentNumber = msw.StudentNumber AND fm.AssessmentWindowID = msw.AssessmentWindowID
        GROUP BY msw.StudentNumber, msw.AssessmentWindowID
    ),
    MathDone AS (   -- students over the >80% bar (empty for R/W since MathApplicable is empty there)
        SELECT DISTINCT msw.StudentNumber
        FROM MathStudentWindow msw
        INNER JOIN MathApplicable ma
                ON ma.AssessmentWindowID = msw.AssessmentWindowID AND ma.GradeCode = msw.Grade
        INNER JOIN MathEnteredTasks me
                ON me.StudentNumber = msw.StudentNumber AND me.AssessmentWindowID = msw.AssessmentWindowID
        WHERE ma.ApplicableTasks > 0
          AND CAST(me.EnteredTasks AS DECIMAL(9,4)) / ma.ApplicableTasks > 0.8
    ),
    -- The cycle instance(s) this section's students actually fall under. Normally exactly ONE (the
    -- course's language pins it), but a cycle can be configured so one section straddles two — e.g. an
    -- English instance split by program scope. The roster step needs the list to route a save to the
    -- right window per student, so carry it rather than guessing downstream.
    SectionWindows AS (
        SELECT Scope, SectionID, STRING_AGG(CAST(AssessmentWindowID AS VARCHAR(20)), ',') AS WindowIDs
        FROM (SELECT DISTINCT Scope, SectionID, AssessmentWindowID FROM SectionStudents) d
        GROUP BY Scope, SectionID
    ),
    -- Grades PRESENT in each card, comma-delimited, so the client grade filter matches a section if
    -- ANY of its grades is selected (a split class surfaces under each of its grades).
    GroupGrades AS (
        SELECT Scope, SectionID, STRING_AGG(Grade, ',') AS Grades
        FROM (SELECT DISTINCT Scope, SectionID, Grade FROM SectionStudents WHERE Grade IS NOT NULL) d
        GROUP BY Scope, SectionID
    )
    SELECT
        ss.Scope,
        CAST('Course' AS VARCHAR(10)) AS GroupType,   -- every entry group is a course section
        'SEC:' + ss.SectionID         AS GroupKey,
        CASE WHEN MAX(ss.SectionNumber) IS NULL OR MAX(ss.SectionNumber) = ''
             THEN MAX(ss.CourseName)
             ELSE CONCAT(MAX(ss.CourseName), ' ', '(', MAX(ss.SectionNumber), ')') END AS GroupLabel,
        MAX(ss.Language)      AS Language,     -- drives the client's language headings + multi-select gate
        MAX(ss.CourseCode)    AS CourseCode,
        MAX(stn.TeacherNames) AS TeacherNames, -- whose class this is (shown on Oversight cards)
        MAX(ss.SchoolName)    AS SchoolName,
        MAX(ss.Grade)         AS Grade,
        MAX(gg.Grades)        AS Grades,
        MAX(sw.WindowIDs)     AS WindowIDs,   -- cycle instance(s) behind this card; roster routes saves by it
        COUNT(DISTINCT ss.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT es.StudentNumber) AS EnteredStudentCount,   -- "started" (>=1 result) for Math; the single result for R/W
        COUNT(DISTINCT md.StudentNumber) AS DoneStudentCount        -- Math only: >80% of grade's benchmark-month tasks marked (0 for R/W)
    FROM SectionStudents ss
    LEFT JOIN SectionTeacherNames stn ON stn.SectionID = ss.SectionID
    LEFT JOIN EnteredStudents es      ON es.StudentNumber = ss.StudentNumber
    LEFT JOIN MathDone md             ON md.StudentNumber = ss.StudentNumber
    LEFT JOIN GroupGrades gg
           ON gg.Scope     = ss.Scope
          AND gg.SectionID = ss.SectionID
    LEFT JOIN SectionWindows sw
           ON sw.Scope     = ss.Scope
          AND sw.SectionID = ss.SectionID
    GROUP BY ss.Scope, ss.SectionID
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherGroups] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentAssessmentHistory ============================ */
/*******************************************************************************
 * Function: tvf_StudentAssessmentHistory  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_StudentAssessmentHistory for the
 *          web app (Phase 3b). One row per (student, completed reading
 *          assessment) for students in the signed-in user's scope. Powers the
 *          per-student detail timeline + trend line.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Adds an optional @StudentKey filter the Power App didn't need (it pulled all
 * history and filtered client-side): pass a key to scope to one student for the
 * detail screen, or NULL for the full in-scope history. Same OR-across-EXISTS
 * role branches as vw_StudentAssessmentHistory, CURRENT_USER -> LOWER(@UPN).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only (see
 * tvf_UserAssessmentWindows header). ORDER BY omitted -- caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistory;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentReadingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN crd.StudentKey IS NULL THEN 1
                WHEN crd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleReading,
        CAST(far.ReadingAssessmentID AS VARCHAR(20))            AS ReadingAssessmentID,
        CAST(far.AssessmentWindowID  AS VARCHAR(20))            AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        aw.ScaleSystem,
        far.AssessmentDate,
        drs.LevelCode,
        drs.LevelOrder,
        far.ReadingDelta,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint,
        -- Expected benchmark range for THIS row's window month + the student's family (item 2).
        drb.ExpectedMinLevel                                    AS ExpectedMinLevel,
        drb.ExpectedMaxLevel                                    AS ExpectedMaxLevel,
        -- Prev-June prior-year anchor (same on every row; item 1a) — the client prepends it to the trend.
        sp.StartingLevelCode                                    AS JuneReadingLevel,
        sp.StartingLevelOrder                                   AS JuneReadingLevelOrder
    FROM FactAssessmentReading far
    JOIN DimStudent s ON s.StudentNumber = far.StudentNumber AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = far.AssessmentWindowID
    JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
    -- Expected range for this row's window month (BenchmarkMonth, else the window's dominant month).
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = s.Grade
          AND drb.ProgramFamily   = CASE WHEN s.ProgramCode = 'J020' THEN 'English' ELSE p.ProgramFamily END
          AND drb.AssessmentMonth = COALESCE(aw.BenchmarkMonth,
                 (SELECT TOP 1 dc.Month FROM DimCalendar dc
                  WHERE dc.Date BETWEEN aw.StartDate AND aw.EndDate
                  GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month))
    -- Prev-June anchor by the student's family scale (J020 -> EN_Reading).
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = s.StudentNumber
          AND sp.ScaleSystem   = CASE WHEN s.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                      WHEN p.ProgramFamily = 'English'          THEN 'EN_Reading'
                                      WHEN p.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END
    LEFT JOIN CurrentReadingIPP crd
           ON crd.StudentKey    = s.StudentKey
          AND crd.ProgramFamily = p.ProgramFamily
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
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

-- DROP+CREATE drops object grants; re-grant here so a redeploy is self-contained.
GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistory] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentAssessmentHistoryWriting ============================ */
/*******************************************************************************
 * Function: tvf_StudentAssessmentHistoryWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentAssessmentHistory. One row per
 *          (student, writing assessment) for students in the signed-in user's
 *          scope -- the four trait scores, their average, and the achievement
 *          band that average falls in. Powers the per-student detail timeline /
 *          trend line on the Writing tab. Optional @StudentKey scopes to one.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Band: average -> code by fixed cut scores (3.50 / 2.75 / 1.75), joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistoryWriting;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistoryWriting(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    ),
    WritingRows AS (
        SELECT
            faw.WritingAssessmentID,
            faw.StudentKey,
            faw.StudentNumber,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
            -- denominator (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha): TRY_CAST('-' AS
            -- INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore
        FROM FactAssessmentWriting faw
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        CAST(w.WritingAssessmentID AS VARCHAR(20))              AS WritingAssessmentID,
        CAST(w.AssessmentWindowID  AS VARCHAR(20))              AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        w.AssessmentDate,
        w.IdeasScore,
        w.OrganizationScore,
        w.LanguageScore,
        w.ConventionsScore,
        w.AvgScore,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM WritingRows w
    JOIN DimStudent s ON s.StudentNumber = w.StudentNumber AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistoryWriting] TO [StudentDataAssessment];
GO

/* ============================ tvf_StudentRWMHistory ============================ */
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
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
    ),
    -- The student, with grade (drives the count-as-0 task universe).
    Stu AS (
        -- @StudentKey is the CURRENT key the app holds; resolve the STABLE StudentNumber here so the
        -- fact scans below match results entered under a prior (re-versioned) key too.
        SELECT s.StudentKey, s.StudentNumber, s.Grade
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.StudentKey = CAST(@StudentKey AS BIGINT)
    ),
    -- Count-as-0 universe: active tasks per (grade, unit) at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
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
        WHERE far.StudentNumber = (SELECT StudentNumber FROM Stu)
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
        -- Traits are VARCHAR: count one ONLY when explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
        -- drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
        -- would hard-CAST '-' and error — so gate on the explicit allow-list.
        CROSS APPLY (SELECT CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore) avg4
        WHERE faw.StudentNumber = (SELECT StudentNumber FROM Stu)
    )
    SELECT
        c.CycleDate,
        DATENAME(MONTH, c.CycleDate) + ' ' + CAST(YEAR(c.CycleDate) AS VARCHAR(4)) AS CycleLabel,
        rc.Code               AS ReadingCode,
        wc.Code               AS WritingCode,
        CAST(mc.RollupPct  AS DECIMAL(5,4)) AS MathRollupPct,      -- blanks excluded
        CAST(mcz.RollupPct AS DECIMAL(5,4)) AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS ReadingMeeting,
        CAST(CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS WritingMeeting,
        CAST(CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)  AS MathMeeting,
        (CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END)          AS RWMScore
    FROM Cycles c
    CROSS JOIN Visible v      -- no rows if the student isn't visible to @UPN
    CROSS JOIN Stu st
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
                WHERE fm.StudentNumber = (SELECT StudentNumber FROM Stu)
                  AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
                  AND fm.AssessmentDate <= c.CycleEnd
            ) x
            INNER JOIN DimMathTask mt ON mt.MathTaskKey = x.MathTaskKey AND mt.ActiveFlag = 1
            WHERE x.rn = 1
            GROUP BY mt.UnitName
        ) u
    ) mc
    -- math roll-up as-of this cycle, blanks COUNT-AS-0: ones-so-far / configured, over the grade's
    -- full-year unit universe (fully-blank units = 0), averaged.
    OUTER APPLY (
        SELECT AVG(z.UnitAvg) AS RollupPct
        FROM (
            SELECT tu.UnitName,
                   CAST(COALESCE(o.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
            FROM TaskUniverse tu
            LEFT JOIN (
                SELECT mt.UnitName, SUM(CAST(x.Result AS INT)) AS Ones
                FROM (
                    SELECT fm.MathTaskKey, fm.Result,
                           ROW_NUMBER() OVER (PARTITION BY fm.MathTaskKey
                                              ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
                    FROM FactAssessmentMath fm
                    WHERE fm.StudentNumber = (SELECT StudentNumber FROM Stu)
                      AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
                      AND fm.AssessmentDate <= c.CycleEnd
                ) x
                INNER JOIN DimMathTask mt ON mt.MathTaskKey = x.MathTaskKey AND mt.ActiveFlag = 1
                WHERE x.rn = 1
                GROUP BY mt.UnitName
            ) o ON o.UnitName = tu.UnitName
            WHERE tu.GradeCode = st.Grade
        ) z
    ) mcz
);
GO

GRANT SELECT ON [dbo].[tvf_StudentRWMHistory] TO [StudentDataAssessment];
GO
