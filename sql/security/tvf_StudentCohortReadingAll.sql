/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only — NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a reading result they have this year):
 *   - a student with an EN and an FR reading result => TWO rows (ScaleSystem 'EN_Reading' / 'FR_Reading');
 *   - a student with one => ONE row; a student with NO reading result => ONE row, ScaleSystem NULL
 *     (so the tree shows them as "No data" instead of dropping them).
 *   Reading language is DERIVED from ReadingScaleID -> DimReadingScale.ScaleSystem (the reading fact has
 *   no AssessmentLanguage column — unlike writing). Dual-language reading is real: entry routes through the
 *   section's cycle instance, whose ScaleSystem the save stores (see project_assessment_language_tracks).
 *
 * MEASURE: AchievementLevelCode is the band for THIS result's ReadingDelta (same DimAchievementLevel logic
 *   as tvf_StudentCohort). NULL when the student has no result, no delta, or is a reading-IPP/unresolved
 *   student (not measured). The client computes % Meeting/Exceeding = rows with a Meeting-or-above band
 *   (code >= 3) / rows with ANY band; IPP / no-data are excluded from the % and shown in the hover.
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst, per school via
 *   StaffSchoolAccess (identical gate to tvf_StudentCohortMathAll / the cohort TVF oversight branch). A
 *   plain teacher gets no rows; teachers keep the flat per-student cohort list.
 *
 * @CycleGroupID NULL = all current-year Reading windows (lifetime-this-year latest); a cycle id restricts
 *   the latest-pick to that cycle's Reading instances. Grades included = the span of the selected Reading
 *   windows' MinGrade..MaxGrade (config-driven, not hardcoded), so a no-result student still appears if
 *   their grade is assessed for reading.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    ReadWins AS (   -- current-year active Reading windows (optionally one cycle)
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (  -- assessed reading grade-order range across the selected windows (who should appear)
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows
        SELECT far.StudentNumber, drs.ScaleSystem, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- one value per student (1 = reading IPP in any family, 0 = not, NULL = unresolved)
        SELECT fsi.StudentKey, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY fsi.StudentKey
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20)) AS StudentKey,
        s.Grade,
        s.Homeroom,
        s.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        s.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS ReadingIPPStatus,
        lr.ScaleSystem,                                     -- language of THIS result; NULL = no reading result
        dal.AchievementLevelCode          AS AchievementLevelCode  -- band for THIS result; NULL = none/IPP/unresolved
    FROM DimStudent s
    INNER JOIN DimGrade g ON g.GradeCode = s.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT  JOIN ReadingIPP ipp ON ipp.StudentKey = s.StudentKey
    -- one row per (student, language-with-a-result); NULL when the student has no reading result
    LEFT  JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr ON lr.StudentNumber = s.StudentNumber
    -- Achievement band for this result's delta — same bound logic as tvf_StudentCohort (mutually exclusive
    -- bounds => at most one band per delta). No delta (no result / NULL) => no band.
    LEFT  JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lr.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND lr.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND lr.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND lr.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND lr.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND lr.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND lr.ReadingDelta =  dal.UpperBound))
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingAll] TO [StudentDataAssessment];
GO
