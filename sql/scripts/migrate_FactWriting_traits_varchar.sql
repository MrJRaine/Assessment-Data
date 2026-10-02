/*******************************************************************************
 * Script: migrate_FactWriting_traits_varchar.sql
 * Purpose: Change FactAssessmentWriting.IdeasScore / OrganizationScore /
 *          LanguageScore from INT to VARCHAR(10), so a trait can hold the
 *          intentional "-" (NOT assessed this cycle — a DELIBERATE recording,
 *          distinct from NULL = never recorded) alongside '1'-'4'. This mirrors
 *          the earlier ConventionsScore INT->VARCHAR swap (which added 'SCR').
 *          After this, all four writing traits are VARCHAR(10) and carry:
 *            '1'-'4' | 'SCR' (Conventions only) | '-' (excluded) | NULL (never recorded).
 *
 *          Fabric has no ALTER COLUMN (type change) and we avoid a full table
 *          rebuild, so each column does the proven multi-step swap that PRESERVES
 *          existing data and the column NAME:
 *            add temp VARCHAR -> copy INT->VARCHAR -> drop INT col -> re-add VARCHAR
 *            under the original name -> copy back -> drop temp.
 *          Each step is its own batch (GO) and the data-copy steps use EXEC so the
 *          parser never sees a not-yet-existing column (fabric-warehouse-sql skill:
 *          catalog-check-in-same-batch gotcha).
 * Created: 2026-10-02
 * Region: Canada East (PIIDPA compliant)
 *
 * RUN ONCE per warehouse (dev, then live). Idempotent: every batch is guarded on
 * the column's current type (int=56, varchar=167), so once converted the whole
 * script no-ops. Safe on an empty table (the UPDATEs touch 0 rows). The '-' values
 * themselves are written by usp_UpsertWritingAssessment (new entries) and by
 * remediate_writing_trait_exclusion.sql (existing rows) — NOT here.
 ******************************************************************************/

-- ======================= IdeasScore =======================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD IdeasScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET IdeasScoreTmp = CAST(IdeasScore AS VARCHAR(10)) WHERE IdeasScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN IdeasScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD IdeasScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET IdeasScore = IdeasScoreTmp WHERE IdeasScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN IdeasScoreTmp;
END;
GO

-- ==================== OrganizationScore ====================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD OrganizationScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET OrganizationScoreTmp = CAST(OrganizationScore AS VARCHAR(10)) WHERE OrganizationScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN OrganizationScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD OrganizationScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET OrganizationScore = OrganizationScoreTmp WHERE OrganizationScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN OrganizationScoreTmp;
END;
GO

-- ====================== LanguageScore ======================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD LanguageScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET LanguageScoreTmp = CAST(LanguageScore AS VARCHAR(10)) WHERE LanguageScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN LanguageScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD LanguageScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET LanguageScore = LanguageScoreTmp WHERE LanguageScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN LanguageScoreTmp;
END;
GO

-- verify (dev/synthetic — safe to display): all four trait columns should now be VARCHAR(167).
SELECT name, system_type_id
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting')
  AND name IN ('IdeasScore', 'OrganizationScore', 'LanguageScore', 'ConventionsScore')
ORDER BY name;
GO
