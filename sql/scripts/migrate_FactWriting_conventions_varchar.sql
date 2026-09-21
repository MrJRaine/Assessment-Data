/*******************************************************************************
 * Script: migrate_FactWriting_conventions_varchar.sql
 * Purpose: Change FactAssessmentWriting.ConventionsScore from INT to VARCHAR(10)
 *          so it can hold the "SCR" (Scribed) code alongside '1'-'4'. Fabric has no
 *          ALTER COLUMN (type change) and we avoid a full table rebuild, so this does
 *          a multi-step column swap that PRESERVES existing data and the column NAME:
 *            add temp VARCHAR -> copy INT->VARCHAR -> drop INT col -> re-add VARCHAR
 *            under the original name -> copy back -> drop temp.
 *          Each step is its own batch (GO) so the parser only sees existing columns
 *          (see the fabric-warehouse-sql skill: catalog-check-in-same-batch gotcha).
 * SCR = Scribed on Conventions only (someone else physically wrote for the student, so
 *          conventions aren't the student's own production). SCR is OMITTED from the
 *          writing average (sum/count over the SCORED traits) — see the reads + proc.
 * Created: 2026-09-17
 * Region: Canada East (PIIDPA compliant)
 *
 * RUN ONCE per warehouse (dev, then live at the 0.5.0 release). Ideas/Organization/
 * Language stay INT. Safe on an empty table too (the UPDATEs just touch 0 rows).
 ******************************************************************************/

-- IDEMPOTENT: every batch is guarded so the swap runs ONLY while ConventionsScore is still INT
-- (system_type_id 56). Once it is VARCHAR (167) every guard is false and the whole script no-ops —
-- safe to re-run, and safe on a dev warehouse that already converted. int=56, varchar=167 are fixed.

-- 1) temp VARCHAR column, seeded from the existing INT — only while conversion is pending.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD ConventionsScoreTmp VARCHAR(10) NULL;
END;
GO
-- Dynamic SQL: the UPDATE names ConventionsScoreTmp, which does not exist on an already-converted
-- warehouse. A plain statement would fail to PARSE there (Fabric parses the whole batch up front,
-- guard or not — the catalog-check-in-same-batch gotcha). EXEC defers parsing to run time, so when the
-- guard is false the statement is never parsed. Same reason applied to the copy-back below.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting
             SET ConventionsScoreTmp = CAST(ConventionsScore AS VARCHAR(10))
           WHERE ConventionsScore IS NOT NULL;');
END;
GO

-- 2) drop the INT column, re-add it as VARCHAR (same name) — only while the INT still exists + tmp is staged.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN ConventionsScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD ConventionsScore VARCHAR(10) NULL;
END;
GO

-- 3) copy back and drop the temp — only while the temp is still present.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting
             SET ConventionsScore = ConventionsScoreTmp
           WHERE ConventionsScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'ConventionsScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN ConventionsScoreTmp;
END;
GO

-- verify (dev/synthetic — safe to display): distinct conventions values now include codes.
SELECT ConventionsScore, COUNT(*) AS Rows
FROM FactAssessmentWriting
GROUP BY ConventionsScore
ORDER BY ConventionsScore;
GO
