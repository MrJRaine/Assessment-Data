/*******************************************************************************
 * View: vw_TeacherGroups
 * Purpose: Returns one row per (calling user, applicable window, group) tuple.
 *          Powers `scrGroupSelect` in the Power Apps entry app. Power Apps
 *          filters client-side by gblSelectedWindow.AssessmentWindowID.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Group resolution rules:
 *   - PP-9 students (DimGrade.GradeOrder <= 9): group by Homeroom
 *       GroupKey   = 'HR:' + Homeroom
 *       GroupType  = 'Homeroom'
 *       GroupLabel = 'Homeroom <Homeroom>'
 *   - 10-12 + RG students (DimGrade.GradeOrder >= 10): group by Section
 *       GroupKey   = 'SEC:' + SectionID
 *       GroupType  = 'Section'
 *       GroupLabel = SectionNumber + ' — ' + CourseName
 *
 * Why split: PP-9 students have a stable homeroom designation in PowerSchool
 * that maps to a single elementary teacher's class. Senior students rotate
 * through multiple content sections, none of which is a "homeroom" — they're
 * grouped per content section instead, so a senior teacher sees the students
 * in their own course (e.g. "FRA12.01 — French 12").
 *
 * Role-branched historical-roster reconciliation (per
 * project_historical_roster_reconciliation memory, decided 2026-05-12):
 *   Mirrors the pattern in vw_UserAssessmentWindows. Each role branch
 *   resolves applicable students at the window's effective date.
 *
 *   - Teacher (AccessLevel IS NULL):
 *       Students in sections they taught during the window. Section context
 *       comes from FactSectionTeachers + DimSection naturally — for PP-9
 *       students this multiplies rows by section, handled by COUNT(DISTINCT
 *       StudentKey) in the final aggregation. For 10-12 students each
 *       (window, student, section) tuple is its own group row by design.
 *   - SchoolAdmin / SpecialistTeacher (AccessLevel IN (...)):
 *       Students whose DimStudent (effective at window date) had SchoolID
 *       in their CURRENT StaffSchoolAccess list. No section context from the
 *       admin branch itself — for senior students (GradeOrder >= 10) we
 *       LEFT JOIN FactEnrollment + DimSection (gated on the window effective
 *       date) to surface section groups.
 *   - RegionalAnalyst:
 *       All students whose DimStudent (effective at window date) matches the
 *       window scope. Same section-context augmentation for seniors.
 *
 * Counts (per group, per window):
 *   - ApplicableStudentCount: distinct students in this group the caller can see
 *   - EnteredStudentCount: distinct students in this group with a
 *                          FactAssessmentReading row for the window.
 *
 *   TODO (Phase 5+): EnteredStudentCount currently only counts Reading.
 *   Same Writing/Math gap as vw_UserAssessmentWindows.
 *
 * Notes:
 *   - PP-9 students with NULL Homeroom land in the 'HR:(none)' bucket — a
 *     visible bucket rather than a silently-excluded one, so missing data is
 *     surfaced.
 *   - 10-12 students with no qualifying section enrollment are dropped from
 *     the view (their GroupKey would be NULL). Acceptable for MVP — a senior
 *     student without an enrollment in the window's program scope wouldn't
 *     be assessed anyway.
 *   - Identity / time zone: same conventions as vw_UserAssessmentWindows.
 ******************************************************************************/

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
-- ROLE BRANCH 1: Teacher — pulls section context naturally through
-- FactSectionTeachers → DimSection. For PP-9 students this produces
-- (window × student × section) tuples; COUNT(DISTINCT StudentKey) in
-- the final aggregation dedupes per homeroom.
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
-- ROLE BRANCH 2: SchoolAdmin / SpecialistTeacher — gated via StaffSchoolAccess.
-- One row per (window, student). Section context filled in later via the
-- senior-augmentation LEFT JOIN.
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
-- ROLE BRANCH 3: RegionalAnalyst — full population gated only by window scope.
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
-- For admin/analyst rows that need section context (only seniors, GradeOrder >= 10):
-- LEFT JOIN FactEnrollment + DimSection effective at the window date. Each
-- senior student produces one row per section they're enrolled in within
-- the window's date envelope. PP-9 admin/analyst rows pass through unchanged
-- (LEFT JOIN finds no match, section columns stay NULL).
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
-- Union all three role branches into one uniform shape.
ApplicableStudents AS (
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM TeacherApplicable
    UNION ALL
    SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom,
           SectionID, SectionNumber, CourseName
    FROM AdminAnalystWithSections
),
-- Resolve group key/label/type per row.
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
    CAST(sg.AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,   -- BIGINT cast to VARCHAR for Power Fx precision; see feedback_powerapps_bigint_precision memory
    sg.GroupKey,
    sg.GroupType,
    sg.GroupLabel,
    MAX(sg.Grade) AS Grade,                                 -- one grade per group by construction; MAX is safe
    COUNT(DISTINCT sg.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN sg.StudentKey END) AS EnteredStudentCount   -- TODO Phase 5+: extend for Writing/Math
FROM StudentGroups sg
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = sg.AssessmentWindowID
      AND far.StudentKey         = sg.StudentKey
WHERE sg.GroupKey IS NOT NULL                               -- drops seniors with no qualifying section enrollment
GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel;
