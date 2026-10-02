/*******************************************************************************
 * Table: WritingTraitExclusion
 * Purpose: Data-driven config for which writing TRAIT(s) are NOT assessed for a
 *          given (Grade x ProgramFamily x cycle benchmark month) — so the entry
 *          grid doesn't show that trait's dropdown and the average/reports drop it
 *          (same effect as a Conventions 'SCR'). Grain: one row per excluded trait.
 *          NEVER hardcode this rule in app/proc logic — add/remove rows here.
 * SCD: N/A (reference/config; admin-maintained).
 * Created: 2026-10-02
 * Region: Canada East (PIIDPA compliant)
 *
 * First rule (early French Immersion Primary can't produce enough French writing
 * in the fall to assess Organization): FI · Grade P · benchmark months Sep/Oct/Nov
 * · Organization. BenchmarkMonth is the INT 1-12 that the cycle's window resolves to
 * (DimAssessmentWindow.BenchmarkMonth, else its dominant calendar month).
 * Trait is one of: 'Ideas' | 'Organization' | 'Language' | 'Conventions'.
 *
 * IDEMPOTENT: guarded CREATE (never drops) + NOT-EXISTS seed, so a redeploy keeps
 * any admin-added rows. SELECT granted to the app SP.
 ******************************************************************************/

IF OBJECT_ID('dbo.WritingTraitExclusion', 'U') IS NULL
    EXEC('CREATE TABLE dbo.WritingTraitExclusion (
        WritingTraitExclusionID BIGINT       NOT NULL IDENTITY,
        GradeCode               VARCHAR(10)  NOT NULL,
        ProgramFamily           VARCHAR(50)  NOT NULL,
        BenchmarkMonth          INT          NOT NULL,   -- 1-12
        Trait                   VARCHAR(20)  NOT NULL,   -- Ideas|Organization|Language|Conventions
        ActiveFlag              BIT          NOT NULL,
        LastUpdated             DATETIME2(0) NOT NULL
    )');
GO

-- Seed: FI Primary — Organization not assessed in Sep/Oct/Nov cycles. Idempotent.
INSERT INTO dbo.WritingTraitExclusion (GradeCode, ProgramFamily, BenchmarkMonth, Trait, ActiveFlag, LastUpdated)
SELECT v.GradeCode, v.ProgramFamily, v.BenchmarkMonth, v.Trait, 1, GETDATE()
FROM (VALUES
    ('P', 'French Immersion',  9, 'Organization'),
    ('P', 'French Immersion', 10, 'Organization'),
    ('P', 'French Immersion', 11, 'Organization')
) v (GradeCode, ProgramFamily, BenchmarkMonth, Trait)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.WritingTraitExclusion x
    WHERE x.GradeCode = v.GradeCode AND x.ProgramFamily = v.ProgramFamily
      AND x.BenchmarkMonth = v.BenchmarkMonth AND x.Trait = v.Trait
);
GO

GRANT SELECT ON [dbo].[WritingTraitExclusion] TO [StudentDataAssessment];
GO
