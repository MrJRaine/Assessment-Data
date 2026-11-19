/*******************************************************************************
 * Migration: columns added for 1.5.0 (split-grade math pacing + chain structure).
 * Purpose: 1) StaffAppAccess.CanManageMathPacing - the new regional pacing-editor
 *             capability (granted from the staff-access admin page).
 *          2) FactAssessmentMath.CarriedFromMathTaskKey / CarriedFromMonth /
 *             OutcomeCode - STRUCTURE ONLY for task chains (planned 1.6.0). All three
 *             are NULL on every existing row and nothing reads or writes them yet.
 * SCD Type: n/a (migration)
 * Created: 2026-11-19 (1.5.0)
 * READS:  sys.columns (to skip a column that already exists).
 * WRITES: adds four NULLable columns. No existing value is changed.
 * Idempotent: yes - each ADD is skipped when the column exists.
 * Region: Canada East (PIIDPA compliant)
 *
 * Each ADD is its own batch: Fabric cannot ADD a column and reference it in the
 * same batch. The columns are NULLable because Fabric cannot add a NOT NULL column
 * to a populated table; readers treat NULL as "no".
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.StaffAppAccess') AND name = 'CanManageMathPacing')
    ALTER TABLE dbo.StaffAppAccess ADD CanManageMathPacing BIT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'CarriedFromMathTaskKey')
    ALTER TABLE dbo.FactAssessmentMath ADD CarriedFromMathTaskKey BIGINT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'CarriedFromMonth')
    ALTER TABLE dbo.FactAssessmentMath ADD CarriedFromMonth INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.FactAssessmentMath') AND name = 'OutcomeCode')
    ALTER TABLE dbo.FactAssessmentMath ADD OutcomeCode VARCHAR(20) NULL;
GO
