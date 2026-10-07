/*******************************************************************************
 * Script: fix_dev_dimstaff_overlap_projectlead.sql   (DEV / TEST ONLY)
 * Purpose: Clear DQ rule D ("overlapping effective windows for same Email") for
 *          jeffrey.raine@tcrce.ca. Cause: fix_dev_projectlead_analyst_active.sql
 *          ENDED the spurious NULL-access deactivation-marker row at today while the
 *          RegionalAnalyst row is open from an earlier date -- so the marker's window
 *          sits INSIDE the open window (overlap). The marker should have been DELETED,
 *          not ended.
 *
 *          Fix: keep the newest RegionalAnalyst row as the single current/open row and
 *          DELETE every other DimStaff row for this email (the marker + any dups).
 *          Leaves exactly one row => no overlap.
 *
 * Reads/Writes: DimStaff (DELETE non-kept rows for this email; UPDATE the kept row to
 *          current/open/active). StaffSchoolAccess/StaffAppAccess untouched (already
 *          point at the kept StaffKey from the earlier fix). No PII. DEV only.
 * Safe: the deleted rows are a recent anti-join deactivation marker (NULL AccessLevel)
 *          and any dup -- not rows anyone entered assessments as, so no fact references them.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Email   VARCHAR(255) = 'jeffrey.raine@tcrce.ca';
DECLARE @KeepKey BIGINT;

-- BEFORE: show the rows (so the overlap is visible).
SELECT 'BEFORE' AS Phase, StaffKey, AccessLevel, ActiveFlag, IsCurrent, EffectiveStartDate, EffectiveEndDate
FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) ORDER BY EffectiveStartDate, StaffKey;

-- Row to keep = newest RegionalAnalyst row.
SELECT TOP 1 @KeepKey = StaffKey
FROM DimStaff
WHERE LOWER(Email) = LOWER(@Email) AND AccessLevel = 'RegionalAnalyst'
ORDER BY EffectiveStartDate DESC, StaffKey DESC;

IF @KeepKey IS NULL
BEGIN
    ;THROW 60002, 'fix_dev_dimstaff_overlap_projectlead: no RegionalAnalyst row for this email -- run grant_dev_projectlead_access.sql first.', 1;
END;

-- Remove every other row for this email (the overlapping marker + any dups).
DELETE FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) AND StaffKey <> @KeepKey;

-- Make the kept row the sole current, open, active RegionalAnalyst row.
UPDATE DimStaff
SET IsCurrent = 1, ActiveFlag = 1, EffectiveEndDate = NULL, LastUpdated = GETDATE()
WHERE StaffKey = @KeepKey;

-- AFTER: exactly one row, open window, RegionalAnalyst/active.
SELECT 'AFTER' AS Phase, StaffKey, AccessLevel, ActiveFlag, IsCurrent, EffectiveStartDate, EffectiveEndDate
FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) ORDER BY EffectiveStartDate, StaffKey;
