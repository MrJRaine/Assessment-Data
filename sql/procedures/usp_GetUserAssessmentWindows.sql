/*******************************************************************************
 * Procedure: usp_GetUserAssessmentWindows
 * Purpose: @UPN-parameterized equivalent of vw_UserAssessmentWindows for the
 *          self-hosted web app (Phase 3b). The web app connects as the
 *          StudentDataAssessment service principal, so CURRENT_USER is the SP,
 *          not the teacher -- the caller-scoped views return nothing. This proc
 *          takes the signed-in user's UPN explicitly and runs the SAME
 *          role-branched logic (Teacher / SchoolAdmin+SpecialistTeacher /
 *          RegionalAnalyst), so admins and analysts get their full multi-school
 *          scope (needed for coverage when a teacher is out).
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * Replaces the web app's dependency on the SharePoint-era bridge views
 * (vw_Bridge*). Those stay only for any legacy/bridge use; the web app reads
 * this proc. The caller-scoped vw_UserAssessmentWindows remains for the
 * (deprecated) Power App + is the logic this mirrors -- keep them in sync until
 * the Power App is retired.
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because EXECUTE
 * is granted to the SP alone and the web app passes an Entra-validated UPN (same
 * boundary as the @UPN write procs). Never expose with a client-supplied UPN.
 *
 * Identity: resolves the caller from DimStaff by @UPN (lowercased) instead of
 * CURRENT_USER. Everything else is identical to vw_UserAssessmentWindows
 * (historical-roster reconciliation, dominant-month-free window aggregates).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_GetUserAssessmentWindows;
GO

CREATE PROCEDURE usp_GetUserAssessmentWindows
    @UPN VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH AtlanticToday AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    Caller AS (
        SELECT TOP 1
            d.StaffKey,
            LOWER(d.Email) AS Email,
            d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN)
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
    TeacherStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
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
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
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
        SELECT wed.AssessmentWindowID, s.StudentKey
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
        wed.ScaleSystem,
        wed.WindowStatus,
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = wed.AssessmentWindowID
          AND far.StudentKey         = a.StudentKey
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ScaleSystem, wed.WindowStatus
    ORDER BY wed.WindowName;
END;
GO
