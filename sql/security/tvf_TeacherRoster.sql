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
    WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT
            w.AssessmentWindowID, w.StartDate AS WindowStartDate, w.EndDate AS WindowEndDate,
            w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage, w.BenchmarkMonth,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
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
    -- SECTION-FIRST resolution (2026-09-18). Start from the class asked for; join outward.
    --
    -- Replaces three role branches that each ENUMERATED EVERY STUDENT the caller could possibly see
    -- (an analyst: the whole region, with four dimension joins) and only then narrowed to the one
    -- section. Because @UPN is a parameter Fabric cannot prune the unused branches at plan time, so a
    -- plain teacher paid for the analyst's region-wide scan too. Access is now a PREDICATE on a
    -- handful of sections rather than a pre-built student universe; the rules are unchanged.
    -- ------------------------------------------------------------------------------------------
    RequestedSections AS (
        SELECT sec.SectionKey, sec.SectionID, sec.SchoolID
        FROM DimSection sec
        CROSS JOIN WindowEffectiveDates wed
        WHERE wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
          AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(sec.SectionID) + ',%')
    ),
    AccessibleSections AS (
        SELECT rs.SectionKey, rs.SectionID
        FROM RequestedSections rs
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE c.AccessLevel = 'RegionalAnalyst'              -- region-wide, no further check
           OR (c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
               AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                           WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = rs.SchoolID))
           OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                      WHERE fst.SectionID = rs.SectionID
                        AND LOWER(fst.TeacherEmail) = c.Email
                        AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate
                                                  AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
    ),
    StudentGroups AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, s.Homeroom, sch.SchoolName, s.ProgramCode, dp.ProgramFamily,
            'SEC:' + asec.SectionID AS GroupKey
        FROM AccessibleSections asec
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = asec.SectionKey
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        -- FactEnrollment.StudentKey points at a specific DimStudent version, so no date filter here
        -- (adding one would silently drop students re-versioned mid-window).
        INNER JOIN DimStudent s    ON s.StudentKey   = e.StudentKey
        LEFT  JOIN DimSchool  sch  ON sch.SchoolID   = s.SchoolID
        INNER JOIN DimGrade   dg   ON dg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE dg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track scoped by the CYCLE (reading has no per-request toggle; the cycle IS the
          -- language). NULL = unscoped -> all students, per-student scale (legacy).
          --
          -- STRUCTURAL only: French reading = French Immersion. A French reading assessment on a
          -- non-immersion student is meaningless whatever anyone decides, so it is safe here.
          --
          -- The `AND s.ProgramCode <> 'J020'` that used to sit on this line is GONE (2026-09-18).
          -- "Late immersion reads English" is POLICY, not structure — it follows from French
          -- benchmarks not existing yet, and it is already expressed where it belongs: the cycle's
          -- ProgramScope. J020 sits in the Late Immersion bucket (DimProgram.ScopeBucket), so the
          -- scope match above already excludes it from an Early-Immersion-scoped French instance.
          -- Keeping it here made the TVF silently override the config, meaning a scope change on
          -- /cycles would not do what it says, and it cost a per-row comparison plus a redundant
          -- predicate fed to a planner that has already proved fragile on this query.
          --
          -- CONSEQUENCE: the config is now the single source of truth. A French reading instance
          -- scoped to all programs (NULL) or including Late Immersion WILL include J020 students.
          -- That is the intended behaviour — the admin decides — but it is no longer caught here.
          AND (
                wed.AssessmentLanguage IS NULL
             OR wed.AssessmentLanguage = 'English'
             OR (wed.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion')
              )
    ),
    -- Latest reading entry per (student, window). Multiple dated entries per window are now
    -- allowed (ongoing-assessment model), so the roster shows the MOST RECENT one -- without this
    -- rn=1 pick the join would fan a student out to one grid row per entry date.
    LatestReadingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta, AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
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
        far.ReadingDelta     AS ExistingDelta,
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
        dal.AchievementLevelCode AS AchievementLevel,
        dal.AchievementLevelName AS AchievementLevelName,
        dal.HexColor             AS AchievementHexColor,
        dal.HexColorTint         AS AchievementHexColorTint,
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
          AND far.StudentKey         = sg.StudentKey
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
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = sg.StudentNumber
          AND sp.ScaleSystem   = COALESCE(wed.ScaleSystem,
                                     CASE WHEN sg.ProgramCode  = 'J020'             THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'English'          THEN 'EN_Reading'
                                          WHEN sg.ProgramFamily = 'French Immersion' THEN 'FR_Reading' END)
    LEFT JOIN ReadingCycleRank lastR ON lastR.StudentNumber = sg.StudentNumber AND lastR.rn = 1
    LEFT JOIN ReadingCycleRank prevR ON prevR.StudentNumber = sg.StudentNumber AND prevR.rn = 2
    -- Match ANY key in the delimited list. Same guarded-LIKE trick as the program-scope match, so
    -- there's no STRING_SPLIT dependency. Group keys contain ':' and '-' but never ',', so the
    -- delimiter is unambiguous.
    -- No group-key filter here any more: RequestedSections already matched @GroupKeys and
    -- AccessibleSections already checked permission, so every row reaching this point is wanted.
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO
