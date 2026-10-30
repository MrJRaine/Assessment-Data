/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only — NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (restores the documented design; server-side
 *          patch under 1.3.0). A row WITH a result now attributes School/Grade/Homeroom from the
 *          RESULT's frozen DimStudent version (fact.StudentKey — the version in force when it was
 *          recorded), NOT the student's current version — so a student transfer no longer moves their
 *          recorded history to the new school, and a student who left the district keeps their recorded
 *          results in the cycles where they were assessed. A student with NO result in scope still
 *          shows from their CURRENT version (current school, "No data"), current+enrolled only.
 *          The access gate follows the ATTRIBUTED school. Non-movers are unchanged (frozen = current).
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a reading result they have this year):
 *   - a student with an EN and an FR reading result => TWO rows (ScaleSystem 'EN_Reading' / 'FR_Reading');
 *   - a student with one => ONE row; a student with NO reading result => ONE row, ScaleSystem NULL
 *     (so the tree shows them as "No data" instead of dropping them).
 *   A mover assessed at two schools shows under EACH school that recorded a (latest-per-language) result.
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
 *   StaffSchoolAccess, matched against the row's ATTRIBUTED school (identical gate shape to
 *   tvf_StudentCohortMathAll). A plain teacher gets no rows; teachers keep the flat per-student list.
 *
 * @CycleGroupID NULL = all current-year Reading windows (lifetime-this-year latest); a cycle id restricts
 *   the latest-pick to that cycle's Reading instances. Grades included = the span of the selected Reading
 *   windows' MinGrade..MaxGrade (config-driven, not hardcoded), checked against the ATTRIBUTED grade.
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
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against (insert-time
        -- effective-date/section-school resolution) — it carries the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, drs.ScaleSystem,
               far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- one value per STUDENT NUMBER (1 = reading IPP in any family, 0 = not, NULL =
        -- unresolved). Keyed by StudentNumber because attributed rows carry FROZEN StudentKeys,
        -- which predate the IPP rows' current-version repointing.
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTED base: assessed rows come from the RESULT's frozen student version (school/grade/
    -- homeroom as recorded — includes movers' old-school rows and district leavers); unassessed
    -- rows are CURRENT, enrolled students with no reading result in scope ("No data" at their
    -- current school). A non-mover's frozen version IS their current version — identical output.
    Base AS (
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               lr.ScaleSystem, lr.AssessmentDate, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1
        UNION ALL
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               CAST(NULL AS VARCHAR(20)), CAST(NULL AS DATE), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestReading lr2 WHERE lr2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        b.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS ReadingIPPStatus,
        b.ScaleSystem,                                      -- language of THIS result; NULL = no reading result
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        dal.AchievementLevelCode          AS AchievementLevelCode  -- band for THIS result; NULL = none/IPP/unresolved
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN ReadingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    -- Achievement band for this result's delta — same bound logic as tvf_StudentCohort (mutually exclusive
    -- bounds => at most one band per delta). No delta (no result / NULL) => no band.
    LEFT  JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND b.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND b.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND b.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND b.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND b.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND b.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND b.ReadingDelta =  dal.UpperBound))
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingAll] TO [StudentDataAssessment];
GO
