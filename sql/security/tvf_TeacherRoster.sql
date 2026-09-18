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
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily, sec.SectionID
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
               AND e.StartDate  <= wed.WindowEndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track scoped by the CYCLE (reading has no per-request toggle; the cycle IS the
          -- language). NULL = unscoped -> all students, per-student scale (legacy). Structural rule:
          -- French reading = French Immersion, minus J020 (late immersion reads English, no FR bench).
          -- English reading = open to all programs; grade/program scope comes from the cycle config.
          AND (
                wed.AssessmentLanguage IS NULL
             OR wed.AssessmentLanguage = 'English'
             OR (wed.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion' AND s.ProgramCode <> 'J020')
              )
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimStudent s
                ON s.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track scoped by the CYCLE (reading has no per-request toggle; the cycle IS the
          -- language). NULL = unscoped -> all students, per-student scale (legacy). Structural rule:
          -- French reading = French Immersion, minus J020 (late immersion reads English, no FR bench).
          -- English reading = open to all programs; grade/program scope comes from the cycle config.
          AND (
                wed.AssessmentLanguage IS NULL
             OR wed.AssessmentLanguage = 'English'
             OR (wed.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion' AND s.ProgramCode <> 'J020')
              )

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.StudentNumber, s.FirstName, s.LastName,
            s.Grade, sg.GradeOrder, s.Homeroom, s.GroupKey AS HomeroomKey, sch.SchoolName, s.SchoolID,
            s.ProgramCode, dp.ProgramFamily
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN DimStudent s
                ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel = 'RegionalAnalyst'
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          -- Cycle PROGRAM-SCOPE: the student's bucket (DimProgram.ScopeBucket: English / Early
          -- Immersion / Late Immersion) must be in the cycle's comma-delimited set. NULL = all
          -- programs. Delimiter-guarded LIKE (no STRING_SPLIT dependency).
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
          -- Language track scoped by the CYCLE (reading has no per-request toggle; the cycle IS the
          -- language). NULL = unscoped -> all students, per-student scale (legacy). Structural rule:
          -- French reading = French Immersion, minus J020 (late immersion reads English, no FR bench).
          -- English reading = open to all programs; grade/program scope comes from the cycle config.
          AND (
                wed.AssessmentLanguage IS NULL
             OR wed.AssessmentLanguage = 'English'
             OR (wed.AssessmentLanguage = 'French' AND dp.ProgramFamily = 'French Immersion' AND s.ProgramCode <> 'J020')
              )
    ),
    AdminAnalystWithSections AS (
        SELECT
            a.AssessmentWindowID, a.StudentKey, a.StudentNumber, a.FirstName, a.LastName,
            a.Grade, a.GradeOrder, a.Homeroom, a.HomeroomKey, a.SchoolName, a.SchoolID, a.ProgramCode, a.ProgramFamily, sec.SectionID
        FROM AdminAnalystApplicable a
        -- Section context for ALL grades (was gated to 10+). An oversight user opening a Primary
        -- course section needs its students to carry a SectionID, or the 'SEC:' candidate below
        -- never fires for them. Fans a student out to one row per enrollment; the StudentGroups
        -- UNION + the final SELECT DISTINCT collapse it.
        LEFT JOIN FactEnrollment e
               ON e.StudentKey  = a.StudentKey
              AND e.StartDate  <= a.WindowEndDate
              AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
        LEFT JOIN DimSection sec
               ON sec.SectionKey = e.SectionKey
              AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
              -- Only the REQUESTED sections. Without this the join fans every in-scope student out to
              -- one row per course enrolment (it used to be capped at grade 10+), which blew the plan
              -- up to Msg 8623 "could not produce a query plan".
              AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(sec.SectionID) + ',%')
    ),
    ApplicableStudents AS (
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SchoolID, ProgramCode, ProgramFamily, SectionID
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
               Grade, GradeOrder, Homeroom, HomeroomKey, SchoolName, SchoolID, ProgramCode, ProgramFamily, SectionID
        FROM AdminAnalystWithSections
    ),
    -- A student is resolvable by EITHER their homeroom key OR (HS) a section key. The shared
    -- oversight picker offers a Homeroom lens (a homeroom card for EVERY grade, P-RG) and a
    -- Section lens (HS -> section card), so both keys must resolve to the same student. Emit one
    -- candidate row per key; only the row whose key equals @GroupKey survives the final WHERE, and
    -- SELECT DISTINCT collapses the fan-out. (Was a single CASE that gave HS students a section key
    -- only, so an HS homeroom card resolved to an empty roster.)
    StudentGroups AS (
        -- Homeroom candidate (any grade that carries a stored homeroom key)
        -- Each branch filters on @GroupKeys ITSELF rather than leaving it all to the final WHERE.
        -- Hand-written predicate pushdown: the branches that can't match the requested keys collapse
        -- to nothing instead of materialising every candidate for every student first. This is what
        -- keeps the plan inside the optimizer's budget (see Msg 8623 above).
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramCode, ProgramFamily,
            Homeroom, SchoolName, HomeroomKey AS GroupKey
        FROM ApplicableStudents
        WHERE HomeroomKey IS NOT NULL
          AND (',' + @GroupKeys + ',') LIKE ('%,' + RTRIM(HomeroomKey) + ',%')

        UNION ALL

        -- Section candidate — EVERY grade, not just 10+. Data Entry is course-scoped now: the picker
        -- hands out 'SEC:<id>' for a Primary FLA section just as much as a grade-11 one. The old
        -- GradeOrder >= 10 gate dated from when a section meant a HIGH SCHOOL section, and left every
        -- elementary/junior course card resolving to an EMPTY roster.
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramCode, ProgramFamily,
            Homeroom, SchoolName, 'SEC:' + SectionID AS GroupKey
        FROM ApplicableStudents
        WHERE SectionID IS NOT NULL
          AND (',' + @GroupKeys + ',') LIKE ('%,SEC:' + RTRIM(SectionID) + ',%')

        UNION ALL

        -- Grade-cohort candidate (oversight Grade lens: all students of a school + grade)
        SELECT
            AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName, Grade, ProgramCode, ProgramFamily,
            Homeroom, SchoolName, 'GRADE:' + SchoolID + ':' + Grade AS GroupKey
        FROM ApplicableStudents
        WHERE SchoolID IS NOT NULL
          AND (',' + @GroupKeys + ',') LIKE ('%,GRADE:' + RTRIM(SchoolID) + ':' + RTRIM(Grade) + ',%')
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
    WHERE (',' + @GroupKeys + ',') LIKE ('%,' + RTRIM(sg.GroupKey) + ',%')
);
GO

-- DROP+CREATE above drops object-level grants. Re-grant here so a redeploy of this
-- file is self-contained (the web-app SP reads this TVF as SELECT ... FROM dbo.tvf_X(...)).
GRANT SELECT ON [dbo].[tvf_TeacherRoster] TO [StudentDataAssessment];
GO
