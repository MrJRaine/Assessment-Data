/*******************************************************************************
 * Script: fix_dimstaff_dup_current_2026-10-30
 * Purpose: One-time repair for DUPLICATE-CURRENT DimStaff pairs created by the
 *          Role-Overrides Save restoring a person the write rule had just
 *          dropped: the Save inserted a new ACTIVE row without closing the
 *          same-day DEACTIVATION MARKER (IsCurrent=1, ActiveFlag=0), leaving
 *          two IsCurrent=1 rows with overlapping windows, and the next merge
 *          hung current FactStaffAssignment rows off the inactive key — the
 *          three DQ-gate violations of 2026-10-30 15:03 (sandra.runyon).
 *          GENERIC: repairs every email in this state, not just one.
 *          The proc is fixed as of 2026-10-30 (marker revived/closed before
 *          provisioning — usp_SetStaffRoleOverride).
 *
 * Reads:  DimStaff, FactStaffAssignment.
 * Writes: FactStaffAssignment (close current rows under marker keys),
 *         DimStaff (close the duplicate markers).
 * Idempotent: repaired rows no longer match the predicates.
 * Run on LIVE (where the DQ gate failed), then re-run the ingest cycle —
 * the gate should pass and the post-gate steps (membership rebuild) complete.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- ---------------------------------------------------------------------------
-- PART 1 — PREVIEW (read-only): every email with more than one IsCurrent=1
-- row, with each row's state, and the current assignment rows under marker keys.
-- ---------------------------------------------------------------------------
SELECT 'Dup-current emails' AS ResultSet,
       d.Email, d.StaffKey, d.ActiveFlag, d.AccessLevel,
       d.EffectiveStartDate, d.EffectiveEndDate, d.IsCurrent
FROM DimStaff d
WHERE d.IsCurrent = 1
  AND LOWER(d.Email) IN (SELECT LOWER(Email) FROM DimStaff
                         WHERE IsCurrent = 1 GROUP BY LOWER(Email) HAVING COUNT(*) > 1)
ORDER BY d.Email, d.ActiveFlag;

SELECT 'FSA rows under marker keys' AS ResultSet,
       f.StaffAssignmentID, f.StaffKey, f.SchoolID, f.RoleCode, f.IsCurrent
FROM FactStaffAssignment f
INNER JOIN DimStaff marker ON marker.StaffKey = f.StaffKey
WHERE f.IsCurrent = 1
  AND marker.IsCurrent = 1 AND marker.ActiveFlag = 0
  AND EXISTS (SELECT 1 FROM DimStaff act
              WHERE LOWER(act.Email) = LOWER(marker.Email)
                AND act.IsCurrent = 1 AND act.ActiveFlag = 1);

-- ---------------------------------------------------------------------------
-- PART 2 — close current FactStaffAssignment rows that hang off a duplicate
-- MARKER key (the email also has a current ACTIVE row; the next ingest's 5c
-- re-opens the assignment under the active key if it isn't there already).
-- ---------------------------------------------------------------------------
UPDATE f
SET EffectiveEndDate = CASE WHEN f.EffectiveStartDate > DATEADD(DAY, -1, @Today)
                            THEN f.EffectiveStartDate ELSE DATEADD(DAY, -1, @Today) END,
    IsCurrent        = 0,
    LastUpdated      = GETDATE()
FROM FactStaffAssignment f
INNER JOIN DimStaff marker ON marker.StaffKey = f.StaffKey
WHERE f.IsCurrent = 1
  AND marker.IsCurrent = 1 AND marker.ActiveFlag = 0
  AND EXISTS (SELECT 1 FROM DimStaff act
              WHERE LOWER(act.Email) = LOWER(marker.Email)
                AND act.IsCurrent = 1 AND act.ActiveFlag = 1);

-- ---------------------------------------------------------------------------
-- PART 3 — close the duplicate MARKER rows themselves (the ACTIVE row stays
-- the single current version). Same-day markers close as a 0-day window.
-- ---------------------------------------------------------------------------
UPDATE marker
SET EffectiveEndDate = CASE WHEN marker.EffectiveStartDate > DATEADD(DAY, -1, @Today)
                            THEN marker.EffectiveStartDate ELSE DATEADD(DAY, -1, @Today) END,
    IsCurrent        = 0,
    LastUpdated      = GETDATE()
FROM DimStaff marker
WHERE marker.IsCurrent = 1 AND marker.ActiveFlag = 0
  AND EXISTS (SELECT 1 FROM DimStaff act
              WHERE LOWER(act.Email) = LOWER(marker.Email)
                AND act.IsCurrent = 1 AND act.ActiveFlag = 1);

-- ---------------------------------------------------------------------------
-- PART 4 — VERIFY: all three counts must be 0 (they mirror the DQ checks
-- that failed the gate).
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM (SELECT LOWER(Email) AS E FROM DimStaff
                           WHERE IsCurrent = 1 GROUP BY LOWER(Email) HAVING COUNT(*) > 1) x) AS DupCurrentEmails,
    (SELECT COUNT(*) FROM FactStaffAssignment f
     INNER JOIN DimStaff d ON d.StaffKey = f.StaffKey
     WHERE f.IsCurrent = 1 AND d.IsCurrent = 1 AND d.ActiveFlag = 0)                        AS CurrentFsaOnInactive,
    (SELECT COUNT(*) FROM DimStaff a
     INNER JOIN DimStaff b ON LOWER(a.Email) = LOWER(b.Email) AND a.StaffKey < b.StaffKey
     WHERE a.IsCurrent = 1 AND b.IsCurrent = 1)                                             AS OverlappingCurrentPairs;
