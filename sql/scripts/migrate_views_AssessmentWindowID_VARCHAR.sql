/*******************************************************************************
 * Migration: cast BIGINT IDENTITY surrogate keys to VARCHAR(20) in the 3
 *            Power-Apps-facing views.
 * Date: 2026-05-21
 * Region: Canada East (PIIDPA compliant)
 *
 * Why: Power Fx Number is IEEE 754 double (53-bit mantissa, 16-digit safe
 *      max). Fabric BIGINT IDENTITY emits ~19-digit values, exceeding that
 *      range. When Power Apps filters `Filter(view, BIGINTKey = scalarBIGINT)`,
 *      the SQL connector serializes the rounded Number back as a parameter and
 *      no rows match. Casting at the view surface keeps both sides as strings
 *      and equality works.
 *
 * Casts in this migration:
 *   vw_UserAssessmentWindows : AssessmentWindowID
 *   vw_TeacherGroups         : AssessmentWindowID
 *   vw_TeacherRoster         : AssessmentWindowID, StudentKey,
 *                              ExistingReadingAssessmentID,
 *                              ExistingReadingScaleID
 *
 * Companion follow-up (NOT in this migration):
 *   - usp_UpsertReadingAssessment: flip @AssessmentWindowID + @ReadingScaleID
 *     to VARCHAR(20) + CAST internally. Do this when wiring scrRosterGrid.
 *   - DimReadingScale wrapper view (vw_DimReadingScale) for cmbNewLevel
 *     dropdown — also when wiring scrRosterGrid.
 *
 * Internal joins are unaffected — only the surface output columns change.
 * See project_powerapps_bigint_precision memory for the full pattern.
 *
 * Idempotent — DROP IF EXISTS + CREATE.
 ******************************************************************************/

DROP VIEW IF EXISTS vw_UserAssessmentWindows;
GO

CREATE VIEW vw_UserAssessmentWindows AS
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
        w.WindowName,
        w.AssessmentType,
        w.SchoolYear,
        w.StartDate,
        w.EndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
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
TeacherStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
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
AdminStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
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
AnalystStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
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
ApplicableStudents AS (
    SELECT * FROM TeacherStudents
    UNION ALL SELECT * FROM AdminStudents
    UNION ALL SELECT * FROM AnalystStudents
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
    wed.WindowStatus,
    COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN a.StudentKey END) AS EnteredStudentCount
FROM WindowEffectiveDates wed
INNER JOIN ApplicableStudents a
        ON a.AssessmentWindowID = wed.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = wed.AssessmentWindowID
      AND far.StudentKey         = a.StudentKey
GROUP BY
    wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
    wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily, wed.WindowStatus;
GO

DROP VIEW IF EXISTS vw_TeacherGroups;
GO

CREATE VIEW vw_TeacherGroups AS
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
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
TeacherApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom,
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
AdminApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom
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
AnalystApplicable AS (
    SELECT
        wed.AssessmentWindowID,
        wed.WindowStartDate,
        wed.WindowEndDate,
        wed.EffectiveDate,
        s.StudentKey,
        s.Grade,
        sg.GradeOrder,
        s.Homeroom
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
        a.Grade,
        a.GradeOrder,
        a.Homeroom,
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
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM TeacherApplicable
    UNION ALL
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM AdminAnalystWithSections
),
StudentGroups AS (
    SELECT
        AssessmentWindowID,
        StudentKey,
        Grade,
        CASE WHEN GradeOrder <= 9  THEN 'HR:'  + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'SEC:' + SectionID
        END AS GroupKey,
        CASE WHEN GradeOrder <= 9  THEN 'Homeroom'
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN 'Section'
        END AS GroupType,
        CASE WHEN GradeOrder <= 9  THEN 'Homeroom ' + COALESCE(Homeroom, '(none)')
             WHEN GradeOrder >= 10 AND SectionID IS NOT NULL THEN SectionNumber + ' — ' + CourseName
        END AS GroupLabel
    FROM ApplicableStudents
)
SELECT
    CAST(sg.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
    sg.GroupKey,
    sg.GroupType,
    sg.GroupLabel,
    MAX(sg.Grade) AS Grade,
    COUNT(DISTINCT sg.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN sg.StudentKey END) AS EnteredStudentCount
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
WHERE sg.GroupKey IS NOT NULL
GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel;
GO

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
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
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
    CAST(sg.AssessmentWindowID         AS VARCHAR(20)) AS AssessmentWindowID,
    sg.GroupKey,
    CAST(sg.StudentKey                 AS VARCHAR(20)) AS StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    CAST(far.ReadingAssessmentID       AS VARCHAR(20)) AS ExistingReadingAssessmentID,
    CAST(far.ReadingScaleID            AS VARCHAR(20)) AS ExistingReadingScaleID,
    drs.LevelCode           AS ExistingScaleValue,
    far.AssessmentDate      AS ExistingAssessmentDate
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
WHERE sg.GroupKey IS NOT NULL;
GO
