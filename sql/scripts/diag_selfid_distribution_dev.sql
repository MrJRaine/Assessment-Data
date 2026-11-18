/*******************************************************************************
 * Diagnostic: diag_selfid_distribution_dev.sql  (DEV: Assessment_Warehouse_Dev)
 * Purpose: Is the Self-ID African filter returning 0 because the stored values
 *          are all NULL? Counts DimStudent's Self-ID values per school x grade.
 *          READ-ONLY.
 * READS: DimStudent. WRITES: nothing.
 *
 * Result meanings: find your group's row.
 *   - AfricanYes ~ Total/12 and AfricanNo = 0 -> data is as the generator makes
 *     it (no explicit No on dev; the No filter correctly returns 0, the Yes
 *     filter should NOT) -> a 0 on Yes means the FEED is dropping the value,
 *     not the warehouse; report back which view/group you filtered.
 *   - AfricanYes = 0 and AfricanNull = Total -> the values never landed on
 *     these rows (column added after their last version; never re-merged) ->
 *     warehouse-side gap, fix is a data pass, not the filter.
 ******************************************************************************/

SELECT s.SchoolID, s.Grade,
       COUNT(*)                                            AS Total,
       SUM(CASE WHEN s.SelfIDAfrican = 1 THEN 1 ELSE 0 END) AS AfricanYes,
       SUM(CASE WHEN s.SelfIDAfrican = 0 THEN 1 ELSE 0 END) AS AfricanNo,
       SUM(CASE WHEN s.SelfIDAfrican IS NULL THEN 1 ELSE 0 END) AS AfricanNull,
       SUM(CASE WHEN s.SelfIDIndigenous = 1 THEN 1 ELSE 0 END) AS IndigenousYes,
       SUM(CASE WHEN s.SelfIDIndigenous = 0 THEN 1 ELSE 0 END) AS IndigenousNo,
       SUM(CASE WHEN s.SelfIDIndigenous IS NULL THEN 1 ELSE 0 END) AS IndigenousNull
FROM DimStudent s
WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
GROUP BY s.SchoolID, s.Grade
ORDER BY s.SchoolID, s.Grade;
