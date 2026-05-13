/*******************************************************************************
 * View: vw_UserAssessmentWindows
 * Purpose: Returns one row per (calling user, applicable assessment window)
 *          tuple. Powers `scrWindowSelect` in the Power Apps entry app.
 * Created: 2026-05-13
 * Region: Canada East (PIIDPA compliant)
 *
 * Role-branched historical-roster reconciliation (per
 * project_historical_roster_reconciliation memory, decided 2026-05-12):
 *
 *   For each active window, compute its **effective date**:
 *     CASE WHEN today_atlantic > window.EndDate THEN window.EndDate
 *          ELSE today_atlantic END
 *   Then resolve "applicable students" using that effective date for SCD
 *   point-in-time joins. The effect: for CLOSED windows, teachers see the
 *   roster they HAD AT THE TIME — not their current roster.
 *
 * Role branches (mutually exclusive in practice via c.AccessLevel filter):
 *   - Teacher       (AccessLevel IS NULL):       students in their sections
 *                                                during the window's effective
 *                                                date, gated on FactSection-
 *                                                Teachers + DimSection +
 *                                                FactEnrollment effective dates
 *   - SchoolAdmin / SpecialistTeacher:           students whose DimStudent
 *                                                (effective at window date) had
 *                                                SchoolID in their CURRENT
 *                                                StaffSchoolAccess list
 *                                                (admin side is NOT historically
 *                                                reconciled — MVP scope)
 *   - RegionalAnalyst:                           all students whose DimStudent
 *                                                (effective at window date)
 *                                                matches the window scope
 *
 * Counts:
 *   - ApplicableStudentCount: distinct students the calling user can see for
 *                             this window per the role-branch logic above.
 *   - EnteredStudentCount:    distinct students with a FactAssessmentReading
 *                             row for the window.
 *
 *   TODO (Phase 5+): EnteredStudentCount currently only counts Reading
 *   assessments. When Writing / Math upsert procs go live, extend the count
 *   with a CASE on wed.AssessmentType + LEFT JOIN FactAssessmentWriting /
 *   FactAssessmentMath. For now Writing/Math windows would show 0 entered
 *   even if data existed.
 *
 * Identity:
 *   - Uses CURRENT_USER (not USERPRINCIPALNAME() — not supported in Fabric
 *     Warehouse T-SQL; see fabric-warehouse-sql skill item 14).
 *   - Emails lowercased on the join (DimStaff.Email + FactSectionTeachers
 *     .TeacherEmail are lowercased at ingest; CURRENT_USER casing is
 *     environment-dependent, so LOWER() both sides defensively).
 *
 * Time zone:
 *   - "Today" is computed in Atlantic time per the project time-zone
 *     convention (project_timezone_convention memory).
 ******************************************************************************/

CREATE VIEW vw_UserAssessmentWindows AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
-- Resolve caller's role + identity once.
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
-- For each active window, compute its effective date for historical-roster resolution.
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
-- ROLE BRANCH 1: Teacher — students in sections they taught during the window.
-- Each join gated on the window effective date being within the relevant
-- Type 2 row's effective period.
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
    WHERE c.AccessLevel IS NULL                                         -- teachers have no school-tier AccessLevel
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: School Admin / SpecialistTeacher — students whose DimStudent
-- (effective at window date) had SchoolID in their CURRENT StaffSchoolAccess list.
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
-- ROLE BRANCH 3: Regional Analyst — all students whose DimStudent
-- (effective at window date) matches the window's scope.
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
    wed.AssessmentWindowID,
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
                        THEN a.StudentKey END) AS EnteredStudentCount   -- TODO Phase 5+: extend for Writing/Math
FROM WindowEffectiveDates wed
INNER JOIN ApplicableStudents a
        ON a.AssessmentWindowID = wed.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = wed.AssessmentWindowID
      AND far.StudentKey         = a.StudentKey
GROUP BY
    wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
    wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily, wed.WindowStatus;
