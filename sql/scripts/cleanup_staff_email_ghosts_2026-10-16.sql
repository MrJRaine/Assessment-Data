/*******************************************************************************
 * Script: cleanup_staff_email_ghosts_2026-10-16.sql   (ONE-TIME remediation — REVIEW PART 1 FIRST)
 * Purpose: Close the existing NULL-access "ghost" DimStaff markers left by past email corrections —
 *          i.e. a deactivation marker under an OLD/typo'd email whose real person now lives under a
 *          CORRECTED email. Going forward, usp_MergeStaff step 3.5 renames in place so no new ghosts
 *          form; this cleans up the ones already on the books. Genuine departures (a ghost with NO
 *          corrected-email twin) are LEFT ALONE.
 *
 * Match: a ghost (current, ActiveFlag=0, AccessLevel NULL) is linked to a current ACTIVE person under a
 *        DIFFERENT email by a SHARED per-assignment PS id (FactStaffAssignment.SourceSystemID) somewhere
 *        in the ghost-email's assignment history. Only 1:1 (one ghost <-> one person) links qualify;
 *        ambiguous links are excluded for manual handling.
 *
 * ** WRITES in PART 2 (closes DimStaff ghost rows). Run PART 1 first, confirm the pairs match the
 *    corrections you made, THEN run PART 2. Dev first, then live. **
 *
 * Reads/Writes: DimStaff (PART 2 UPDATE sets IsCurrent=0 on matched ghost markers), FactStaffAssignment.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- ============================ PART 1 — PREVIEW (read-only) ============================
-- Review: each row is a ghost email that will be closed, with the corrected person it maps to.
;WITH GhostEmails AS (
    SELECT d.StaffKey AS GhostKey, d.Email AS GhostEmail
    FROM DimStaff d
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 0 AND d.AccessLevel IS NULL
),
GhostAssignIDs AS (   -- every PS assignment id ever tied to the ghost email (across all its versions)
    SELECT g.GhostKey, g.GhostEmail, f.SourceSystemID
    FROM GhostEmails g
    INNER JOIN DimStaff dv           ON dv.Email    = g.GhostEmail
    INNER JOIN FactStaffAssignment f ON f.StaffKey  = dv.StaffKey
    WHERE NULLIF(LTRIM(RTRIM(f.SourceSystemID)), '') IS NOT NULL
),
CurrentPersonAssign AS (   -- current ACTIVE staff + their current assignment ids
    SELECT d.StaffKey AS PersonKey, d.Email AS PersonEmail, f.SourceSystemID
    FROM DimStaff d
    INNER JOIN FactStaffAssignment f ON f.StaffKey = d.StaffKey AND f.IsCurrent = 1
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 1
      AND NULLIF(LTRIM(RTRIM(f.SourceSystemID)), '') IS NOT NULL
),
Links AS (
    SELECT DISTINCT ga.GhostKey, ga.GhostEmail, cp.PersonKey, cp.PersonEmail
    FROM GhostAssignIDs ga
    INNER JOIN CurrentPersonAssign cp ON cp.SourceSystemID = ga.SourceSystemID
    WHERE cp.PersonEmail <> ga.GhostEmail
)
SELECT l.GhostEmail, l.PersonEmail, l.GhostKey, l.PersonKey
FROM Links l
WHERE l.GhostEmail  IN (SELECT GhostEmail  FROM Links GROUP BY GhostEmail  HAVING COUNT(DISTINCT PersonEmail) = 1)
  AND l.PersonEmail IN (SELECT PersonEmail FROM Links GROUP BY PersonEmail HAVING COUNT(DISTINCT GhostEmail)  = 1)
ORDER BY l.GhostEmail;
GO

-- ============================ PART 2 — APPLY (writes; run after reviewing PART 1) =====
-- Closes the matched ghost markers so the old email drops out of the current staff set (its history
-- stays). Same 1:1-guarded match as PART 1. (CTEs repeat — Fabric doesn't persist them across batches.)
/*  Uncomment to run:
;WITH GhostEmails AS (
    SELECT d.StaffKey AS GhostKey, d.Email AS GhostEmail
    FROM DimStaff d
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 0 AND d.AccessLevel IS NULL
),
GhostAssignIDs AS (
    SELECT g.GhostKey, g.GhostEmail, f.SourceSystemID
    FROM GhostEmails g
    INNER JOIN DimStaff dv           ON dv.Email    = g.GhostEmail
    INNER JOIN FactStaffAssignment f ON f.StaffKey  = dv.StaffKey
    WHERE NULLIF(LTRIM(RTRIM(f.SourceSystemID)), '') IS NOT NULL
),
CurrentPersonAssign AS (
    SELECT d.StaffKey AS PersonKey, d.Email AS PersonEmail, f.SourceSystemID
    FROM DimStaff d
    INNER JOIN FactStaffAssignment f ON f.StaffKey = d.StaffKey AND f.IsCurrent = 1
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 1
      AND NULLIF(LTRIM(RTRIM(f.SourceSystemID)), '') IS NOT NULL
),
Links AS (
    SELECT DISTINCT ga.GhostKey, ga.GhostEmail, cp.PersonEmail
    FROM GhostAssignIDs ga
    INNER JOIN CurrentPersonAssign cp ON cp.SourceSystemID = ga.SourceSystemID
    WHERE cp.PersonEmail <> ga.GhostEmail
),
Unambiguous AS (
    SELECT l.GhostKey
    FROM Links l
    WHERE l.GhostEmail  IN (SELECT GhostEmail  FROM Links GROUP BY GhostEmail  HAVING COUNT(DISTINCT PersonEmail) = 1)
      AND l.PersonEmail IN (SELECT PersonEmail FROM Links GROUP BY PersonEmail HAVING COUNT(DISTINCT GhostEmail)  = 1)
)
UPDATE d
SET IsCurrent = 0,
    EffectiveEndDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE),
    LastUpdated = GETDATE()
FROM DimStaff d
INNER JOIN Unambiguous u ON u.GhostKey = d.StaffKey
WHERE d.IsCurrent = 1 AND d.ActiveFlag = 0 AND d.AccessLevel IS NULL;
GO
*/
