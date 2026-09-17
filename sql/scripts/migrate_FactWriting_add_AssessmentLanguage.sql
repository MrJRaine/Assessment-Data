/*******************************************************************************
 * Script: migrate_FactWriting_add_AssessmentLanguage.sql
 * Purpose: Dual-language writing. Add AssessmentLanguage to FactAssessmentWriting
 *          so a French-Immersion grade-3+ student can hold BOTH an English and a
 *          French writing result per cycle. Grain becomes
 *          (StudentKey, AssessmentWindowID, AssessmentLanguage, AssessmentDate).
 *
 * Backfill: existing rows predate dual-track, so they are the language of the
 *          student's PROGRAM -- English/FSL program -> 'English', French Immersion
 *          -> 'French' (per user, 2026-09-17). Joined on the exact SCD version the
 *          fact points to (StudentKey surrogate), not IsCurrent.
 * Run ONCE. GO-separated: the ADD COLUMN and the UPDATE that references the new
 *          column MUST be in separate batches -- Fabric parses a batch as a unit,
 *          so a column added and used in the same batch raises Msg 207
 *          (Invalid column name). ADD COLUMN + UPDATE are supported (no ALTER-type).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- 1) Add the column (nullable so the ADD succeeds; backfilled below, then always
--    supplied by usp_UpsertWritingAssessment going forward).
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'AssessmentLanguage'
)
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD AssessmentLanguage VARCHAR(10) NULL;
END;
GO

-- 2) Backfill existing rows by program family (FI -> French; everything else -> English).
--    Separate batch so AssessmentLanguage is already committed and parseable here.
UPDATE faw
SET AssessmentLanguage =
        CASE WHEN dp.ProgramFamily = 'French Immersion' THEN 'French' ELSE 'English' END
FROM dbo.FactAssessmentWriting faw
JOIN dbo.DimStudent s  ON s.StudentKey  = faw.StudentKey       -- exact SCD version the fact references
JOIN dbo.DimProgram dp ON dp.ProgramCode = s.ProgramCode
WHERE faw.AssessmentLanguage IS NULL;
GO

-- 3) Verify: no NULLs remain, and the split looks right.
SELECT AssessmentLanguage, COUNT(*) AS Rows
FROM dbo.FactAssessmentWriting
GROUP BY AssessmentLanguage
ORDER BY AssessmentLanguage;
GO
