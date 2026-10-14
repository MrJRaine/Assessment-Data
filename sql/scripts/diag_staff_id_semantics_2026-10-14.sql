/*******************************************************************************
 * Script: diag_staff_id_semantics_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Decide whether Stg_Staff.ID is a per-ACCOUNT id (stable per person -> usable as the
 *          immutable staff match key) or a per-ASSIGNMENT id (varies by school -> NOT usable).
 *          Gates the proposed "match staff on PS account ID instead of email" rework.
 *
 * Reads:  Stg_Staff (current PS staff export only — truncate/reload). Staff email, no student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * How to read it:
 *   (1) For people on MULTIPLE rows (multi-school), DistinctIDs = 1  -> ID is per-ACCOUNT (GOOD, usable).
 *                                                     DistinctIDs > 1 -> ID is per-ASSIGNMENT (need DCID).
 *   (2) Any single ID mapping to >1 email in ONE export would be odd (ID reuse / email mid-change).
 *   (3) Any email mapping to >1 ID in ONE export = per-assignment ID (same finding as (1), other angle).
 ******************************************************************************/

SET NOCOUNT ON;

-- (1) Per person (email): how many rows, distinct IDs, distinct schools.
SELECT
    LOWER(s.Email_Addr)       AS Email,
    COUNT(*)                  AS Rows,
    COUNT(DISTINCT s.ID)      AS DistinctIDs,
    COUNT(DISTINCT s.SchoolID) AS DistinctSchools
FROM Stg_Staff s
WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL
GROUP BY LOWER(s.Email_Addr)
HAVING COUNT(*) > 1
ORDER BY DistinctIDs DESC, Rows DESC;
GO

-- (2) Any ID under more than one email (ID reuse / collision).
SELECT s.ID, COUNT(DISTINCT LOWER(s.Email_Addr)) AS DistinctEmails
FROM Stg_Staff s
WHERE s.ID IS NOT NULL AND NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL
GROUP BY s.ID
HAVING COUNT(DISTINCT LOWER(s.Email_Addr)) > 1
ORDER BY DistinctEmails DESC;
GO

-- (3) Quick verdict: overall uniqueness of ID vs email across the whole current export.
SELECT
    COUNT(*)                        AS TotalRows,
    COUNT(DISTINCT s.ID)            AS DistinctIDs,
    COUNT(DISTINCT LOWER(s.Email_Addr)) AS DistinctEmails,
    SUM(CASE WHEN s.ID IS NULL OR LTRIM(RTRIM(s.ID)) = '' THEN 1 ELSE 0 END) AS NullOrBlankIDs
FROM Stg_Staff s
WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL;
GO
