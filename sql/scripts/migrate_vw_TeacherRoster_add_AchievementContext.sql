/*******************************************************************************
 * Migration: extend vw_TeacherRoster with achievement-level context columns
 * Purpose: scrRosterGrid needs expected level range (for display), expected
 *          min/max LevelOrder (for client-side delta computation against the
 *          pending dropdown selection), ExistingDelta from the stored
 *          assessment, and ReadingIPP context (Subject='Reading' x window's
 *          ProgramFamily).
 *
 *          New columns appended at the end of the SELECT; existing columns
 *          unchanged in order, name, and type. Should be transparent to any
 *          consumer that only reads the original columns.
 *
 * Created: 2026-05-27
 *
 * New columns:
 *   ExistingDelta                  INT NULL        -- from FactAssessmentReading.ReadingDelta
 *   ExpectedMinLevel               VARCHAR(10) NULL  -- from DimReadingBenchmark
 *   ExpectedMaxLevel               VARCHAR(10) NULL
 *   ExpectedMinOrder               INT NULL        -- LevelOrder of ExpectedMinLevel; for Power Fx delta math
 *   ExpectedMaxOrder               INT NULL
 *   ReadingIPPStatus               BIT NULL        -- FactStudentIPP.IsIPP for (student, 'Reading', window.ProgramFamily)
 *   ReadingIPPNeedsConfirmation    BIT NOT NULL    -- 1 when a current FactStudentIPP row exists with IsIPP=NULL; else 0
 *
 * Benchmark lookup uses the "dominant calendar month" rule (most days within
 * the window's [StartDate, EndDate], ties broken by earlier month), computed
 * inline via DimCalendar. Matches what usp_UpsertReadingAssessment does
 * at write time so a row's pre-save view-rendered delta is identical to the
 * post-save FactAssessmentReading.ReadingDelta the proc will compute.
 *
 * IPP join semantics: matches on (StudentKey, Subject='Reading', ProgramFamily)
 * where ProgramFamily is the window's if it's scoped to one, else the student's
 * (handles NULL-window-program case for hypothetical all-program windows).
 *
 * After deploying this migration: Power Apps users MUST remove + re-add the
 * vw_TeacherRoster data source so the connector picks up the new columns
 * (per feedback_powerapps_data_source_refresh memory).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_TeacherRoster;
GO

CREATE VIEW vw_TeacherRoster AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.StartDate AS WindowStartDate,
        w.EndDate   AS WindowEndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        w.ScaleSystem,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- Dominant calendar month per window (most days within [StartDate, EndDate],
-- ties broken by earlier month). Same rule as usp_UpsertReadingAssessment.
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
-- ROLE BRANCH 1: Teacher
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
        s.ProgramCode,
        dp.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
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
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IS NULL
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: SchoolAdmin / SpecialistTeacher
AdminApplicable AS (
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
        s.ProgramCode,
        dp.ProgramFamily
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN StaffSchoolAccess ssa
            ON ssa.StaffKey = c.StaffKey
    INNER JOIN DimStudent s
            ON s.SchoolID = ssa.SchoolID
           AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 3: RegionalAnalyst
AnalystApplicable AS (
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
        s.ProgramCode,
        dp.ProgramFamily
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel = 'RegionalAnalyst'
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
AdminAnalystWithSections AS (
    SELECT
        a.AssessmentWindowID,
        a.StudentKey,
        a.StudentNumber,
        a.FirstName,
        a.LastName,
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
        a.ProgramCode,
        a.ProgramFamily,
        sec.SectionID,
        sec.SectionNumber,
        sec.CourseName
    FROM (
        SELECT * FROM AdminApplicable
        UNION ALL
        SELECT * FROM AnalystApplicable
    ) a
    LEFT JOIN FactEnrollment e
           ON a.GradeOrder >= 10
          AND e.StudentKey  = a.StudentKey
          AND e.StartDate  <= a.WindowEndDate
          AND (e.EndDate IS NULL OR e.EndDate >= a.WindowStartDate)
    LEFT JOIN DimSection sec
           ON sec.SectionKey = e.SectionKey
          AND a.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
),
ApplicableStudents AS (
    SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
           Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily,
           SectionID, SectionNumber, CourseName
    FROM TeacherApplicable
    UNION ALL
    SELECT AssessmentWindowID, StudentKey, StudentNumber, FirstName, LastName,
           Grade, GradeOrder, Homeroom, ProgramCode, ProgramFamily,
           SectionID, SectionNumber, CourseName
    FROM AdminAnalystWithSections
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        StudentNumber,
        FirstName,
        LastName,
        Grade,
        ProgramCode,
        ProgramFamily,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey
    FROM ApplicableStudents
)
SELECT DISTINCT
    CAST(sg.AssessmentWindowID         AS VARCHAR(20)) AS AssessmentWindowID,           -- BIGINT cast to VARCHAR for Power Fx precision
    sg.GroupKey,
    CAST(sg.StudentKey                 AS VARCHAR(20)) AS StudentKey,                   -- BIGINT IDENTITY — cast for Power Apps
    sg.StudentNumber,                                                                    -- 10-digit, within Power Fx safe range
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    -- Existing assessment columns:
    CAST(far.ReadingAssessmentID       AS VARCHAR(20)) AS ExistingReadingAssessmentID,  -- BIGINT IDENTITY — cast for Power Apps
    CAST(far.ReadingScaleID            AS VARCHAR(20)) AS ExistingReadingScaleID,       -- BIGINT IDENTITY — cast for Power Apps
    drs.LevelCode           AS ExistingScaleValue,
    far.AssessmentDate      AS ExistingAssessmentDate,
    far.ReadingDelta        AS ExistingDelta,                                           -- NEW: integer delta from saved assessment
    -- Expected range (from DimReadingBenchmark via dominant-month rule):
    drb.ExpectedMinLevel,                                                                -- NEW
    drb.ExpectedMaxLevel,                                                                -- NEW
    bmin.LevelOrder         AS ExpectedMinOrder,                                         -- NEW: for Power Fx pending-delta computation
    bmax.LevelOrder         AS ExpectedMaxOrder,                                         -- NEW
    -- IPP status for this window's reading context:
    ipp.IsIPP                                                  AS ReadingIPPStatus,     -- NEW: NULL (no row OR unresolved), TRUE (has IPP), FALSE (no IPP)
    CASE WHEN ipp.StudentIPPID IS NOT NULL
              AND ipp.IsIPP IS NULL
         THEN CAST(1 AS BIT)
         ELSE CAST(0 AS BIT)
    END                                                        AS ReadingIPPNeedsConfirmation  -- NEW: 1 when row exists but unresolved
FROM StudentGroups sg
INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
INNER JOIN WindowDominantMonth wdm  ON wdm.AssessmentWindowID = sg.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
-- Benchmark lookup (gives min/max VARCHAR level codes):
LEFT JOIN DimReadingBenchmark drb
       ON drb.ScaleSystem     = wed.ScaleSystem
      AND drb.ProgramFamily   = sg.ProgramFamily
      AND drb.GradeCode       = sg.Grade
      AND drb.AssessmentMonth = wdm.DominantMonth
-- Resolve min/max to LevelOrder (needed for Power Fx delta computation):
LEFT JOIN DimReadingScale bmin
       ON bmin.LevelCode    = drb.ExpectedMinLevel
      AND bmin.ScaleSystem  = wed.ScaleSystem
LEFT JOIN DimReadingScale bmax
       ON bmax.LevelCode    = drb.ExpectedMaxLevel
      AND bmax.ScaleSystem  = wed.ScaleSystem
-- IPP status for the window's reading context. ProgramFamily match uses
-- the window's if scoped, else falls back to the student's (covers
-- hypothetical NULL-program-family all-programs windows; MVP windows are
-- scoped so the COALESCE is a defense-in-depth).
LEFT JOIN FactStudentIPP ipp
       ON ipp.StudentKey    = sg.StudentKey
      AND ipp.Subject       = 'Reading'
      AND ipp.ProgramFamily = COALESCE(wed.ProgramFamily, sg.ProgramFamily)
      AND ipp.IsCurrent     = 1
WHERE sg.GroupKey IS NOT NULL;
GO
