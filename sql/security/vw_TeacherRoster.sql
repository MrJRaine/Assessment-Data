/*******************************************************************************
 * View: vw_TeacherRoster
 * Purpose: Returns one row per (calling user, applicable window, group,
 *          student) tuple with existing reading-assessment value if any.
 *          Powers `scrRosterGrid` in the Power Apps entry app. Power Apps
 *          filters client-side by gblSelectedWindow.AssessmentWindowID AND
 *          gblSelectedGroup.GroupKey.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Companion view to vw_TeacherGroups — same role-branched historical-roster
 * reconciliation, same group-resolution rules (PP-9 → 'HR:' + Homeroom;
 * 10-12/RG → 'SEC:' + SectionID). See vw_TeacherGroups header for the full
 * reconciliation rationale.
 *
 * "Existing assessment" semantics:
 *   - One assessment per (StudentKey, AssessmentWindowID) by design.
 *   - LEFT JOIN to FactAssessmentReading on that pair surfaces the prior
 *     entry's ReadingScaleID + LevelCode + AssessmentDate if any.
 *   - Power Apps displays the level code (or "—" via Coalesce) in the
 *     "Existing Level" column; the upsert proc resolves new-value writes
 *     against the same (Student, Window) key.
 *
 *   TODO (Phase 5+): the "existing" columns are Reading-only. When Writing/
 *   Math entry screens go live, either branch this view by AssessmentType
 *   or build sibling views (vw_WritingRoster / vw_MathRoster).
 *
 * Dedup note:
 *   The teacher role branch can produce multiple rows for the same student
 *   (one per section the teacher teaches them in). For PP-9 students grouped
 *   by homeroom, those rows collapse to the same (window, group, student)
 *   triple — the final SELECT DISTINCT dedupes. For 10-12 students grouped
 *   by section, each section is its own group, so multi-section enrollment
 *   produces multiple group rows by design.
 *
 * Identity / time zone: same conventions as vw_UserAssessmentWindows /
 * vw_TeacherGroups.
 ******************************************************************************/

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
-- Senior section context for admin/analyst rows (only GradeOrder >= 10).
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
    sg.AssessmentWindowID,
    sg.GroupKey,
    sg.StudentKey,
    sg.StudentNumber,
    sg.FirstName,
    sg.LastName,
    sg.Grade,
    sg.ProgramCode,
    sg.ProgramFamily,
    far.ReadingAssessmentID AS ExistingReadingAssessmentID,
    far.ReadingScaleID      AS ExistingReadingScaleID,
    drs.LevelCode           AS ExistingScaleValue,
    far.AssessmentDate      AS ExistingAssessmentDate
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
LEFT JOIN DimReadingScale drs
       ON drs.ReadingScaleID = far.ReadingScaleID
WHERE sg.GroupKey IS NOT NULL;
