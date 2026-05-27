/*******************************************************************************
 * View: vw_StudentAssessmentHistory
 * Purpose: Power-Apps-facing history view for scrStudentData. One row per
 *          (student, completed reading assessment) for students in the
 *          calling user's scope. Powers the cohort bar chart (achievement
 *          distribution across windows in the selected date range) and the
 *          per-student detail timelines (reading level / achievement /
 *          difference over time).
 *
 * Created: 2026-05-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: one row per (StudentKey, ReadingAssessmentID).
 *
 * Date range / school year filtering:
 *   Done client-side in Power Apps. The view exposes WindowSchoolYear,
 *   WindowStartDate, WindowEndDate, and AssessmentDate -- Power Apps applies
 *   the active filter (default current school year) at the collection level.
 *
 * IPP gating:
 *   IsChartEligibleReading is computed the same way as in vw_StudentCohort
 *   (CURRENT IPP-Reading status for the student's program family). Per the
 *   2026-05-27 design decision, IPP students (confirmed OR unresolved) are
 *   excluded from charts. The detail timeline screen may choose to surface
 *   their data anyway -- the column is present for filtering, not enforced.
 *
 * RLS branching: same OR-across-EXISTS pattern as vw_StudentCohort /
 *   vw_StudentIPP. Regional Analyst -> all; Admin/SpecialistTeacher -> their
 *   schools; Teacher -> current section roster.
 *
 * Power Apps binding notes:
 *   - StudentKey, ReadingAssessmentID, AssessmentWindowID, ReadingScaleID
 *     CAST to VARCHAR(20) (project_powerapps_bigint_precision).
 *   - StudentNumber stays BIGINT (10-digit, within Power Fx safe range).
 *
 * After deploying: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source (feedback_powerapps_data_source_refresh).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentAssessmentHistory;
GO

CREATE VIEW vw_StudentAssessmentHistory AS
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
    -- IPP gate (same convention as vw_StudentCohort)
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1
            WHEN crd.IsIPP = 0           THEN 1
            ELSE 0
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    -- Assessment record
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
    dal.HexColor                                             AS AchievementHexColor
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
WHERE s.EnrollStatus IN (0, -1)
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff staff
            WHERE LOWER(staff.Email) = LOWER(CURRENT_USER)
              AND staff.IsCurrent    = 1
              AND staff.AccessLevel  = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email)   = LOWER(CURRENT_USER)
              AND ssa.SchoolID       = s.SchoolID
              AND ssa.AccessLevel   IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst
            JOIN   DimSection sec
                ON sec.SectionID = fst.SectionID
               AND sec.IsCurrent = 1
            JOIN   FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.ActiveFlag  = 1
            WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst.IsCurrent = 1
              AND e.StudentKey  = s.StudentKey
        )
      );
GO
