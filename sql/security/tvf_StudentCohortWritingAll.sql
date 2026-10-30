/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only — no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom comes from the RESULT's frozen DimStudent version and the
 *          oversight gate follows the ATTRIBUTED school; a student with no writing result in that cycle
 *          stays a current, enrolled student at their current school. With no cycle (the "Current"
 *          view) everything anchors on the current version, as before. Non-movers are unchanged.
 * Region: Canada East (PIIDPA compliant)
 *
 * GRAIN — one row per (student x the language of a writing result they have this year):
 *   - FactAssessmentWriting.AssessmentLanguage IS part of the grain (unlike reading, which derives it
 *     from the scale), so a student with an English and a French writing result has TWO fact rows and
 *     gets TWO rows here ('English' / 'French'); one language => one row; no writing result => ONE row,
 *     AssessmentLanguage NULL ("No data"). A mover assessed at two schools shows under EACH school that
 *     recorded a (latest-per-language) result.
 *
 * MEASURE: the band CODE of the latest writing AVERAGE for that (student, language), by the SAME cut
 *   scores as tvf_StudentCohortWriting (avg>=3.50->4, >=2.75->3, >=1.75->2, else 1; NULL avg->NULL code).
 *   Client % Meeting/Exceeding = rows with code >= 3 / rows with ANY code, IPP excluded (via the flag).
 *   Average counts ONLY explicit '1'-'4' traits (SCR / '-' / NULL dropped from numerator AND denominator).
 *
 * Scope: OVERSIGHT ONLY — Administrator / SpecialistTeacher / RegionalAnalyst via StaffSchoolAccess,
 *   matched against the row's ATTRIBUTED school.
 * @CycleGroupID NULL = all current-year Writing windows; a cycle id restricts the latest-pick. Grades =
 *   the span of the selected Writing windows' MinGrade..MaxGrade, checked against the ATTRIBUTED grade.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingAll;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingAll(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    WriteWins AS (
        SELECT w.AssessmentWindowID, w.MinGrade, w.MaxGrade
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM WriteWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    LatestWriting AS (   -- latest result per (student, language) across the selected windows + its average.
        -- faw.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage, faw.AssessmentDate,
            faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,  -- per-trait rollup (score >= 3 = Meeting/Exceeding)
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber, faw.AssessmentLanguage
                               ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        WHERE faw.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins)
    ),
    WritingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
        GROUP BY dsi.StudentNumber
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed rows come from the RESULT's frozen
    -- student version (includes movers' old-school rows and district leavers) and unassessed rows are
    -- CURRENT, enrolled students ("No data" at their current school); with NO cycle (the "Current"
    -- view) everything anchors on the current version, as before.
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               lw.AssessmentLanguage, lw.AssessmentDate,
               lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore, lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- cycle selected, unassessed: current, enrolled students with no result in that cycle
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE @CycleGroupID IS NOT NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM LatestWriting lw2 WHERE lw2.StudentNumber = s.StudentNumber)
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               lw3.AssessmentLanguage, lw3.AssessmentDate,
               lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore, lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        LEFT JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,
        b.SchoolID,
        sch.SchoolName,
        ipp.IsIPP                         AS WritingIPPStatus,
        b.AssessmentLanguage,                                -- 'English' | 'French'; NULL = no writing result
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        b.IdeasScore                      AS IdeasScore,        -- the four trait scores ('1'-'4'/'SCR'/'-'/NULL)
        b.OrganizationScore               AS OrganizationScore, -- for the per-trait roll-up (% Meeting/Exceeding or Mean)
        b.LanguageScore                   AS LanguageScore,
        b.ConventionsScore                AS ConventionsScore,
        b.AvgScore                        AS AvgScore,          -- the 4-trait average (for the Mean measure)
        CASE WHEN b.AvgScore IS NULL THEN NULL
             WHEN b.AvgScore >= 3.50 THEN 4
             WHEN b.AvgScore >= 2.75 THEN 3
             WHEN b.AvgScore >= 1.75 THEN 2
             ELSE 1 END                   AS AchievementLevelCode
    FROM Base b
    INNER JOIN DimGrade g ON g.GradeCode = b.Grade
    CROSS JOIN GradeSpan gs
    LEFT  JOIN DimSchool sch ON sch.SchoolID = b.SchoolID
    LEFT  JOIN WritingIPP ipp ON ipp.StudentNumber = b.StudentNumber
    WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
      AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                  WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = b.SchoolID
                    AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingAll] TO [StudentDataAssessment];
GO
