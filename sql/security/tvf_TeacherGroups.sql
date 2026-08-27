/*******************************************************************************
 * Function: tvf_TeacherGroups  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_TeacherGroups for the web app
 *          (Phase 3b). Same three role branches + group-resolution rules (PP-9
 *          -> 'HR:'+Homeroom; 10-12/RG -> 'SEC:'+SectionID). Takes the signed-in
 *          UPN + target window; returns one row per group.
 * Created: 2026-06-22
 * Region: Canada East (PIIDPA compliant)
 *
 * See tvf_UserAssessmentWindows header for the iTVF rationale + SECURITY note
 * (trusts @UPN; SELECT granted to the SP only). Mirrors vw_TeacherGroups with
 * CURRENT_USER -> @UPN. @AssessmentWindowID is VARCHAR (Power-Fx/JS precision);
 * cast inline to BIGINT. ORDER BY omitted -- the caller sorts.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherGroups;
GO

CREATE FUNCTION dbo.tvf_TeacherGroups(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20))
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
            w.MinGrade, w.MaxGrade, w.ProgramFamily,
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    TeacherApplicable AS (
        SELECT
            wed.AssessmentWindowID, s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom,
            sec.SectionID, sec.SectionNumber, sec.CourseName
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
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
    ),
    AdminAnalystApplicable AS (
        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom
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

        UNION ALL

        SELECT
            wed.AssessmentWindowID, wed.WindowStartDate, wed.WindowEndDate, wed.EffectiveDate,
            s.StudentKey, s.Grade, sg.GradeOrder, s.Homeroom
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
            a.AssessmentWindowID, a.StudentKey, a.Grade, a.GradeOrder, a.Homeroom,
            sec.SectionID, sec.SectionNumber, sec.CourseName
        FROM AdminAnalystApplicable a
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
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, SectionID, SectionNumber, CourseName
        FROM TeacherApplicable
        UNION ALL
        SELECT AssessmentWindowID, StudentKey, Grade, GradeOrder, Homeroom, SectionID, SectionNumber, CourseName
        FROM AdminAnalystWithSections
    ),
    StudentGroups AS (
        SELECT
            AssessmentWindowID, StudentKey, Grade,
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
        -- "Entered" = students with >=1 entry in the fact matching the window's TYPE (Reading vs
        -- Writing). COUNT(DISTINCT) collapses the multiple-dated-entries fan-out. Only one fact has
        -- rows for a given window (a window is one type), so joining both is safe.
        COUNT(DISTINCT CASE
            WHEN aw.AssessmentType = 'Reading' AND far.ReadingAssessmentID IS NOT NULL THEN sg.StudentKey
            WHEN aw.AssessmentType = 'Writing' AND faw.WritingAssessmentID IS NOT NULL THEN sg.StudentKey
        END) AS EnteredStudentCount
    FROM StudentGroups sg
    INNER JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN FactAssessmentReading far
           ON far.AssessmentWindowID = sg.AssessmentWindowID
          AND far.StudentKey         = sg.StudentKey
    LEFT JOIN FactAssessmentWriting faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
    WHERE sg.GroupKey IS NOT NULL
    GROUP BY sg.AssessmentWindowID, sg.GroupKey, sg.GroupType, sg.GroupLabel
);
GO
