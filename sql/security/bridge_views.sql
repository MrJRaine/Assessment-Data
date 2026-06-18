/*******************************************************************************
 * Bridge Views — SharePoint entry-layer pivot (docs/sharepoint-entry-pivot.md)
 * Purpose: warehouse-side sources for the Fabric bridge that maintains the
 *          SharePoint lists serving the $0-license Teacher Entry / Admin apps.
 *          The caller-scoped RLS views (vw_TeacherRoster, vw_StudentCohort,
 *          vw_StudentAssessmentHistory) filter by CURRENT_USER and therefore
 *          return NOTHING to a service identity — these views return ALL rows
 *          with the scoping key (TeacherEmail / SchoolID) as a COLUMN, so the
 *          bridge can partition rows into list items.
 *
 * Created: 2026-06-12
 * Region: Canada East (PIIDPA compliant)
 *
 * *** SECURITY — READ BEFORE GRANTING ANYTHING ***
 *   These views bypass row-level security BY DESIGN. They must NEVER be:
 *     - added as a Power Apps data source,
 *     - granted to any teacher/admin/analyst login or role.
 *   No GRANTs are issued here: only workspace principals (the bridge job's
 *   identity) can read them. If a dedicated bridge identity is created later,
 *   GRANT SELECT on exactly these five views to it and nothing else.
 *
 * Views:
 *   1. vw_BridgeTeacherRosterAll  — (window x teacher x group x student) for ALL
 *      current teachers; feeds the RosterEntry list (teacher app). Mirrors
 *      vw_TeacherRoster's teacher branch + achievement-context tail.
 *   2. vw_BridgeSchoolRosterAll   — (window x school x group x student) for ALL
 *      students in window scope; feeds the admin read-only roster slices.
 *   3. vw_BridgeStudentCohortAll  — vw_StudentCohort minus the RLS gate, plus
 *      SchoolID kept for partitioning; feeds the admin cohort list.
 *   4. vw_BridgeAssessmentHistoryAll — vw_StudentAssessmentHistory minus the
 *      RLS gate; feeds the admin history list (per-student on-demand loads).
 *   5. vw_BridgeScaleLevels       — DimReadingScale wrapper; feeds ScaleLevels.
 *
 * Conventions carried over from the caller-scoped views (keep in sync):
 *   - Historical-roster reconciliation: window EffectiveDate = min(today
 *     Atlantic, window EndDate); enrollment overlap test on window dates.
 *   - Group resolution: GradeOrder <= 9 -> 'HR:' + Homeroom; >= 10 -> 'SEC:'
 *     + SectionID (senior students one group per section).
 *   - Dominant-month benchmark rule identical to usp_UpsertReadingAssessment.
 *   - BIGINT surrogate keys CAST to VARCHAR(20) (list columns are text; keeps
 *     values identical to what the old SQL-bound app rendered).
 *   - WindowStatus derived Atlantic-aware: Upcoming/Open/ClosesToday/Closed.
 ******************************************************************************/

-- ============================================================================
-- 1. vw_BridgeTeacherRosterAll
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeTeacherRosterAll;
GO

CREATE VIEW vw_BridgeTeacherRosterAll AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.SchoolYear,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
WindowDominantMonth AS (
    SELECT
        wed.AssessmentWindowID,
        (SELECT TOP 1 dc.Month
         FROM DimCalendar dc
         WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
         GROUP BY dc.Month
         ORDER BY COUNT(*) DESC, dc.Month) AS DominantMonth
    FROM WindowEffectiveDates wed
),
-- All (teacher, window, student) tuples — vw_TeacherRoster's teacher branch
-- with the Caller filter removed and TeacherEmail carried as a column.
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        LOWER(fst.TeacherEmail) AS TeacherEmail,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.SchoolID,
        s.ProgramCode,
        dp.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM WindowEffectiveDates wed
    INNER JOIN FactSectionTeachers fst
            ON wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimSection sec
            ON sec.SectionID = fst.SectionID
           AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    INNER JOIN FactEnrollment e
            ON e.SectionKey  = sec.SectionKey
           AND e.StartDate  <= wed.WindowEndDate
           AND (e.EndDate IS NULL OR e.EndDate >= wed.WindowStartDate)
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        TeacherEmail,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        SchoolID,
        ProgramCode,
        ProgramFamily,
        SectionNumber,
        CourseName,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM TeacherApplicable
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID AS VARCHAR(20))          AS AssessmentWindowID,
    wed.WindowName,
    wed.SchoolYear,
    wed.WindowStatus,
    wed.ScaleSystem,
    sg.TeacherEmail,
    sg.GroupKey,
    sg.SectionNumber,
    sg.CourseName,
    CAST(sg.StudentKey AS VARCHAR(20))                  AS StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.SchoolID,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))        AS ExistingReadingAssessmentID,
    CAST(far.ReadingScaleID      AS VARCHAR(20))        AS ExistingReadingScaleID,
    drs.LevelCode                                        AS ExistingScaleValue,
    far.AssessmentDate                                   AS ExistingAssessmentDate,
    far.ReadingDelta                                     AS ExistingDelta,
    drb.ExpectedMinLevel,
    drb.ExpectedMaxLevel,
    bmin.LevelOrder                                      AS ExpectedMinOrder,
    bmax.LevelOrder                                      AS ExpectedMaxOrder,
    ipp.IsIPP                                            AS ReadingIPPStatus,
    CASE WHEN ipp.StudentIPPID IS NOT NULL
              AND ipp.IsIPP IS NULL
         THEN CAST(1 AS BIT)
         ELSE CAST(0 AS BIT)
    END                                                  AS ReadingIPPNeedsConfirmation
FROM StudentGroups sg
INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN DimReadingBenchmark drb
       ON drb.ScaleSystem     = wed.ScaleSystem
      AND drb.ProgramFamily   = sg.ProgramFamily
      AND drb.GradeCode       = sg.Grade
      AND drb.AssessmentMonth = wdm.DominantMonth
LEFT JOIN DimReadingScale bmin
       ON bmin.LevelCode    = drb.ExpectedMinLevel
      AND bmin.ScaleSystem  = wed.ScaleSystem
LEFT JOIN DimReadingScale bmax
       ON bmax.LevelCode    = drb.ExpectedMaxLevel
      AND bmax.ScaleSystem  = wed.ScaleSystem
LEFT JOIN FactStudentIPP ipp
       ON ipp.StudentKey    = sg.StudentKey
      AND ipp.Subject       = 'Reading'
      AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
      AND ipp.IsCurrent     = 1
WHERE sg.GroupKey IS NOT NULL;
GO

-- ============================================================================
-- 2. vw_BridgeSchoolRosterAll
--    One row per (window x school x group x student) for ALL students in each
--    window's grade/program scope — the admin monitoring surface. Equivalent
--    of the analyst branch with SchoolID as the partition key.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeSchoolRosterAll;
GO

CREATE VIEW vw_BridgeSchoolRosterAll AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.SchoolYear,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
WindowDominantMonth AS (
    SELECT
        wed.AssessmentWindowID,
        (SELECT TOP 1 dc.Month
         FROM DimCalendar dc
         WHERE dc.Date BETWEEN wed.WindowStartDate AND wed.WindowEndDate
         GROUP BY dc.Month
         ORDER BY COUNT(*) DESC, dc.Month) AS DominantMonth
    FROM WindowEffectiveDates wed
),
AllApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.SchoolID,
        s.ProgramCode,
        dp.ProgramFamily
    FROM WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- Senior section context for group resolution (GradeOrder >= 10 only)
WithSections AS (
    SELECT
        a.AssessmentWindowID,
        a.StudentKey,
        a.StudentNumber,
        a.FirstName,
        a.LastName,
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
        a.SchoolID,
        a.ProgramCode,
        a.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM AllApplicable a
    LEFT JOIN FactEnrollment e
           ON a.GradeOrder >= 10
          AND e.StudentKey  = a.StudentKey
          AND e.StartDate  <= a.WindowEndDate
          AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
    LEFT JOIN DimSection sec
           ON sec.SectionKey = e.SectionKey
          AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        SchoolID,
        ProgramCode,
        ProgramFamily,
        SectionNumber,
        CourseName,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM WithSections
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID AS VARCHAR(20))          AS AssessmentWindowID,
    wed.WindowName,
    wed.SchoolYear,
    wed.WindowStatus,
    wed.ScaleSystem,
    sg.SchoolID,
    sg.GroupKey,
    sg.SectionNumber,
    sg.CourseName,
    CAST(sg.StudentKey AS VARCHAR(20))                  AS StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))        AS ExistingReadingAssessmentID,
    CAST(far.ReadingScaleID      AS VARCHAR(20))        AS ExistingReadingScaleID,
    drs.LevelCode                                        AS ExistingScaleValue,
    far.AssessmentDate                                   AS ExistingAssessmentDate,
    far.ReadingDelta                                     AS ExistingDelta,
    drb.ExpectedMinLevel,
    drb.ExpectedMaxLevel,
    bmin.LevelOrder                                      AS ExpectedMinOrder,
    bmax.LevelOrder                                      AS ExpectedMaxOrder,
    ipp.IsIPP                                            AS ReadingIPPStatus,
    CASE WHEN ipp.StudentIPPID IS NOT NULL
              AND ipp.IsIPP IS NULL
         THEN CAST(1 AS BIT)
         ELSE CAST(0 AS BIT)
    END                                                  AS ReadingIPPNeedsConfirmation
FROM StudentGroups sg
INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN DimReadingBenchmark drb
       ON drb.ScaleSystem     = wed.ScaleSystem
      AND drb.ProgramFamily   = sg.ProgramFamily
      AND drb.GradeCode       = sg.Grade
      AND drb.AssessmentMonth = wdm.DominantMonth
LEFT JOIN DimReadingScale bmin
       ON bmin.LevelCode    = drb.ExpectedMinLevel
      AND bmin.ScaleSystem  = wed.ScaleSystem
LEFT JOIN DimReadingScale bmax
       ON bmax.LevelCode    = drb.ExpectedMaxLevel
      AND bmax.ScaleSystem  = wed.ScaleSystem
LEFT JOIN FactStudentIPP ipp
       ON ipp.StudentKey    = sg.StudentKey
      AND ipp.Subject       = 'Reading'
      AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
      AND ipp.IsCurrent     = 1
WHERE sg.GroupKey IS NOT NULL;
GO

-- ============================================================================
-- 3. vw_BridgeStudentCohortAll — vw_StudentCohort minus the RLS gate.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeStudentCohortAll;
GO

CREATE VIEW vw_BridgeStudentCohortAll AS
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
),
CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    sg.GradeOrder,
    s.SchoolID,
    sch.SchoolName,
    sch.Abbreviation                                         AS SchoolAbbreviation,
    s.ProgramCode,
    p.ProgramFamily,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP                                                    AS IPP_PSFlag,
    s.Adap,
    s.Homeroom,
    crd.IsIPP                                                AS IsIPP_Reading,
    CASE
        WHEN crd.StudentKey IS NULL          THEN 'N/A'
        WHEN crd.IsIPP IS NULL                THEN 'Unresolved'
        WHEN crd.IsIPP = 1                    THEN 'IPP'
        WHEN crd.IsIPP = 0                    THEN 'Not IPP'
    END                                                      AS IPPStatus_Reading,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    CAST(lr.ReadingAssessmentID AS VARCHAR(20))              AS MostRecentReadingAssessmentID,
    CAST(lr.AssessmentWindowID  AS VARCHAR(20))              AS MostRecentAssessmentWindowID,
    aw.WindowName                                            AS MostRecentWindowName,
    aw.SchoolYear                                            AS MostRecentSchoolYear,
    lr.AssessmentDate                                        AS MostRecentAssessmentDate,
    CAST(lr.ReadingScaleID      AS VARCHAR(20))              AS MostRecentReadingScaleID,
    drs.LevelCode                                            AS MostRecentLevelCode,
    drs.LevelOrder                                           AS MostRecentLevelOrder,
    lr.ReadingDelta                                          AS MostRecentReadingDelta,
    dal.AchievementLevelCode                                 AS MostRecentAchievementLevelCode,
    dal.AchievementLevelName                                 AS MostRecentAchievementLevelName,
    dal.HexColor                                             AS MostRecentAchievementHexColor,
    dal.HexColorTint                                         AS MostRecentAchievementHexColorTint
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimGrade sg
    ON sg.GradeCode  = s.Grade
LEFT JOIN DimSchool sch
    ON sch.SchoolID = s.SchoolID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN LatestReading lr
    ON  lr.StudentKey = s.StudentKey
    AND lr.rn         = 1
LEFT JOIN DimAssessmentWindow aw
    ON  aw.AssessmentWindowID = lr.AssessmentWindowID
LEFT JOIN DimReadingScale drs
    ON  drs.ReadingScaleID = lr.ReadingScaleID
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND lr.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound)
        )
WHERE s.IsCurrent     = 1
  AND s.EnrollStatus IN (0, -1);
GO

-- ============================================================================
-- 4. vw_BridgeAssessmentHistoryAll — vw_StudentAssessmentHistory minus RLS.
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeAssessmentHistoryAll;
GO

CREATE VIEW vw_BridgeAssessmentHistoryAll AS
WITH CurrentReadingIPP AS (
    SELECT
        fsi.StudentKey,
        fsi.ProgramFamily,
        fsi.IsIPP
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND fsi.Subject   = 'Reading'
)
SELECT
    CAST(s.StudentKey         AS VARCHAR(20))               AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.LastName,
    s.FirstName + ' ' + s.LastName                          AS FullName,
    s.Grade,
    s.SchoolID,
    s.ProgramCode,
    p.ProgramFamily                                          AS StudentProgramFamily,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    CAST(far.ReadingAssessmentID AS VARCHAR(20))             AS ReadingAssessmentID,
    CAST(far.AssessmentWindowID  AS VARCHAR(20))             AS AssessmentWindowID,
    aw.WindowName,
    aw.AssessmentType,
    aw.SchoolYear                                            AS WindowSchoolYear,
    aw.StartDate                                             AS WindowStartDate,
    aw.EndDate                                               AS WindowEndDate,
    aw.ProgramFamily                                         AS WindowProgramFamily,
    aw.ScaleSystem,
    far.AssessmentDate,
    CAST(far.ReadingScaleID AS VARCHAR(20))                  AS ReadingScaleID,
    drs.LevelCode,
    drs.LevelOrder,
    far.ReadingDelta,
    dal.AchievementLevelCode,
    dal.AchievementLevelName,
    dal.HexColor                                             AS AchievementHexColor,
    dal.HexColorTint                                         AS AchievementHexColorTint
FROM FactAssessmentReading far
JOIN DimStudent s
    ON  s.StudentKey = far.StudentKey
    AND s.IsCurrent  = 1
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimAssessmentWindow aw
    ON aw.AssessmentWindowID = far.AssessmentWindowID
JOIN DimReadingScale drs
    ON drs.ReadingScaleID = far.ReadingScaleID
LEFT JOIN CurrentReadingIPP crd
    ON  crd.StudentKey    = s.StudentKey
    AND crd.ProgramFamily = p.ProgramFamily
LEFT JOIN DimAchievementLevel dal
    ON  dal.ActiveFlag = 1
    AND far.ReadingDelta IS NOT NULL
    AND (
            dal.LowerBound IS NULL
         OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
         OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
         OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound)
        )
    AND (
            dal.UpperBound IS NULL
         OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
         OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
         OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound)
        )
WHERE s.EnrollStatus IN (0, -1);
GO

-- ============================================================================
-- 5. vw_BridgeScaleLevels — DimReadingScale wrapper (BIGINT key cast).
-- ============================================================================
DROP VIEW IF EXISTS vw_BridgeScaleLevels;
GO

CREATE VIEW vw_BridgeScaleLevels AS
SELECT
    CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
    LevelCode,
    LevelOrder,
    ScaleSystem,
    Description,
    ActiveFlag
FROM DimReadingScale;
GO
