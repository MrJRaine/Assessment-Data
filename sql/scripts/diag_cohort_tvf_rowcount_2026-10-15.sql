/*******************************************************************************
 * Script: diag_cohort_tvf_rowcount_2026-10-15.sql   (LIVE — READ ONLY; StudentNumber)
 * Purpose: Ground truth for the duplication: how many rows does tvf_StudentCohort ACTUALLY return
 *          per student? Tells us whether the x4 is all server-side (a join fan-out in the TVF) or
 *          whether the TVF returns x2 and the report PAGE doubles it again (client-side).
 *            - duplicated students at CohortRows = 2  -> server is only x2 (the view); the other x2 is the webapp.
 *            - duplicated students at CohortRows = 4  -> a second fan-out lives in the TVF after all.
 *
 * Reads:  tvf_StudentCohort (via @UPN). Returns StudentNumber + a count — authorized admin use.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * @UPN must be a caller with broad scope (RegionalAnalyst) so all students are in range.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @UPN VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- a RegionalAnalyst UPN (sees all students)

SELECT StudentNumber, COUNT(*) AS CohortRows
FROM dbo.tvf_StudentCohort(@UPN, NULL)
GROUP BY StudentNumber
HAVING COUNT(*) > 1
ORDER BY CohortRows DESC, StudentNumber;
GO

-- Totals for context: rows returned vs distinct students (gap = total duplication).
DECLARE @UPN2 VARCHAR(255) = 'jeffrey.raine@tcrce.ca';
SELECT COUNT(*) AS TotalRows, COUNT(DISTINCT StudentNumber) AS DistinctStudents
FROM dbo.tvf_StudentCohort(@UPN2, NULL);
GO
