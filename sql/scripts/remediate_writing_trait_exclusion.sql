/*******************************************************************************
 * Script: remediate_writing_trait_exclusion
 * Purpose: Reconcile EXISTING FactAssessmentWriting rows to the WritingTraitExclusion
 *          config. For any stored row whose (grade x program family x cycle benchmark
 *          month) matches an active exclusion rule, record the excluded trait as the
 *          intentional '-' (deliberately NOT assessed — distinct from NULL = never
 *          recorded) and recompute the stored WritingAverage over the scored traits.
 *
 *          WHY: the upsert proc enforces exclusions only at WRITE time (new/corrected
 *          entries store '-' + a '-'/'SCR'/NULL-aware average). Rows written BEFORE a
 *          rule existed — or seeded/imported directly — still carry a numeric value
 *          under the now-excluded trait, so every recompute-from-traits read (entry
 *          grid, cohort & history TVFs) would keep counting it. This brings stored
 *          data in line and marks those cells with the '-' sentinel.
 *
 *          RUN THIS: once after first deploying WritingTraitExclusion (AND after
 *          migrate_FactWriting_traits_varchar.sql — the trait columns must be VARCHAR
 *          to hold '-'), and again each time an exclusion rule is ADDED/activated for a
 *          grade/program/month that may already hold entries.
 *
 * Reads:   WritingTraitExclusion (ActiveFlag=1), DimStudent (by frozen StudentKey —
 *          the surrogate already pins the grade/program as-of the assessment),
 *          DimProgram, DimAssessmentWindow.
 * Writes:  FactAssessmentWriting — IdeasScore / OrganizationScore / LanguageScore /
 *          ConventionsScore (set to '-' where excluded) + WritingAverage + LastUpdated.
 *
 * IDEMPOTENT: the trait updates are guarded by "value is not already '-'", and the
 *          average recompute lands the same value on a second run — re-running on
 *          clean data changes 0 rows.
 * SAFETY:   affects ONLY rows matching an ACTIVE exclusion rule. Non-matching rows
 *          (any other grade/program/month) are untouched. Depends on VARCHAR trait
 *          columns — run migrate_FactWriting_traits_varchar.sql FIRST.
 * Region:  Canada East (PIIDPA compliant)
 *
 * Benchmark month for a row = its window's BenchmarkMonth, else the window StartDate's
 * calendar month (the monthly-bin fallback) — identical to the proc and roster TVF.
 ******************************************************************************/

SET NOCOUNT ON;

-- A row matches a rule when the frozen DimStudent version for its StudentKey has the
-- rule's grade + program family, and the row's window resolves to the rule's benchmark
-- month. One guarded UPDATE per trait (only Organization has a rule today; the other
-- three are no-ops until a rule names them). Guard "<> '-' OR IS NULL" so an already
-- remediated cell is skipped (idempotent) but a stale numeric or a true NULL is set to '-'.

-- Ideas
UPDATE faw
SET faw.IdeasScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.IdeasScore IS NULL OR faw.IdeasScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Ideas'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Organization
UPDATE faw
SET faw.OrganizationScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.OrganizationScore IS NULL OR faw.OrganizationScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Organization'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Language
UPDATE faw
SET faw.LanguageScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.LanguageScore IS NULL OR faw.LanguageScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Language'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Conventions (also carries 'SCR'; an exclusion rule still overrides to '-')
UPDATE faw
SET faw.ConventionsScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.ConventionsScore IS NULL OR faw.ConventionsScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Conventions'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));
GO

-- Recompute the stored WritingAverage over the scored traits, for every row that matches
-- ANY active exclusion rule. Same formula as usp_UpsertWritingAssessment and the read TVFs:
-- TRY_CAST drops '-' (excluded), 'SCR' (scribed) and NULL from BOTH numerator and denominator.
-- All-dropped -> NULL average.
UPDATE faw
SET faw.WritingAverage =
        CAST(COALESCE(TRY_CAST(faw.IdeasScore AS INT), 0) + COALESCE(TRY_CAST(faw.OrganizationScore AS INT), 0)
             + COALESCE(TRY_CAST(faw.LanguageScore AS INT), 0) + COALESCE(TRY_CAST(faw.ConventionsScore AS INT), 0) AS DECIMAL(6,4))
        / NULLIF( (CASE WHEN TRY_CAST(faw.IdeasScore        AS INT) IS NOT NULL THEN 1 ELSE 0 END)
                + (CASE WHEN TRY_CAST(faw.OrganizationScore AS INT) IS NOT NULL THEN 1 ELSE 0 END)
                + (CASE WHEN TRY_CAST(faw.LanguageScore     AS INT) IS NOT NULL THEN 1 ELSE 0 END)
                + (CASE WHEN TRY_CAST(faw.ConventionsScore  AS INT) IS NOT NULL THEN 1 ELSE 0 END), 0),
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));
GO

-- Verify: after remediation this should return 0 rows (no excluded trait still holds a
-- numeric value — each matching cell now reads '-').
SELECT faw.WritingAssessmentID, ds.Grade, dp.ProgramFamily,
       COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)) AS BenchMonth,
       faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore, faw.WritingAverage
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
JOIN WritingTraitExclusion wte
      ON wte.ActiveFlag = 1
     AND wte.GradeCode      = ds.Grade
     AND wte.ProgramFamily  = dp.ProgramFamily
     AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate))
WHERE (wte.Trait = 'Ideas'        AND TRY_CAST(faw.IdeasScore        AS INT) IS NOT NULL)
   OR (wte.Trait = 'Organization' AND TRY_CAST(faw.OrganizationScore AS INT) IS NOT NULL)
   OR (wte.Trait = 'Language'     AND TRY_CAST(faw.LanguageScore     AS INT) IS NOT NULL)
   OR (wte.Trait = 'Conventions'  AND TRY_CAST(faw.ConventionsScore  AS INT) IS NOT NULL);
GO
