/*******************************************************************************
 * Script: migrate_DimAssessmentWindow_add_AssessmentLanguage.sql
 * Purpose: App-level per-cycle scoping. Adds two columns to DimAssessmentWindow so
 *          a Short Cycle can be scoped, from the /cycles page, along:
 *            AssessmentLanguage  'English'|'French' (NULL = Both: writing toggle /
 *                                reading per student).
 *            ProgramScope        comma-delimited bucket set from
 *                                {English, Early Immersion, Late Immersion}
 *                                (NULL = all programs). Buckets come from
 *                                DimProgram.ScopeBucket (non-immersion -> English).
 *          These combine with the existing MinGrade/MaxGrade grade band. Membership
 *          follows the structural rule (French literacy = French Immersion); WHICH
 *          grades/programs/language a cycle covers is this config, not hardcoded.
 *          The writing RESULT keeps its own AssessmentLanguage (storage); these
 *          scope the CYCLE.
 * Run ONCE. GO-separated. ADD COLUMN supported in Fabric.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.DimAssessmentWindow') AND name = 'AssessmentLanguage')
BEGIN
    ALTER TABLE dbo.DimAssessmentWindow ADD AssessmentLanguage VARCHAR(10) NULL;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.DimAssessmentWindow') AND name = 'ProgramScope')
BEGIN
    ALTER TABLE dbo.DimAssessmentWindow ADD ProgramScope VARCHAR(100) NULL;
END;
GO

-- Existing cycles stay NULL on both (= Both / all programs) = today's behaviour. No backfill.
SELECT TOP 5 AssessmentWindowID, WindowName, AssessmentType, ProgramScope, ScaleSystem, AssessmentLanguage, MinGrade, MaxGrade
FROM dbo.DimAssessmentWindow ORDER BY AssessmentWindowID DESC;
GO
