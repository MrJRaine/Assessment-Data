/*******************************************************************************
 * Script: verify_selfcontained_facts.sql   (READ-ONLY)
 * Purpose: Confirm the reading + writing as-was backfills landed correctly.
 *          Run after migrate_FactAssessmentReading_add_score_context.sql and
 *          migrate_FactAssessmentWriting_add_average.sql. No writes.
 *
 * PASS = every "*_shouldBe0" column reads 0.
 * Created: 2026-09-21 · Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ===== READING: counts + the reconciliation check =====
-- DeltaSet_ExpectedNull must be 0: a row that has a delta must now carry the expected range the
-- delta was measured against (otherwise the row could contradict itself).
SELECT
    'READING' AS Fact,
    COUNT(*)                                                                 AS Rows_,
    COUNT(LevelCode)                                                         AS WithLevelCode,
    COUNT(ExpectedMinLevelCode)                                              AS WithExpectedRange,
    SUM(CASE WHEN ReadingDelta IS NOT NULL AND ExpectedMinLevelCode IS NULL
             THEN 1 ELSE 0 END)                                              AS DeltaSet_ExpectedNull_shouldBe0
FROM FactAssessmentReading;

-- Reading sample — eyeball a few real rows: scored X, expected MIN-MAX, delta.
SELECT TOP 10
    ReadingAssessmentID, LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode, ReadingDelta
FROM FactAssessmentReading
WHERE LevelCode IS NOT NULL
ORDER BY ReadingAssessmentID DESC;

-- ===== WRITING: counts + recompute check =====
-- WithAverage should equal Rows_ (every complete row got an average).
-- Complete_AvgNull must be 0 (no complete row missing its average).
-- AvgMismatch must be 0 (stored average matches a fresh SCR-aware recompute, rounded to 2 dp).
SELECT
    'WRITING' AS Fact,
    COUNT(*)                                                                 AS Rows_,
    COUNT(WritingAverage)                                                    AS WithAverage,
    SUM(CASE WHEN IdeasScore IS NOT NULL AND OrganizationScore IS NOT NULL
              AND LanguageScore IS NOT NULL AND WritingAverage IS NULL
             THEN 1 ELSE 0 END)                                              AS Complete_AvgNull_shouldBe0,
    SUM(CASE WHEN WritingAverage IS NOT NULL
              AND WritingAverage <> CAST(
                    CAST(IdeasScore + OrganizationScore + LanguageScore
                         + COALESCE(TRY_CAST(ConventionsScore AS INT), 0) AS DECIMAL(6,4))
                    / (3 + CASE WHEN TRY_CAST(ConventionsScore AS INT) IS NULL THEN 0 ELSE 1 END)
                    AS DECIMAL(4,2))
             THEN 1 ELSE 0 END)                                              AS AvgMismatch_shouldBe0
FROM FactAssessmentWriting;

-- Writing sample — scores + stored average; SCR rows should average over 3 traits.
SELECT TOP 10
    WritingAssessmentID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore, WritingAverage
FROM FactAssessmentWriting
WHERE WritingAverage IS NOT NULL
ORDER BY WritingAssessmentID DESC;
