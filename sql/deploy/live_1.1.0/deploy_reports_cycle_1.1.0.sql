/*******************************************************************************
 * 1.1.0 LIVE deploy — Reports cycle time-binding fan-out + Math task-month.
 * Run once against Assessment_Warehouse (live). All objects are DROP-IF-EXISTS +
 * CREATE + GRANT, so a re-run is safe. Fixes the 1.1.0 'Couldn't load data' on the
 * cohort reports (the app passes @CycleGroupID; these give the functions that param).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ==================== sql/security/tvf_StudentCohort.sql ====================
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
            far.StudentKey,
            far.ReadingAssessmentID,
            far.AssessmentWindowID,
            far.ReadingScaleID,
            far.ReadingDelta,
            far.AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY far.StudentKey
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
    LEFT JOIN LatestReading lr ON lr.StudentKey = s.StudentKey AND lr.rn = 1
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


-- ==================== sql/security/tvf_StudentCohortWriting.sql ====================
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
            faw.StudentKey,
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
                PARTITION BY faw.StudentKey
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
    LEFT JOIN LatestWriting lw ON lw.StudentKey = s.StudentKey AND lw.rn = 1
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
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND g.GradeOrder BETWEEN 0 AND 6
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
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND sg.GradeOrder BETWEEN 0 AND 6
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


-- ==================== sql/procedures/usp_UpsertShortCycle.sql ====================
/*******************************************************************************
 * Procedure: usp_UpsertShortCycle
 * Purpose: Create or edit a "Short Cycle of Response" — a manually-defined,
 *          REGION-WIDE assessment date range for one subject. Replaces the
 *          auto-generated monthly windows (usp_GenerateMonthlyWindows, retired).
 *          Backing table is still DimAssessmentWindow (internal name kept; only
 *          user-facing labels use "Short Cycle of Response").
 * SCD Type: N/A (DimAssessmentWindow rows are managed manually)
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Model (2026-08-27; app-level scope 2026-09-17):
 *   - A cycle can be SCOPED from the /cycles page along three axes (all optional):
 *       @MinGrade/@MaxGrade  grade band (default whole-population 'PP'..'12'),
 *       @ProgramScope        comma-delimited bucket set {English, Early Immersion, Late Immersion}
 *                            (NULL = all; non-immersion folds into English via DimProgram.ScopeBucket),
 *       @AssessmentLanguage  'English'|'French'|NULL(Both).
 *     e.g. "Immersion grades 3-6, writing, French only" = @ProgramScope='Early Immersion,Late Immersion',
 *     @MinGrade='3', @MaxGrade='6', @AssessmentLanguage='French'. NULL on an axis = no scope
 *     there. A language-scoped READING cycle also fixes ScaleSystem (EN_Reading/FR_Reading).
 *     Membership still follows the track rule (usp_MergeStudent Step 6); the scope narrows it.
 *     The writing RESULT carries its own AssessmentLanguage (storage/backfill/reporting); this
 *     scopes the CYCLE. See project_assessment_language_tracks.
 *   - This proc writes ONE subject-row per call. A multi-subject cycle is several
 *     rows sharing a @CycleGroupID (the app calls this once per selected subject).
 *   - SchoolYear is derived from StartDate (Sep–Aug academic year).
 *
 * Authorization: enforced at the app layer (the Manage-Short-Cycles screen is
 *   RegionalAnalyst-gated, server-side). This proc does input validation only;
 *   @CallerUPN is recorded as CreatedBy for the audit trail. Grant is to the
 *   web-app service principal alone (same boundary as the other write procs).
 *
 * THROW codes (51030–51036, user-fixable per project_submission_validation_strategy):
 *   51030  @AssessmentType not in (Reading, Writing, Math)
 *   51031  @CycleName blank
 *   51032  @EndDate < @StartDate (or a date is NULL)
 *   51033  @MinGrade / @MaxGrade not a valid DimGrade.GradeCode
 *   51034  @MinGrade above @MaxGrade
 *   51035  @BenchmarkMonth not in 1–12
 *   51036  @AssessmentWindowID supplied for edit but not found
 *   51037  @AssessmentLanguage not in ('English','French',NULL)
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_UpsertShortCycle;
GO
CREATE PROCEDURE dbo.usp_UpsertShortCycle
    @AssessmentType     VARCHAR(20),                 -- 'Reading' | 'Writing' | 'Math'
    @CycleName          VARCHAR(100),                -- e.g. 'Cycle 1 – Fall Reading'
    @StartDate          DATE,
    @EndDate            DATE,
    @MinGrade           VARCHAR(10)  = 'PP',         -- whole-population default
    @MaxGrade           VARCHAR(10)  = '12',
    @ProgramScope       VARCHAR(100) = NULL,         -- comma-delimited bucket set from {English, Early Immersion, Late Immersion}; NULL = all. e.g. 'English,Late Immersion'
    @AssessmentLanguage VARCHAR(10)  = NULL,         -- 'English' | 'French' language scope (literacy); NULL = Both (toggle/per-student)
    @BenchmarkMonth     INT          = NULL,         -- 1-12: Reading = benchmark month, Math = task-pull month (DimMathTask.AssessmentMonth); NULL = dominant-month fallback. Writing has none.
    @CycleGroupID       VARCHAR(36)  = NULL,         -- groups the per-subject rows of one multi-subject cycle (app-generated GUID)
    @ActiveFlag         BIT          = 1,            -- 0 to deactivate/hide a cycle
    @AssessmentWindowID BIGINT       = NULL,         -- NULL = create; else edit this cycle
    @CallerUPN          VARCHAR(255) = NULL          -- recorded as CreatedBy (audit)
AS
BEGIN
    SET NOCOUNT ON;

    -- ---- Input validation -------------------------------------------------
    -- (Each THROW is wrapped in BEGIN...END: Fabric rejects a bare ";THROW" as an IF body.)
    IF @AssessmentType NOT IN ('Reading', 'Writing', 'Math')
    BEGIN
        ;THROW 51030, 'usp_UpsertShortCycle: @AssessmentType must be Reading, Writing, or Math.', 1;
    END;

    IF @CycleName IS NULL OR LTRIM(RTRIM(@CycleName)) = ''
    BEGIN
        ;THROW 51031, 'usp_UpsertShortCycle: @CycleName is required.', 1;
    END;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
    BEGIN
        ;THROW 51032, 'usp_UpsertShortCycle: @EndDate must be on or after @StartDate.', 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MinGrade)
       OR NOT EXISTS (SELECT 1 FROM DimGrade WHERE GradeCode = @MaxGrade)
    BEGIN
        ;THROW 51033, 'usp_UpsertShortCycle: @MinGrade/@MaxGrade must be valid DimGrade.GradeCode values.', 1;
    END;

    IF (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MinGrade)
     > (SELECT GradeOrder FROM DimGrade WHERE GradeCode = @MaxGrade)
    BEGIN
        ;THROW 51034, 'usp_UpsertShortCycle: @MinGrade must be at or below @MaxGrade.', 1;
    END;

    IF @BenchmarkMonth IS NOT NULL AND @BenchmarkMonth NOT BETWEEN 1 AND 12
    BEGIN
        ;THROW 51035, 'usp_UpsertShortCycle: @BenchmarkMonth must be 1-12 (or NULL for dominant-month fallback).', 1;
    END;

    IF @AssessmentLanguage IS NOT NULL AND @AssessmentLanguage NOT IN ('English', 'French')
    BEGIN
        ;THROW 51037, 'usp_UpsertShortCycle: @AssessmentLanguage must be ''English'', ''French'', or NULL (Both).', 1;
    END;

    -- @ProgramScope is a comma-delimited bucket set (validated by the /cycles UI; app-gated proc).
    -- Empty string normalises to NULL (= all programs).
    IF @ProgramScope IS NOT NULL AND LTRIM(RTRIM(@ProgramScope)) = '' SET @ProgramScope = NULL;

    -- Benchmark/task month applies to Reading (benchmark month) AND Math (the month whose
    -- DimMathTask rows the roster pulls); ONLY Writing has no month, so null it just for Writing.
    IF @AssessmentType = 'Writing' SET @BenchmarkMonth = NULL;

    -- Language scope is literacy-only; Math is single-track (no language).
    IF @AssessmentType = 'Math' SET @AssessmentLanguage = NULL;

    -- A language-scoped READING cycle fixes the scale; Writing/Math/Both carry no cycle scale.
    DECLARE @ScaleSystem VARCHAR(20) =
        CASE WHEN @AssessmentType = 'Reading' AND @AssessmentLanguage = 'English' THEN 'EN_Reading'
             WHEN @AssessmentType = 'Reading' AND @AssessmentLanguage = 'French'  THEN 'FR_Reading'
             ELSE NULL END;

    -- ---- Derive academic school year from the start date (Sep–Aug) ---------
    DECLARE @Y INT = YEAR(@StartDate), @M INT = MONTH(@StartDate);
    DECLARE @SchoolYear VARCHAR(9) =
        CASE WHEN @M >= 9 THEN CONCAT(@Y, '-', @Y + 1)
                          ELSE CONCAT(@Y - 1, '-', @Y) END;

    DECLARE @Now DATETIME2(0) = GETDATE();

    IF @AssessmentWindowID IS NULL
    BEGIN
        -- ---- CREATE -------------------------------------------------------
        INSERT INTO DimAssessmentWindow (
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage, BenchmarkMonth, CycleGroupID, ActiveFlag,
            CreatedDate, CreatedBy, LastUpdated
        )
        VALUES (
            @CycleName, @AssessmentType, @SchoolYear, @StartDate, @EndDate,
            @MinGrade, @MaxGrade, NULL, @ProgramScope, @ScaleSystem, @AssessmentLanguage, @BenchmarkMonth, @CycleGroupID, @ActiveFlag,
            @Now, @CallerUPN, @Now
        );

        -- No OUTPUT clause in Fabric Warehouse — read the new row back.
        SELECT TOP 1
            CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ActiveFlag
        FROM DimAssessmentWindow
        WHERE WindowName = @CycleName AND AssessmentType = @AssessmentType
          AND StartDate = @StartDate AND EndDate = @EndDate
        ORDER BY AssessmentWindowID DESC;
    END
    ELSE
    BEGIN
        -- ---- EDIT ---------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM DimAssessmentWindow WHERE AssessmentWindowID = @AssessmentWindowID)
        BEGIN
            ;THROW 51036, 'usp_UpsertShortCycle: @AssessmentWindowID not found.', 1;
        END;

        UPDATE DimAssessmentWindow
        SET WindowName     = @CycleName,
            AssessmentType = @AssessmentType,
            SchoolYear     = @SchoolYear,
            StartDate      = @StartDate,
            EndDate        = @EndDate,
            MinGrade       = @MinGrade,
            MaxGrade       = @MaxGrade,
            ProgramFamily  = NULL,               -- legacy single-family column, unused by new cycles
            ProgramScope   = @ProgramScope,      -- bucket set (NULL = all programs)
            ScaleSystem    = @ScaleSystem,       -- reading scale of a language-scoped cycle (else NULL)
            AssessmentLanguage = @AssessmentLanguage,  -- 'English'/'French' scope, or NULL (Both)
            BenchmarkMonth = @BenchmarkMonth,
            CycleGroupID   = @CycleGroupID,
            ActiveFlag     = @ActiveFlag,
            LastUpdated    = @Now
        WHERE AssessmentWindowID = @AssessmentWindowID;

        SELECT
            CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
            WindowName, AssessmentType, SchoolYear, StartDate, EndDate,
            MinGrade, MaxGrade, ActiveFlag
        FROM DimAssessmentWindow
        WHERE AssessmentWindowID = @AssessmentWindowID;
    END
END;
GO

-- Web app connects as the service principal; grant EXECUTE to it alone.
GRANT EXECUTE ON dbo.usp_UpsertShortCycle TO [StudentDataAssessment];
GO

