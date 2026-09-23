/*******************************************************************************
 * Function: tvf_UserAssessmentWindows  (INLINE table-valued function)
 * Purpose: @UPN-parameterized equivalent of vw_UserAssessmentWindows for the
 *          web app (Phase 3b). The web app connects as the StudentDataAssessment
 *          service principal, so CURRENT_USER is the SP, not the teacher -- the
 *          caller-scoped views return nothing. This iTVF takes the signed-in
 *          user's UPN and runs the SAME role-branched logic (Teacher /
 *          SchoolAdmin+SpecialistTeacher / RegionalAnalyst), so admins/analysts
 *          get their full multi-school scope (coverage when a teacher is out).
 * Created: 2026-06-22
 * Modified: 2026-09-18 — +CycleGroupID/CycleName so /enter collapses a cycle's instances into ONE
 *          card per subject. Applied the instance's PROGRAM SCOPE (it was selected but never
 *          filtered on, so an English-scope and an Early-Immersion-scope instance both counted the
 *          SAME students and the collapsed card's total came out double), and course-scoped the
 *          teacher branch to agree with the course-scoped group picker.
 *          2026-09-22 — COURSE-SCOPED the ADMIN + ANALYST branches too (2026-09-18 did only the
 *          teacher branch). They counted straight off DimStudent by grade+scope, so an oversight
 *          user's /enter card overcounted (students with no literacy section) and mis-read as
 *          English-only. Now they resolve through mapped-course sections, language-matched to the
 *          instance, exactly like tvf_TeacherGroups — the card equals the sum of the group cards for
 *          every role. Also changed EnteredStudentCount to "a result on ANY instance of the cycle"
 *          (CycleEntered) so a result on a sibling-language window still counts (matches the picker).
 * Region: Canada East (PIIDPA compliant)
 *
 * Why an inline TVF (not a proc): reads should be QUERYABLE -- the app does
 *   SELECT ... FROM dbo.tvf_UserAssessmentWindows(@UPN) [WHERE/ORDER BY ...]
 * keeping the role logic in one place in SQL while staying composable. Inline
 * TVFs are expanded into the calling query by the optimizer (view-like perf).
 * Reads = iTVFs; writes stay stored procs (they INSERT/UPDATE + audit).
 *
 * SECURITY: trusts the caller to pass a truthful @UPN. Safe only because SELECT
 * is granted to the SP alone and the web app passes an Entra-validated UPN (same
 * boundary as the @UPN write procs). Never expose with a client-supplied UPN.
 * Mirrors vw_UserAssessmentWindows (CURRENT_USER -> @UPN); keep in sync until the
 * Power App is retired. ORDER BY is intentionally omitted (the caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_UserAssessmentWindows;
GO

CREATE FUNCTION dbo.tvf_UserAssessmentWindows(@UPN VARCHAR(255))
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
            w.AssessmentWindowID, w.WindowName, w.AssessmentType, w.SchoolYear,
            w.StartDate, w.EndDate, w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.AssessmentLanguage, w.ScaleSystem,
            w.CycleGroupID,
            sc.DisplayName AS CycleName,   -- the HEADER's name ("SCoR 1"); the collapsed card's title
            CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
            CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
                 WHEN at.Today > w.EndDate   THEN 'Closed'
                 WHEN at.Today = w.EndDate   THEN 'ClosesToday'
                 ELSE 'Open' END AS WindowStatus
        FROM DimAssessmentWindow w
        CROSS JOIN AtlanticToday at
        LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
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
        -- The section's COURSE has to be one we assess for this subject, and in the instance's
        -- language. Without this a teacher whose only literacy course is ELA still got a French
        -- Reading card (their immersion students matched it by program), which then opened an empty
        -- group picker -- the picker is course-scoped and this count has to agree with it.
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IS NULL
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    -- Oversight (Administrator / SpecialistTeacher / RegionalAnalyst) — COURSE-SCOPED and
    -- SCHOOL-SCOPED: only students in MAPPED-COURSE sections (ELA/FLA/Math) in the schools the caller
    -- covers via StaffSchoolAccess (= their CanChangeSchool buildings), language-matched to the
    -- instance. RegionalAnalyst is gated the SAME way — NO region-wide branch; a region-wide analyst
    -- simply has every building in their list. Mirrors tvf_TeacherGroups' Oversight path.
    AdminStudents AS (
        SELECT wed.AssessmentWindowID, s.StudentKey
        FROM Caller c
        CROSS JOIN WindowEffectiveDates wed
        INNER JOIN StaffSchoolAccess ssa ON ssa.StaffKey = c.StaffKey
        INNER JOIN DimSection sec
                ON sec.SchoolID = ssa.SchoolID
               AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
        INNER JOIN DimCourseAssessment ca
                ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
               AND ((wed.AssessmentType IN ('Reading', 'Writing') AND ca.Kind = 'Literacy')
                 OR (wed.AssessmentType = 'Math'                  AND ca.Kind = 'Math'))
               AND (wed.AssessmentLanguage IS NULL OR ca.Language IS NULL OR ca.Language = wed.AssessmentLanguage)
        INNER JOIN FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.StartDate  <= wed.EndDate
               AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
        INNER JOIN DimStudent s ON s.StudentKey = e.StudentKey
        INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
        INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
        INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
        INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
        WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
          AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
          AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
          AND (wed.ProgramScope IS NULL
               OR (',' + wed.ProgramScope + ',') LIKE ('%,' + dp.ScopeBucket + ',%'))
    ),
    ApplicableStudents AS (
        SELECT * FROM TeacherStudents
        UNION ALL SELECT * FROM AdminStudents
    ),
    -- "Entered" = a result on ANY instance of the same cycle+subject, not just this one window. A
    -- student's result can sit on a sibling-language instance (e.g. immersion reading entered on the
    -- English window before the French instance existed); the collapsed /enter card and the group
    -- picker both treat that as entered, so this must too. Keyed by CycleGroupID + AssessmentType.
    CycleEntered AS (
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentReading f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Reading' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentWriting f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Writing' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
        UNION
        -- Math (added 2026-09-23): a student counts as entered once they have ANY task result -
        -- FactAssessmentMath is one row per (student x task), so DISTINCT StudentKey gives "has begun",
        -- the same "has a result" meaning used for Reading/Writing. Without this, Math cards read 0.
        SELECT DISTINCT w2.CycleGroupID, w2.AssessmentType, f.StudentKey
        FROM DimAssessmentWindow w2
        INNER JOIN FactAssessmentMath f ON f.AssessmentWindowID = w2.AssessmentWindowID
        WHERE w2.AssessmentType = 'Math' AND w2.ActiveFlag = 1 AND w2.CycleGroupID IS NOT NULL
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
        wed.ProgramScope,
        wed.AssessmentLanguage,
        wed.ScaleSystem,
        wed.CycleGroupID,   -- lets /enter collapse a cycle's instances into ONE card per subject
        wed.CycleName,      -- header name for that collapsed card (instance names differ per scope)
        wed.WindowStatus,
        COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
        -- Entered if the student has a result on ANY instance of this cycle+subject (see CycleEntered),
        -- so a result on a sibling-language instance still counts and the card matches the group picker.
        COUNT(DISTINCT CASE WHEN ce.StudentKey IS NOT NULL THEN a.StudentKey END) AS EnteredStudentCount
    FROM WindowEffectiveDates wed
    INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
    LEFT JOIN CycleEntered ce
           ON ce.CycleGroupID   = wed.CycleGroupID
          AND ce.AssessmentType = wed.AssessmentType
          AND ce.StudentKey     = a.StudentKey
    GROUP BY
        wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
        wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily,
        wed.ProgramScope, wed.AssessmentLanguage, wed.ScaleSystem, wed.CycleGroupID, wed.CycleName,
        wed.WindowStatus
);
GO

-- Re-grant here so a standalone redeploy (DROP+CREATE) never leaves the web-app SP without SELECT.
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows] TO [StudentDataAssessment];
GO
