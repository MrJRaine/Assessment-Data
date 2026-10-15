/*******************************************************************************
 * Script: diag_startingpoint_dup_source_2026-10-15.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: vw_StudentReadingStartingPoint returns 2 rows for 17 (StudentNumber, ScaleSystem) pairs,
 *          fanning out the reading cohort. Pin WHICH of two causes:
 *            (A) duplicate rows in the baseline seed (PriorYearBaseline) for a (student, language); OR
 *            (B) the view's final DimReadingScale join (bsrs) has NO ActiveFlag filter, so a baseline
 *                LevelCode that matches an ACTIVE *and* an INACTIVE scale row returns twice.
 *
 * Reads:  PriorYearBaseline, DimReadingScale. (A) counts dup baseline students (no names). No PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (A) Baseline seed duplicates per (StudentNumber, AssessmentLanguage).
SELECT 'PriorYearBaseline dup (student,language)' AS Check_,
       COUNT(*) AS DupPairs
FROM (
    SELECT StudentNumber, AssessmentLanguage
    FROM PriorYearBaseline
    WHERE ReadingLevel IS NOT NULL
    GROUP BY StudentNumber, AssessmentLanguage
    HAVING COUNT(*) > 1
) x;
GO

-- (B) DimReadingScale (ScaleSystem, LevelCode) duplicated across ALL rows (active + inactive) —
--     this is what the view's unfiltered bsrs join sees. ActiveRows<TotalRows = an inactive dup exists.
SELECT 'DimReadingScale dup incl inactive' AS Check_,
       ScaleSystem, LevelCode,
       COUNT(*)                                   AS TotalRows,
       SUM(CASE WHEN ActiveFlag = 1 THEN 1 ELSE 0 END) AS ActiveRows,
       SUM(CASE WHEN ActiveFlag = 0 THEN 1 ELSE 0 END) AS InactiveRows
FROM DimReadingScale
GROUP BY ScaleSystem, LevelCode
HAVING COUNT(*) > 1
ORDER BY TotalRows DESC;
GO
