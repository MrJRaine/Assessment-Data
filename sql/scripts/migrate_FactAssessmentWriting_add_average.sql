/*******************************************************************************
 * Script: migrate_FactAssessmentWriting_add_average.sql
 * Purpose: Store the SCR-aware writing AVERAGE on each FactAssessmentWriting row,
 *          stamped as-was, so the "Scribed drops from the average" rule lives in
 *          the DATA and can't be re-derived wrong later (or disagree with a
 *          report that recomputes it). Conventions='SCR' drops from BOTH the
 *          numerator and the denominator; Ideas/Org/Language are 1-4.
 *
 * Created: 2026-09-21
 * Region:  Canada East (PIIDPA compliant)
 *
 * WHEN TO RUN:
 *   - DEV: yes — the table already exists (with test rows) and lacks the column.
 *   - LIVE: run the ALTER only if FactAssessmentWriting ALREADY EXISTS on live
 *     WITHOUT this column. If 0.5.0 creates FactAssessmentWriting FRESH on live
 *     (the CREATE now includes WritingAverage), SKIP the ALTER and run only the
 *     backfill UPDATE below — it no-ops on an empty table. (Confirm the live
 *     state before the deploy.)
 *
 * RUN ONCE per environment: the ALTER errors if the column already exists. The
 * backfill UPDATE is safe to re-run (it re-writes the same values).
 ******************************************************************************/

ALTER TABLE FactAssessmentWriting
    ADD WritingAverage DECIMAL(4,2) NULL;
GO

-- Backfill from the stored trait scores, exactly as usp_UpsertWritingAssessment now computes it:
-- TRY_CAST turns 'SCR' into NULL so it drops from the mean; the denominator is 3 (+1 when
-- Conventions is numeric). Guarded to complete rows (all three numeric traits present) — incomplete
-- rows should not exist, but this keeps the average NULL rather than wrong if one slipped through.
UPDATE FactAssessmentWriting
SET WritingAverage =
        CAST(IdeasScore + OrganizationScore + LanguageScore
             + COALESCE(TRY_CAST(ConventionsScore AS INT), 0) AS DECIMAL(6,4))
        / (3 + CASE WHEN TRY_CAST(ConventionsScore AS INT) IS NULL THEN 0 ELSE 1 END)
WHERE IdeasScore IS NOT NULL
  AND OrganizationScore IS NOT NULL
  AND LanguageScore IS NOT NULL;
GO

-- Verify.
SELECT
    'rows'                    AS Metric, COUNT(*)                     AS Value FROM FactAssessmentWriting
UNION ALL SELECT 'with WritingAverage', COUNT(WritingAverage)        FROM FactAssessmentWriting
UNION ALL SELECT 'SCR rows (avg over 3)',
    SUM(CASE WHEN ConventionsScore = 'SCR' THEN 1 ELSE 0 END)        FROM FactAssessmentWriting;
