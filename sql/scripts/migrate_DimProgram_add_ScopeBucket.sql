/*******************************************************************************
 * Script: migrate_DimProgram_add_ScopeBucket.sql
 * Purpose: Classify each program into the cycle PROGRAM-SCOPE bucket used by the
 *          /cycles multi-select: 'English' | 'Early Immersion' | 'Late Immersion'.
 *          This is a FACTUAL property of each PowerSchool program code (early vs
 *          late immersion is otherwise only implicit in the program name), so it
 *          lives in DimProgram rather than being derived in a TVF.
 *          Rule (per user 2026-09-17): anything NOT French Immersion folds into
 *          'English' (incl. French Second Language). FI + name contains 'Late' ->
 *          'Late Immersion'; other FI (incl. 'Elementary French Immersion') -> 'Early'.
 * Run ONCE. GO-separated (add column, then backfill). ADD COLUMN + UPDATE supported.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.DimProgram') AND name = 'ScopeBucket'
)
BEGIN
    ALTER TABLE dbo.DimProgram ADD ScopeBucket VARCHAR(20) NULL;
END;
GO

UPDATE dbo.DimProgram
SET ScopeBucket =
    CASE WHEN IsImmersion = 0            THEN 'English'          -- non-immersion (incl. FSL) folds into English
         WHEN ProgramName LIKE '%Late%'  THEN 'Late Immersion'
         ELSE 'Early Immersion' END;
GO

-- Verify the split (expect Late = J020/S020/S120/S220; Early = E015/J015/S015/S115/S215; rest English).
SELECT ScopeBucket, COUNT(*) AS Programs, STRING_AGG(ProgramCode, ', ') AS Codes
FROM dbo.DimProgram GROUP BY ScopeBucket ORDER BY ScopeBucket;
GO
