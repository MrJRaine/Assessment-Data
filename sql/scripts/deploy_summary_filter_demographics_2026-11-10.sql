/*******************************************************************************
 * Deploy: Summary-tree demographics + expected-language rows
 * Date: 2026-11-10 (revised 2026-11-12)
 * Target: Assessment_Warehouse_Dev FIRST, then live. Idempotent - safe to run
 * again even if the 2026-11-10 revision already ran.
 * Replaces five oversight roll-up TVFs with BOTH changes:
 *   (a) 2026-11-10 - Gender / SelfIDAfrican / SelfIDIndigenous columns for the
 *       Reports summary trees' demographic filter section;
 *   (b) 2026-11-12 - EXPECTED-LANGUAGE rows (reading/writing TVFs only): the
 *       per-student language set becomes EXPECTED (StudentExpectedAssessment,
 *       cycle-scoped) UNION assessed, so the Language of Assessment filter no
 *       longer drops students who should be assessed in a language but have no
 *       result yet - they now count under that language as "no result".
 *   1. tvf_StudentCohortReadingAll     (roll-up feed)     a + b
 *   2. tvf_StudentCohortWritingAll     (roll-up feed)     a + b
 *   3. tvf_StudentCohortReadingGroup   (drill detail)     a + b
 *   4. tvf_StudentCohortWritingGroup   (drill detail)     a + b
 *   5. tvf_StudentCohortRWM            (RWM report feed)  a only
 * READS: DimStudent (Gender/Self-ID; frozen version for attributed rows),
 * StudentExpectedAssessment (expected languages). WRITES: nothing -
 * DROP/CREATE of the five iTVFs + re-GRANT to StudentDataAssessment only.
 * Assembled verbatim from sql/security sources.
 ******************************************************************************/
/*******************************************************************************
 * Function: tvf_StudentCohortReadingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Reading OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Mirrors tvf_StudentCohortMathAll: one row per in-scope student PER READING-RESULT LANGUAGE,
 *          carrying the measure the client rolls up (School -> Grade|Homeroom, % Meeting/Exceeding) plus
 *          the language so the display can show distinct STUDENTS vs RESULTS per language (EN/FR) + overall.
 *          Counts/measure only — NO names or student numbers (privacy; the per-group student detail loads
 *          separately on expand, same pattern as Math).
 * Created: 2026-10-16
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows (fixes the Language of Assessment filter dropping
 *          expected-but-unassessed students): the per-student language set is now EXPECTED
 *          (StudentExpectedAssessment, cycle-scoped) UNION assessed — the same union as
 *          tvf_StudentCohort's LangSet. An expected language with no result emits a row with
 *          ScaleSystem set, NULL date/delta, IsExpectedOnly=1 (the client counts the STUDENT under
 *          that language but no result); the NULL-language "No data" fallback row now only fires
 *          when a student is neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters). Attributed rows carry the FROZEN version's demographics, unassessed/current
 *          rows the current version's — same source row as the rest of the attribution.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION (restores the documented design; server-side
 *          patch under 1.3.0), CYCLE-SCOPED: when @CycleGroupID is set, a row WITH a result attributes
 *          School/Grade/Homeroom from the RESULT's frozen DimStudent version (fact.StudentKey — the
 *          version in force when it was recorded), NOT the student's current version — so a transfer
 *          no longer moves recorded history to the new school, and a district leaver keeps their
 *          recorded results in the cycles where they were assessed; a student with NO result in that
 *          cycle shows from their CURRENT version ("No data", current+enrolled only), and the access
 *          gate follows the ATTRIBUTED school. With NO cycle selected (the "Current" view) everything
 *          anchors on the CURRENT version, as before. Non-movers are unchanged (frozen = current).
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
    -- Expected reading languages per student (cycle-scoped; config-derived from mapped-course
    -- enrolment — see StudentExpectedAssessment), as the reading ScaleSystem the facts carry.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber,
               CASE sea.Language WHEN 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, an assessed row attributes to the RESULT's
    -- frozen student version (the school/grade/homeroom that recorded it — includes movers' old-school
    -- rows and district leavers); with NO cycle selected (the "Current" view) every row anchors on the
    -- CURRENT version, as before — the current view reflects the schools as they are today. A
    -- non-mover's frozen version IS their current version — identical output either way.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed (tvf_StudentCohort's LangSet union): an
    -- expected language with no result emits an IsExpectedOnly row from the CURRENT version (there is
    -- no result to attribute by); the NULL-language fallback fires only when neither expected nor
    -- assessed. The NOT EXISTS probes hit the fact directly — cheaper than re-running LatestReading
    -- (Fabric inlines a CTE at every reference).
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lr.ScaleSystem, lr.AssessmentDate, lr.ReadingDelta, CAST(0 AS BIT) AS IsExpectedOnly
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lr3.ScaleSystem, lr3.AssessmentDate, lr3.ReadingDelta, CAST(0 AS BIT)
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.ScaleSystem, CAST(NULL AS DATE), CAST(NULL AS INT), CAST(1 AS BIT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx
                          INNER JOIN DimReadingScale dx ON dx.ReadingScaleID = fx.ReadingScaleID
                          WHERE fx.StudentNumber = s.StudentNumber AND dx.ScaleSystem = el.ScaleSystem
                            AND fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(20)), CAST(NULL AS DATE), CAST(NULL AS INT), CAST(0 AS BIT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,   -- homeroom expansion key (per-group detail)
        b.SchoolID,
        sch.SchoolName,
        b.Gender,                                           -- summary-view demographic filters (2026-11-10)
        b.SelfIDAfrican,
        b.SelfIDIndigenous,
        ipp.IsIPP                         AS ReadingIPPStatus,
        b.ScaleSystem,                                      -- language of THIS row; NULL = neither expected nor assessed
        b.AssessmentDate                  AS AssessmentDate, -- date of THIS latest result (drives the by-cycle trend); NULL = no result
        dal.AchievementLevelCode          AS AchievementLevelCode, -- band for THIS result; NULL = none/IPP/unresolved
        b.IsExpectedOnly                  AS IsExpectedOnly  -- 1 = expected in this language, no result yet (counts the student, not a result)
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
/*******************************************************************************
 * Function: tvf_StudentCohortWritingAll  (INLINE table-valued function)
 * Purpose: READ-ONLY feed for the Reports > Writing OVERSIGHT roll-up tree (1.3.0 reports rebuild).
 *          Writing counterpart of tvf_StudentCohortReadingAll: one row per in-scope student PER WRITING
 *          LANGUAGE, carrying the achievement band of that language's latest writing AVERAGE (for the
 *          client's % Meeting/Exceeding) + the language so the display shows distinct STUDENTS vs RESULTS
 *          per language (EN/FR) + overall. Counts/measure only — no names (the per-group detail loads
 *          separately on expand).
 * Created: 2026-10-16
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortReadingAll (see
 *          its header): language set = expected (StudentExpectedAssessment, Writing) UNION assessed;
 *          an expected language with no result emits an IsExpectedOnly=1 row (NULL date/traits/avg);
 *          the NULL-language fallback fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters), in lockstep with tvf_StudentCohortReadingAll.
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
    -- Expected writing languages per student (cycle-scoped; config-derived — StudentExpectedAssessment).
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber, sea.Language
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED: with a cycle selected, assessed rows come from the RESULT's frozen
    -- student version (includes movers' old-school rows and district leavers) and unassessed rows are
    -- CURRENT, enrolled students ("No data" at their current school); with NO cycle (the "Current"
    -- view) everything anchors on the current version, as before.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed (tvf_StudentCohort's LangSet union): an
    -- expected language with no result emits an IsExpectedOnly row from the CURRENT version; the
    -- NULL-language fallback fires only when neither expected nor assessed. The NOT EXISTS probes hit
    -- the fact directly — cheaper than re-running LatestWriting (Fabric inlines a CTE per reference).
    Base AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.Grade, fv.Homeroom, fv.GroupKey, fv.SchoolID,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lw.AssessmentLanguage, lw.AssessmentDate,
               lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore, lw.ConventionsScore, lw.AvgScore,
               CAST(0 AS BIT) AS IsExpectedOnly
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lw3.AssessmentLanguage, lw3.AssessmentDate,
               lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore, lw3.ConventionsScore, lw3.AvgScore,
               CAST(0 AS BIT)
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.Language, CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2)),
               CAST(1 AS BIT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx
                          WHERE fx.StudentNumber = s.StudentNumber
                            AND fx.AssessmentLanguage = el.Language
                            AND fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.Grade, s.Homeroom, s.GroupKey, s.SchoolID,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DATE),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2)),
               CAST(0 AS BIT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    )
    SELECT
        CAST(b.StudentKey AS VARCHAR(20)) AS StudentKey,
        b.Grade,
        b.Homeroom,
        b.GroupKey                        AS HomeroomKey,
        b.SchoolID,
        sch.SchoolName,
        b.Gender,                                            -- summary-view demographic filters (2026-11-10)
        b.SelfIDAfrican,
        b.SelfIDIndigenous,
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
             ELSE 1 END                   AS AchievementLevelCode,
        b.IsExpectedOnly                  AS IsExpectedOnly  -- 1 = expected in this language, no result yet (counts the student, not a result)
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
/*******************************************************************************
 * Function: tvf_StudentCohortReadingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP reading detail for the Reports > Reading roll-up tree (1.3.0, Slice 1b).
 *          Loaded on demand when a Grade / Homeroom node is expanded — the individual students in that
 *          group with their LATEST reading level + achievement band PER LANGUAGE (EN/FR). One row per
 *          (student x reading-result language) + a NULL-language row for a student with no reading
 *          result (so they show as "No data"). The client pivots to one row per student (EN + FR cells).
 * Created: 2026-10-16
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortReadingAll (see
 *          its header): an expected language (StudentExpectedAssessment) with no result emits a row
 *          with ScaleSystem set and NULL level/delta, so the drill under a Language of Assessment
 *          filter shows expected-but-unassessed students as "—" instead of dropping them; the
 *          NULL-language "No data" row fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters: the drill table must match the filtered node counts above it).
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortReadingAll
 *          (see its header for the full rationale), CYCLE-SCOPED: with a cycle selected, an assessed
 *          row's School/Grade/Homeroom (and so its @GroupKey membership) comes from the RESULT's frozen
 *          DimStudent version and the oversight gate follows the ATTRIBUTED school; unassessed rows
 *          stay current students. With no cycle ("Current" view) everything anchors on the current
 *          version, as before. Display names come from the student's CURRENT version when one exists
 *          (people keep their current name), falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same OR-across-EXISTS gate as tvf_StudentCohortMath (oversight via
 * StaffSchoolAccess against the ATTRIBUTED school; teacher via FactSectionTeachers — kept for parity
 * though the reading tree is oversight-only; the teacher branch remains current-roster, so it never
 * surfaces a departed student). @GroupKey shapes: 'GRADE:<SchoolID>:<Grade>', 'SEC:<SectionID>', else a
 * homeroom DimStudent.GroupKey — matched against the ATTRIBUTED version's values, so the drill's rows
 * agree with the roll-up's counts. Students restricted to the selected Reading windows' grade span.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortReadingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortReadingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (
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
    GradeSpan AS (
        SELECT MIN(gmin.GradeOrder) AS MinOrd, MAX(gmax.GradeOrder) AS MaxOrd
        FROM ReadWins rw
        INNER JOIN DimGrade gmin ON gmin.GradeCode = rw.MinGrade
        INNER JOIN DimGrade gmax ON gmax.GradeCode = rw.MaxGrade
    ),
    -- Effective benchmark month per selected reading window (BenchmarkMonth, else dominant calendar
    -- month) — matched against DimReadingBenchmark for the Expected range (mirrors tvf_StudentCohort).
    WindowMonth AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w
        WHERE w.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    LatestReading AS (   -- latest result per (student, language) across the selected windows.
        -- far.StudentKey is the FROZEN version the result was recorded against — the attribution.
        SELECT far.StudentNumber, far.StudentKey AS FactStudentKey, far.AssessmentWindowID,
               drs.ScaleSystem, drs.LevelCode, drs.LevelOrder, far.ReadingDelta,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber, drs.ScaleSystem
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        INNER JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
        WHERE far.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins)
    ),
    ReadingIPP AS (    -- keyed by StudentNumber (frozen StudentKeys predate IPP repointing)
        SELECT dsi.StudentNumber, MAX(CAST(fsi.IsIPP AS INT)) AS IsIPP
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent dsi ON dsi.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Reading'
        GROUP BY dsi.StudentNumber
    ),
    -- Expected reading languages per student (cycle-scoped) — see StudentExpectedAssessment.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber,
               CASE sea.Language WHEN 'French' THEN 'FR_Reading' ELSE 'EN_Reading' END AS ScaleSystem
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Reading'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortReadingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed, in lockstep with the *All feed.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lr.AssessmentWindowID, lr.ScaleSystem, lr.LevelCode, lr.LevelOrder, lr.ReadingDelta
        FROM LatestReading lr
        INNER JOIN DimStudent fv ON fv.StudentKey = lr.FactStudentKey
        WHERE lr.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lr3.AssessmentWindowID, lr3.ScaleSystem, lr3.LevelCode, lr3.LevelOrder, lr3.ReadingDelta
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestReading WHERE rn = 1) lr3 ON lr3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS BIGINT), el.ScaleSystem, CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx
                          INNER JOIN DimReadingScale dx ON dx.ReadingScaleID = fx.ReadingScaleID
                          WHERE fx.StudentNumber = s.StudentNumber AND dx.ScaleSystem = el.ScaleSystem
                            AND fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS BIGINT), CAST(NULL AS VARCHAR(20)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS INT), CAST(NULL AS INT)
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM ReadWins))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    ),
    -- The group's attributed rows (in the reading grade span), intersected with the caller's scope.
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,
               a.AssessmentWindowID, a.ScaleSystem, a.LevelCode, a.LevelOrder, a.ReadingDelta
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        gs.Gender,                                    -- summary-view demographic filters (2026-11-10)
        gs.SelfIDAfrican,
        gs.SelfIDIndigenous,
        ipp.IsIPP                 AS ReadingIPPStatus,
        gs.ScaleSystem,                               -- language of THIS result; NULL = no reading result
        gs.LevelCode,                                 -- the reading level (e.g. 'M'); NULL = no result
        gs.LevelOrder,
        gs.ReadingDelta,                              -- signed difference from the expected benchmark
        drb.ExpectedMinLevel      AS ExpectedMinLevel, -- expected benchmark range for THIS result's language
        drb.ExpectedMaxLevel      AS ExpectedMaxLevel,
        expMin.LevelOrder         AS ExpectedMinOrder, -- order of ExpectedMinLevel (for sorting the Expected column)
        sp.StartingLevelCode      AS JuneReadingLevel,  -- prior-June starting level (same language); parity with the flat list
        CASE WHEN gs.LevelOrder IS NOT NULL AND jrs.LevelOrder IS NOT NULL
             THEN gs.LevelOrder - jrs.LevelOrder END AS DiffFromPrevJune,  -- signed growth since prior June
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- cell-background tint (coloured cell, not text)
    FROM GroupStudents gs
    LEFT JOIN ReadingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    -- Expected benchmark range for THIS result's window month + the language's family (EN_Reading ->
    -- English, FR_Reading -> French Immersion), so a French result shows the French expectation.
    LEFT JOIN WindowMonth wm ON wm.AssessmentWindowID = gs.AssessmentWindowID
    LEFT JOIN DimReadingBenchmark drb
           ON drb.GradeCode       = gs.Grade
          AND drb.AssessmentMonth = wm.BenchMonth
          AND drb.ProgramFamily   = CASE gs.ScaleSystem WHEN 'EN_Reading' THEN 'English'
                                                         WHEN 'FR_Reading' THEN 'French Immersion' END
    LEFT JOIN DimReadingScale expMin
           ON expMin.LevelCode  = drb.ExpectedMinLevel
          AND expMin.ScaleSystem = gs.ScaleSystem
    -- Prior-June starting point for THIS result's language (mirrors tvf_StudentCohort) → Diff from Prev June.
    LEFT JOIN dbo.vw_StudentReadingStartingPoint sp
           ON sp.StudentNumber = gs.StudentNumber AND sp.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimReadingScale jrs
           ON jrs.LevelCode = sp.StartingLevelCode AND jrs.ScaleSystem = gs.ScaleSystem
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.ReadingDelta IS NOT NULL
          AND (dal.LowerBound IS NULL
               OR (dal.LowerOp = '>=' AND gs.ReadingDelta >= dal.LowerBound)
               OR (dal.LowerOp = '>'  AND gs.ReadingDelta >  dal.LowerBound)
               OR (dal.LowerOp = '='  AND gs.ReadingDelta =  dal.LowerBound))
          AND (dal.UpperBound IS NULL
               OR (dal.UpperOp = '<=' AND gs.ReadingDelta <= dal.UpperBound)
               OR (dal.UpperOp = '<'  AND gs.ReadingDelta <  dal.UpperBound)
               OR (dal.UpperOp = '='  AND gs.ReadingDelta =  dal.UpperBound))
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortReadingGroup] TO [StudentDataAssessment];
GO
/*******************************************************************************
 * Function: tvf_StudentCohortWritingGroup  (INLINE table-valued function)
 * Purpose: READ-ONLY per-GROUP writing detail for the Reports > Writing roll-up tree (1.3.0, Slice 2).
 *          Loaded when a Grade / Homeroom node is expanded — the individual students in that group with
 *          their LATEST writing FOUR TRAIT scores + average + achievement band, PER LANGUAGE (EN/FR).
 *          One row per (student x writing language) + a NULL-language row for a student with no writing
 *          result. The client renders one row per (student, language) with the four traits in COIL order.
 * Created: 2026-10-16
 * Modified: 2026-11-12 — EXPECTED-LANGUAGE rows, in lockstep with tvf_StudentCohortWritingAll (see
 *          the reading All header for the rationale): an expected language (StudentExpectedAssessment)
 *          with no result emits a row with the language set and NULL traits/avg, so the drill under a
 *          Language of Assessment filter shows expected-but-unassessed students as "—" instead of
 *          dropping them; the NULL-language row fires only when neither expected nor assessed.
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (summary-view demographic
 *          filters: the drill table must match the filtered node counts above it).
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohortWritingAll /
 *          tvf_StudentCohortReadingAll (see the reading All header for the full rationale), CYCLE-
 *          SCOPED: with a cycle selected, an assessed row's School/Grade/Homeroom (and so its @GroupKey
 *          membership) comes from the RESULT's frozen DimStudent version and the oversight gate follows
 *          the ATTRIBUTED school; unassessed rows stay current students. With no cycle ("Current" view)
 *          everything anchors on the current version, as before. Display names come from the student's
 *          CURRENT version when one exists, falling back to the frozen name for district leavers.
 * Region: Canada East (PIIDPA compliant)
 *
 * Group-scoped + @UPN-scoped: same @GroupKey shapes + OR-across-EXISTS gate as tvf_StudentCohortMath /
 * tvf_StudentCohortReadingGroup, matched on the ATTRIBUTED version's values. Average counts ONLY explicit
 * '1'-'4' traits (SCR / '-' / NULL dropped); band CODE by the writing cut scores (reused name + colour
 * from DimAchievementLevel by code).
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWritingGroup;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWritingGroup(@UPN VARCHAR(255), @GroupKey VARCHAR(70), @CycleGroupID VARCHAR(36) = NULL)
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
    LatestWriting AS (   -- latest result per (student, language); faw.StudentKey = the FROZEN version
        SELECT faw.StudentNumber, faw.StudentKey AS FactStudentKey, faw.AssessmentLanguage,
               faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore,
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
    -- Expected writing languages per student (cycle-scoped) — see StudentExpectedAssessment.
    ExpectedLang AS (
        SELECT DISTINCT sea.StudentNumber, sea.Language
        FROM StudentExpectedAssessment sea
        WHERE sea.AssessmentType = 'Writing'
          AND (@CycleGroupID IS NULL OR sea.CycleGroupID = @CycleGroupID)
    ),
    -- ATTRIBUTION IS CYCLE-SCOPED (mirrors tvf_StudentCohortWritingAll's Base so drill rows agree with
    -- roll-up counts): cycle selected -> assessed rows from the result's frozen version, unassessed from
    -- the current version; no cycle ("Current" view) -> everything anchors on the current version.
    -- LANGUAGE SET (2026-11-12) = expected UNION assessed, in lockstep with the *All feed.
    AttrStudents AS (
        -- cycle selected, assessed: attributed by that result's frozen version
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.Homeroom,
               fv.SchoolID, fv.GroupKey AS HomeroomKey,
               fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous,
               lw.AssessmentLanguage, lw.IdeasScore, lw.OrganizationScore, lw.LanguageScore,
               lw.ConventionsScore, lw.AvgScore
        FROM LatestWriting lw
        INNER JOIN DimStudent fv ON fv.StudentKey = lw.FactStudentKey
        WHERE lw.rn = 1 AND @CycleGroupID IS NOT NULL
        UNION ALL
        -- no cycle ("Current"): current students with their per-language latest (original semantics)
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               lw3.AssessmentLanguage, lw3.IdeasScore, lw3.OrganizationScore, lw3.LanguageScore,
               lw3.ConventionsScore, lw3.AvgScore
        FROM DimStudent s
        INNER JOIN (SELECT * FROM LatestWriting WHERE rn = 1) lw3 ON lw3.StudentNumber = s.StudentNumber
        WHERE @CycleGroupID IS NULL
          AND s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
        UNION ALL
        -- expected language with NO result in it (either cycle mode): current, enrolled students
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               el.Language, CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        INNER JOIN ExpectedLang el ON el.StudentNumber = s.StudentNumber
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx
                          WHERE fx.StudentNumber = s.StudentNumber
                            AND fx.AssessmentLanguage = el.Language
                            AND fx.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins))
        UNION ALL
        -- neither expected nor assessed (either cycle mode): one NULL-language "No data" row
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.Homeroom,
               s.SchoolID, s.GroupKey,
               s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous,
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)),
               CAST(NULL AS VARCHAR(10)), CAST(NULL AS VARCHAR(10)), CAST(NULL AS DECIMAL(5,2))
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting fx2
                          WHERE fx2.StudentNumber = s.StudentNumber
                            AND fx2.AssessmentWindowID IN (SELECT AssessmentWindowID FROM WriteWins))
          AND NOT EXISTS (SELECT 1 FROM ExpectedLang el2 WHERE el2.StudentNumber = s.StudentNumber)
    ),
    GroupStudents AS (
        SELECT a.StudentKey, a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName) AS FirstName,   -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)  AS LastName,    -- frozen name for district leavers
               a.Grade, a.Homeroom, a.SchoolID, sch.SchoolName,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous,
               a.AssessmentLanguage, a.IdeasScore, a.OrganizationScore, a.LanguageScore,
               a.ConventionsScore, a.AvgScore
        FROM AttrStudents a
        INNER JOIN DimGrade g ON g.GradeCode = a.Grade
        CROSS JOIN GradeSpan gs
        LEFT  JOIN DimSchool sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE g.GradeOrder BETWEEN gs.MinOrd AND gs.MaxOrd
          -- group membership by @GroupKey shape, matched on the ATTRIBUTED version's values
          AND (
                (LEFT(@GroupKey, 6) = 'GRADE:' AND 'GRADE:' + a.SchoolID + ':' + a.Grade = @GroupKey)
             OR (LEFT(@GroupKey, 4) = 'SEC:' AND EXISTS (
                     SELECT 1 FROM FactEnrollment e
                     INNER JOIN DimSection sec ON sec.SectionKey = e.SectionKey AND sec.IsCurrent = 1
                     WHERE e.StudentKey = a.StudentKey AND e.ActiveFlag = 1 AND 'SEC:' + sec.SectionID = @GroupKey))
             OR (LEFT(@GroupKey, 6) <> 'GRADE:' AND LEFT(@GroupKey, 4) <> 'SEC:' AND a.HomeroomKey = @GroupKey)
          )
          -- caller scope gate (oversight via StaffSchoolAccess against the ATTRIBUTED school
          -- OR teacher via FactSectionTeachers — current roster, unchanged)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1
                        FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec2 ON sec2.SectionID = fst.SectionID AND sec2.IsCurrent = 1
                        INNER JOIN FactEnrollment e2 ON e2.SectionKey = sec2.SectionKey AND e2.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e2.StudentKey = a.StudentKey)
          )
    )
    SELECT
        CAST(gs.StudentKey AS VARCHAR(20)) AS StudentKey,
        gs.StudentNumber,
        gs.FirstName,
        gs.LastName,
        gs.Grade,
        gs.Homeroom,
        gs.SchoolName,
        gs.Gender,                                 -- summary-view demographic filters (2026-11-10)
        gs.SelfIDAfrican,
        gs.SelfIDIndigenous,
        ipp.IsIPP                 AS WritingIPPStatus,
        gs.AssessmentLanguage,                     -- 'English' | 'French'; NULL = no writing result
        gs.IdeasScore,
        gs.OrganizationScore,
        gs.LanguageScore,
        gs.ConventionsScore,
        gs.AvgScore,
        dal.AchievementLevelCode  AS AchievementLevelCode,
        dal.AchievementLevelName  AS AchievementLevelName,
        dal.HexColor              AS AchievementHexColor,
        dal.HexColorTint          AS AchievementHexColorTint  -- Avg-cell background tint (parity with the flat list)
    FROM GroupStudents gs
    LEFT JOIN WritingIPP ipp ON ipp.StudentNumber = gs.StudentNumber
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND gs.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN gs.AvgScore >= 3.50 THEN 4
                   WHEN gs.AvgScore >= 2.75 THEN 3
                   WHEN gs.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWritingGroup] TO [StudentDataAssessment];
GO
/*******************************************************************************
 * Function: tvf_StudentCohortRWM  (INLINE table-valued function)
 * Purpose: READ-ONLY Reading·Writing·Math achievement roll-up for Reports > RWM
 *          (0.7.0, item 5). One row per in-scope Primary-6 student with a 0-3 score:
 *          how many of {Reading, Writing, Math} the student is CURRENTLY meeting or
 *          exceeding (their most-recent result in each area).
 * Created: 2026-09-24
 * Modified: 2026-11-10 — + Gender / SelfIDAfrican / SelfIDIndigenous (RWM Summary tree's filter
 *          section, in lockstep with the Reading/Writing *All TVFs). Attributed rows carry the
 *          FROZEN version's demographics, unassessed/current rows the current version's.
 * Modified: 2026-10-30 — HISTORICAL SCHOOL ATTRIBUTION, in lockstep with tvf_StudentCohort (full
 *          rationale in tvf_StudentCohortReadingAll), CYCLE-SCOPED: with a cycle selected, a student
 *          WITH any R/W/M result in it takes their demographics from the frozen DimStudent version of
 *          their MOST RECENT result across the three subjects in that cycle (one attribution per
 *          student) and the scope gate follows the ATTRIBUTED school; students with no result stay
 *          current students. With NO cycle (the "Current" view) everything anchors on the current
 *          version, as before. Names + the emitted StudentKey (detail link) prefer the CURRENT
 *          version. AnyIPP is keyed by StudentNumber (frozen keys predate IPP repointing).
 * Region: Canada East (PIIDPA compliant)
 *
 * "Meeting+" per area:
 *   Reading  - most-recent FactAssessmentReading delta -> DimAchievementLevel code IN (3,4).
 *   Writing  - most-recent FactAssessmentWriting trait average -> band code IN (3,4)
 *              (same cut scores as tvf_StudentCohortWriting: avg >= 2.75).
 *   Math     - current-year roll-up = AVERAGE of the student's per-unit averages
 *              (unit avg = AVG(Result) over recorded tasks; blanks are absent rows, so
 *              already excluded) >= 0.75 (Meeting / In-depth).
 *
 * SCOPE: P-6 only (math is P-6; the whole score is defined P-6). EXCLUDES any student
 * with a CONFIRMED IPP (IsIPP = 1) in Reading, Writing, OR Math -- an IPP student is on an
 * individualized plan and isn't measured against these benchmarks. @UPN role gate is the
 * same OR-across-EXISTS branch as the other cohort TVFs (analyst/admin via StaffSchoolAccess;
 * teacher via FactSectionTeachers) -- NO region-wide branch.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortRWM;
GO

CREATE FUNCTION dbo.tvf_StudentCohortRWM(@UPN VARCHAR(255), @CycleGroupID VARCHAR(36) = NULL)
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        -- @CycleGroupID (2026-10-07): NULL = all current-year math windows; a cycle id narrows to that cycle's Math window(s).
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND (@CycleGroupID IS NULL OR w.CycleGroupID = @CycleGroupID)
    ),
    -- Cycle-scoped attribution source: the student's most recent result across R/W/M in the selected
    -- cycle, whose frozen StudentKey supplies the demographics. Empty when no cycle is selected.
    AnyTouch AS (
        SELECT x.StudentNumber, x.StudentKey,
               ROW_NUMBER() OVER (PARTITION BY x.StudentNumber
                                  ORDER BY x.AssessmentDate DESC, x.LastUpdated DESC) AS rn
        FROM (
            SELECT far.StudentNumber, far.StudentKey, far.AssessmentDate, far.LastUpdated
            FROM FactAssessmentReading far
            WHERE @CycleGroupID IS NOT NULL
              AND far.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT faw.StudentNumber, faw.StudentKey, faw.AssessmentDate, faw.LastUpdated
            FROM FactAssessmentWriting faw
            WHERE @CycleGroupID IS NOT NULL
              AND faw.AssessmentWindowID IN (
                    SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                    WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
            UNION ALL
            SELECT fm.StudentNumber, fm.StudentKey, fm.AssessmentDate, fm.LastUpdated
            FROM FactAssessmentMath fm
            WHERE @CycleGroupID IS NOT NULL
              AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
        ) x
    ),
    -- WHO appears + WHICH DimStudent version supplies the demographics (cycle-scoped attribution).
    AttrBase AS (
        -- cycle selected, assessed: the frozen version of the student's most recent R/W/M result
        SELECT fv.StudentKey, fv.StudentNumber, fv.FirstName, fv.LastName, fv.Grade, fv.SchoolID,
               fv.ProgramCode, fv.Homeroom, fv.Gender, fv.SelfIDAfrican, fv.SelfIDIndigenous
        FROM AnyTouch t
        INNER JOIN DimStudent fv ON fv.StudentKey = t.StudentKey
        WHERE t.rn = 1
        UNION ALL
        -- current students: ALL of them with no cycle selected; the unassessed ones with a cycle
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, s.SchoolID,
               s.ProgramCode, s.Homeroom, s.Gender, s.SelfIDAfrican, s.SelfIDIndigenous
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
          AND (@CycleGroupID IS NULL
               OR NOT EXISTS (SELECT 1 FROM AnyTouch t2 WHERE t2.StudentNumber = s.StudentNumber))
    ),
    -- In-scope, attributed, P-5 students (role-gated against the ATTRIBUTED school).
    InScope AS (
        SELECT COALESCE(cur.StudentKey, a.StudentKey) AS StudentKey,   -- detail link only (prefer the live record)
               a.StudentNumber,
               COALESCE(cur.FirstName, a.FirstName)   AS FirstName,    -- current name when one exists;
               COALESCE(cur.LastName,  a.LastName)    AS LastName,     -- frozen name for district leavers
               a.Grade, sg.GradeOrder,
               a.SchoolID, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation,
               a.ProgramCode, p.ProgramFamily, a.Homeroom,
               a.Gender, a.SelfIDAfrican, a.SelfIDIndigenous
        FROM AttrBase a
        INNER JOIN DimProgram p  ON p.ProgramCode = a.ProgramCode
        INNER JOIN DimGrade   sg ON sg.GradeCode  = a.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = a.SchoolID
        LEFT  JOIN DimStudent cur ON cur.StudentNumber = a.StudentNumber AND cur.IsCurrent = 1
        WHERE sg.GradeOrder BETWEEN 0 AND 5  -- RWM P..5 (grade 6 math not ready 2026-27)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = a.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = a.StudentKey)
          )
    ),
    -- Any confirmed IPP in ANY of the three subjects removes the student from this report.
    -- Keyed by StudentNumber (2026-10-30): an attributed row carries a frozen StudentKey, which the
    -- IPP rows' current-version repointing no longer matches.
    AnyIPP AS (
        SELECT DISTINCT ds.StudentNumber
        FROM FactStudentIPP fsi
        INNER JOIN DimStudent ds ON ds.StudentKey = fsi.StudentKey
        WHERE fsi.IsCurrent = 1 AND fsi.IsIPP = 1 AND fsi.Subject IN ('Reading', 'Writing', 'Math')
    ),
    -- Most-recent reading -> achievement code (delta mapped through DimAchievementLevel bounds).
    ReadLatest AS (
        SELECT far.StudentNumber, far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentNumber
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Reading window(s).
        WHERE @CycleGroupID IS NULL
           OR far.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1)
    ),
    ReadAch AS (
        SELECT rl.StudentNumber, dal.AchievementLevelCode AS Code
        FROM ReadLatest rl
        LEFT JOIN DimAchievementLevel dal
               ON dal.ActiveFlag = 1
              AND rl.ReadingDelta IS NOT NULL
              AND (dal.LowerBound IS NULL
                   OR (dal.LowerOp = '>=' AND rl.ReadingDelta >= dal.LowerBound)
                   OR (dal.LowerOp = '>'  AND rl.ReadingDelta >  dal.LowerBound)
                   OR (dal.LowerOp = '='  AND rl.ReadingDelta =  dal.LowerBound))
              AND (dal.UpperBound IS NULL
                   OR (dal.UpperOp = '<=' AND rl.ReadingDelta <= dal.UpperBound)
                   OR (dal.UpperOp = '<'  AND rl.ReadingDelta <  dal.UpperBound)
                   OR (dal.UpperOp = '='  AND rl.ReadingDelta =  dal.UpperBound))
        WHERE rl.rn = 1
    ),
    -- Most-recent writing -> trait average -> band code (same cut scores as tvf_StudentCohortWriting).
    -- Traits are VARCHAR: count one ONLY when it is explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
    -- all drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
    -- would hard-CAST '-' and error — so gate on the explicit allow-list.
    WriteLatest AS (
        SELECT faw.StudentNumber,
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
               ROW_NUMBER() OVER (PARTITION BY faw.StudentNumber
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
        -- @CycleGroupID: NULL = lifetime latest; a cycle id scopes to that cycle's Writing window(s).
        WHERE @CycleGroupID IS NULL
           OR faw.AssessmentWindowID IN (
                SELECT w.AssessmentWindowID FROM DimAssessmentWindow w
                WHERE w.CycleGroupID = @CycleGroupID AND w.AssessmentType = 'Writing' AND w.ActiveFlag = 1)
    ),
    WriteAch AS (
        SELECT wl.StudentNumber,
               CASE WHEN wl.AvgScore IS NULL   THEN NULL
                    WHEN wl.AvgScore >= 3.50   THEN 4
                    WHEN wl.AvgScore >= 2.75   THEN 3
                    WHEN wl.AvgScore >= 1.75   THEN 2
                    ELSE 1 END AS Code
        FROM WriteLatest wl WHERE wl.rn = 1
    ),
    -- Math roll-up: latest result per task (current-year windows) -> per-unit avg -> avg of unit avgs.
    MathLatest AS (
        SELECT fm.StudentNumber, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentNumber, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathUnit AS (
        SELECT ml.StudentNumber, mt.UnitName, AVG(CAST(ml.Result AS FLOAT)) AS UnitAvg
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.UnitName
    ),
    MathRoll AS (   -- blanks EXCLUDED: unit avg over recorded tasks only
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathUnit GROUP BY StudentNumber
    ),
    -- blanks COUNT-AS-0: denominator = every configured task for the grade's units this year, so an
    -- un-recorded task counts as a miss. Universe = active tasks at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
    ),
    MathUnitOnes AS (   -- recorded 1s per (student, unit)
        SELECT ml.StudentNumber, mt.GradeCode, mt.UnitName, SUM(CAST(ml.Result AS INT)) AS Ones
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentNumber, mt.GradeCode, mt.UnitName
    ),
    MathZeroUnit AS (   -- one row per (student, configured unit): ones / configured (fully-blank unit = 0)
        SELECT isc.StudentNumber,
               CAST(COALESCE(mo.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
        FROM InScope isc
        INNER JOIN TaskUniverse tu ON tu.GradeCode = isc.Grade
        LEFT  JOIN MathUnitOnes mo ON mo.StudentNumber = isc.StudentNumber AND mo.GradeCode = isc.Grade AND mo.UnitName = tu.UnitName
    ),
    MathZeroRoll AS (
        SELECT StudentNumber, AVG(UnitAvg) AS RollupPct FROM MathZeroUnit GROUP BY StudentNumber
    )
    SELECT
        CAST(isc.StudentKey AS VARCHAR(20))            AS StudentKey,
        isc.StudentNumber,
        isc.FirstName,
        isc.LastName,
        isc.FirstName + ' ' + isc.LastName             AS FullName,
        isc.Grade,
        isc.GradeOrder,
        isc.SchoolID,
        isc.SchoolName,
        isc.SchoolAbbreviation,
        isc.ProgramCode,
        isc.ProgramFamily,
        isc.Homeroom,
        isc.Gender,
        isc.SelfIDAfrican,
        isc.SelfIDIndigenous,
        ra.Code                                        AS ReadingCode,
        wa.Code                                        AS WritingCode,
        CAST(mr.RollupPct AS DECIMAL(5,4))             AS MathRollupPct,      -- blanks excluded
        CAST(mz.RollupPct AS DECIMAL(5,4))             AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS ReadingMeeting,
        CAST(CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS WritingMeeting,
        CAST(CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)       AS MathMeeting,
        -- 0-3: how many areas are currently meeting/exceeding.
        (CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END)               AS RWMScore,
        -- "has any evidence" per area, so the UI can tell "not meeting" from "no result yet".
        CAST(CASE WHEN ra.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasReading,
        CAST(CASE WHEN wa.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasWriting,
        CAST(CASE WHEN mr.StudentNumber IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasMath
    FROM InScope isc
    LEFT JOIN ReadAch   ra ON ra.StudentNumber = isc.StudentNumber
    LEFT JOIN WriteAch  wa ON wa.StudentNumber = isc.StudentNumber
    LEFT JOIN MathRoll  mr ON mr.StudentNumber = isc.StudentNumber
    LEFT JOIN MathZeroRoll mz ON mz.StudentNumber = isc.StudentNumber
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentNumber = isc.StudentNumber)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO
