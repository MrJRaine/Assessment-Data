/*******************************************************************************
 * Script: diag_cohort_fanout_by_version_2026-10-15.sql   (LIVE — READ ONLY; StudentNumber only, no names)
 * Purpose: PROVE the duplication chain in ONE table, and test the hypothesis that the fan-out tracks
 *          how many times a student was SCD-versioned (how many StudentKeys they have). For every
 *          student the cohort returns more than once, lay out side by side:
 *            Versions      = # of DimStudent rows for that StudentNumber (SCD versions / StudentKeys)
 *            CurrentRows   = # with IsCurrent = 1  (should be 1; >1 = stacked-current base fan-out)
 *            BaselineRows  = # of PriorYearBaseline rows (all languages) for that student
 *            ViewRows      = # of rows vw_StudentReadingStartingPoint returns for that student (all scales)
 *            CohortRows    = # of rows tvf_StudentCohort ACTUALLY returns for that student  <-- ground truth
 *
 *          Read the correlation:
 *            - CohortRows tracks Versions  -> the baseline seed was emitted per StudentKey; the view
 *              collapse (already built) fixes it, because it forces 1 row per (StudentNumber, ScaleSystem).
 *            - CohortRows tracks BaselineRows but NOT Versions -> raw dup seed rows; same collapse fixes it.
 *            - CohortRows > ViewRows -> a SECOND server-side fan-out exists OUTSIDE the view (keep digging).
 *            - CohortRows = ViewRows = 2 but the PAGE shows 4 -> the extra x2 is client-side (webapp).
 *            - CurrentRows > 1 for anyone -> the base itself is fanning out (stacked IsCurrent markers).
 *
 * Reads:  DimStudent, PriorYearBaseline, vw_StudentReadingStartingPoint, tvf_StudentCohort (via @UPN).
 *         Returns StudentNumber + counts only (NO names). Authorized admin use, in-region.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * @UPN must be a RegionalAnalyst UPN so every student is in scope.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- a RegionalAnalyst UPN (sees all students)

;WITH ver AS (
    SELECT StudentNumber,
           COUNT(*)                                        AS Versions,
           SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END)  AS CurrentRows
    FROM DimStudent
    GROUP BY StudentNumber
),
base AS (
    SELECT StudentNumber, COUNT(*) AS BaselineRows
    FROM PriorYearBaseline
    WHERE ReadingLevel IS NOT NULL
    GROUP BY StudentNumber
),
vw AS (
    SELECT StudentNumber, COUNT(*) AS ViewRows
    FROM vw_StudentReadingStartingPoint
    GROUP BY StudentNumber
),
coh AS (
    SELECT StudentNumber, COUNT(*) AS CohortRows
    FROM dbo.tvf_StudentCohort(@UPN, NULL)
    GROUP BY StudentNumber
)
SELECT
    coh.StudentNumber,
    ver.Versions,
    ver.CurrentRows,
    base.BaselineRows,
    vw.ViewRows,
    coh.CohortRows
FROM coh
LEFT JOIN ver  ON ver.StudentNumber  = coh.StudentNumber
LEFT JOIN base ON base.StudentNumber = coh.StudentNumber
LEFT JOIN vw   ON vw.StudentNumber   = coh.StudentNumber
WHERE coh.CohortRows > 1
ORDER BY coh.CohortRows DESC, ver.Versions DESC, coh.StudentNumber;
GO
