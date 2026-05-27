/*******************************************************************************
 * View: vw_StudentCohort
 * Purpose: Power-Apps-facing cohort view for scrStudentData. One row per
 *          student in the calling user's scope, with demographics for filters
 *          + most-recent reading evidence for the pie chart.
 *
 *          Consumed by:
 *            - scrStudentData (cohort screen): student gallery, demographic
 *              slicers (Grade, Gender, SelfIDAfrican, SelfIDIndigenous, IPP,
 *              Homeroom), and the achievement-level pie chart.
 *
 * Created: 2026-05-27
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS branching (OR-across-EXISTS pattern, matching vw_StudentIPP):
 *   Regional Analyst:  full visibility (no school/student filter)
 *   Admin / SpecialistTeacher: students in their schools via StaffSchoolAccess
 *   Teacher: students currently on their section roster via FactSectionTeachers
 *
 *   Uses CURRENT_USER under Entra ID Integrated auth (not USERPRINCIPALNAME()
 *   -- the latter is not supported in Fabric Warehouse).
 *
 * "Most recent reading" semantics (locked in 2026-05-27):
 *   Lifetime-latest completed reading assessment for the student -- NOT
 *   bounded by school year or date range. The cohort screen's school-year
 *   filter affects the bar chart and detail timeline, not the pie chart's
 *   per-student "current level" classification. Tie-break by AssessmentDate
 *   DESC, then ReadingAssessmentID DESC.
 *
 * IPP gating (locked in 2026-05-27):
 *   IsChartEligibleReading is a convenience BIT for the pie chart filter.
 *   Set to 0 when the student has a current Reading IPP row (FactStudentIPP
 *   IsCurrent = 1) that is either confirmed IPP (IsIPP = 1) OR unresolved
 *   (IsIPP IS NULL). Confirmed not-IPP (IsIPP = 0) or no row at all -> 1.
 *
 * Most-recent reading columns are NULL for students with zero history. The
 *   Power Apps pie chart filters on
 *     IsChartEligibleReading = true And Not(IsBlank(MostRecentAchievementLevelCode))
 *   so unassessed students simply don't appear in the chart -- but still
 *   appear in the cohort gallery.
 *
 * Power Apps binding notes:
 *   - StudentKey, MostRecentAssessmentWindowID, MostRecentReadingScaleID,
 *     MostRecentReadingAssessmentID are CAST to VARCHAR(20) to avoid Power
 *     Fx's 16-digit ceiling on 19-digit BIGINT IDENTITY (see
 *     project_powerapps_bigint_precision memory).
 *   - StudentNumber stays BIGINT (10-digit provincial number, within range).
 *   - AchievementLevelCode is plain INT (1-4) -- no cast needed.
 *
 * After deploying this view: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source (feedback_powerapps_data_source_refresh).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentCohort;
GO

CREATE VIEW vw_StudentCohort AS
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
    s.ProgramCode,
    p.ProgramFamily,
    s.Gender,
    s.SelfIDAfrican,
    s.SelfIDIndigenous,
    s.IPP                                                    AS IPP_PSFlag,
    s.Adap,
    s.Homeroom,
    -- IPP gate for charts (Reading, matched on student's program family)
    crd.IsIPP                                                AS IsIPP_Reading,
    CASE
        WHEN crd.StudentKey IS NULL          THEN 'N/A'         -- no applicable Reading IPP row
        WHEN crd.IsIPP IS NULL                THEN 'Unresolved'
        WHEN crd.IsIPP = 1                    THEN 'IPP'
        WHEN crd.IsIPP = 0                    THEN 'Not IPP'
    END                                                      AS IPPStatus_Reading,
    CAST(
        CASE
            WHEN crd.StudentKey IS NULL THEN 1                -- no IPP row -> eligible
            WHEN crd.IsIPP = 0           THEN 1                -- confirmed not-IPP -> eligible
            ELSE 0                                            -- IPP=1 or NULL -> exclude
        END AS BIT
    )                                                        AS IsChartEligibleReading,
    -- Most-recent reading evidence (lifetime, NULL if none)
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
    dal.HexColor                                             AS MostRecentAchievementHexColor
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN DimGrade sg
    ON sg.GradeCode  = s.Grade
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
  AND s.EnrollStatus IN (0, -1)
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
