/*******************************************************************************
 * Script: diag_cohort_dupes_by_name_2026-10-15.sql   (LIVE — READ ONLY; STUDENT PII — names)
 * Purpose: Reproduce what the Reading report actually shows: it lists students by NAME, but our earlier
 *          diag grouped by StudentNumber and topped out at 2 per number. If one physical student has
 *          TWO StudentNumbers (re-registration / duplicate provincial #, i.e. two separate current
 *          DimStudent rows), each number returns 2 (baseline-dup x2) and the PERSON shows 2+2 = 4 times
 *          by name. This groups the cohort output by NAME to expose that:
 *            RowsByName              = how many times the name appears on the report  <-- matches the screen
 *            DistinctStudentNumbers  = how many provincial numbers that name maps to
 *            DistinctStudentKeys     = how many current DimStudent surrogate rows
 *
 *          Read it:
 *            - RowsByName = 4, DistinctStudentNumbers = 2 -> CONFIRMED: the 2nd x2 is a DUPLICATE
 *              StudentNumber for the same person. Fix = (a) view-collapse (already built) drops each
 *              number to 1 -> name shows 2x; (b) the duplicate-StudentNumber records need reconciling.
 *            - RowsByName = 4, DistinctStudentNumbers = 1 -> a single number returning 4 (would
 *              contradict the per-number diag; means a 2nd server fan-out after all).
 *            - RowsByName = 2 only -> just the baseline-dup x2; no name quadrupling (look elsewhere).
 *
 * Reads:  tvf_StudentCohort (via @UPN). Returns names (PII) + counts — authorized admin use, in-region.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * @UPN must be a RegionalAnalyst UPN so every student is in scope.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- a RegionalAnalyst UPN (sees all students)

;WITH c AS (
    SELECT FirstName, LastName, StudentNumber, StudentKey
    FROM dbo.tvf_StudentCohort(@UPN, NULL)
)
SELECT
    LastName,
    FirstName,
    COUNT(*)                        AS RowsByName,            -- times this name appears on the report
    COUNT(DISTINCT StudentNumber)   AS DistinctStudentNumbers,
    COUNT(DISTINCT StudentKey)      AS DistinctStudentKeys
FROM c
GROUP BY LastName, FirstName
HAVING COUNT(*) > 1
ORDER BY RowsByName DESC, LastName, FirstName;
GO
