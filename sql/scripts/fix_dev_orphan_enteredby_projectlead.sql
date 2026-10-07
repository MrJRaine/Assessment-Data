/*******************************************************************************
 * Script: fix_dev_orphan_enteredby_projectlead.sql   (DEV / TEST ONLY)
 * Purpose: Clear the 3 DQ "Orphan" violations from the 2026-10-07 app ingest:
 *          FactAssessmentReading (2) + FactAssessmentWriting (1) rows whose
 *          EnteredByStaffKey = 8016407336719482881 point at a DimStaff row that no
 *          longer exists.
 *
 *          CAUSE: fix_dev_dimstaff_overlap_projectlead.sql DELETED every DimStaff row
 *          for jeffrey.raine@tcrce.ca except the newest RegionalAnalyst row. Its header
 *          assumed none of the deleted rows had authored facts -- but 8016407336719482881
 *          was an earlier StaffKey of this user that HAD entered those 3 test assessments,
 *          so the delete orphaned them. Dev-recovery residue, not a loader/ingest defect
 *          (the app ingest reaching the DQ gate confirms #1119's SP-path COPY INTO is fixed).
 *
 *          FIX: re-point the orphaned EnteredByStaffKey (the author/audit stamp of WHO
 *          entered the result) to the surviving DimStaff StaffKey for the same person.
 *          This is the same author, just the current surrogate -- correct for dev test data.
 *          (We never DELETE a staff row that authored facts on LIVE; this is a dev-only
 *          cleanup of a dev-only over-delete.)
 *
 * Reads/Writes: DimStaff (read only, to resolve the keep key); UPDATE EnteredByStaffKey on
 *          FactAssessmentReading / FactAssessmentWriting / FactAssessmentMath for the ONE
 *          orphaned key only. No StudentKey / score / date touched. No PII. DEV only.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Email     VARCHAR(255) = 'jeffrey.raine@tcrce.ca';
DECLARE @OrphanKey BIGINT       = 8016407336719482881;   -- the deleted StaffKey the facts still reference
DECLARE @KeepKey   BIGINT;

-- Resolve a StaffKey for this user that STILL EXISTS in DimStaff. Prefer the newest
-- RegionalAnalyst row (the one the overlap fix kept + access points at); fall back to any
-- surviving row for the email if AccessLevel was nulled by a merge.
SELECT TOP 1 @KeepKey = StaffKey
FROM DimStaff
WHERE LOWER(Email) = LOWER(@Email) AND AccessLevel = 'RegionalAnalyst'
ORDER BY EffectiveStartDate DESC, StaffKey DESC;

IF @KeepKey IS NULL
    SELECT TOP 1 @KeepKey = StaffKey
    FROM DimStaff
    WHERE LOWER(Email) = LOWER(@Email)
    ORDER BY IsCurrent DESC, EffectiveStartDate DESC, StaffKey DESC;

IF @KeepKey IS NULL
BEGIN
    ;THROW 60003, 'fix_dev_orphan_enteredby_projectlead: no surviving DimStaff row for this email -- run grant_dev_projectlead_access.sql first.', 1;
END;

-- Guard: never re-point to a key that is itself the orphan (would be a no-op leaving the orphan).
IF @KeepKey = @OrphanKey
BEGIN
    ;THROW 60004, 'fix_dev_orphan_enteredby_projectlead: resolved keep key equals the orphan key -- the deleted row still exists? Inspect DimStaff before proceeding.', 1;
END;

-- BEFORE: how many rows each fact table has under the orphan key.
SELECT 'BEFORE' AS Phase,
       (SELECT COUNT(*) FROM FactAssessmentReading WHERE EnteredByStaffKey = @OrphanKey) AS Reading_Orphans,
       (SELECT COUNT(*) FROM FactAssessmentWriting WHERE EnteredByStaffKey = @OrphanKey) AS Writing_Orphans,
       (SELECT COUNT(*) FROM FactAssessmentMath    WHERE EnteredByStaffKey = @OrphanKey) AS Math_Orphans,
       @OrphanKey AS OrphanKey, @KeepKey AS KeepKey;

-- Re-point the author stamp to the surviving StaffKey for the same person.
UPDATE FactAssessmentReading SET EnteredByStaffKey = @KeepKey, LastUpdated = GETDATE() WHERE EnteredByStaffKey = @OrphanKey;
UPDATE FactAssessmentWriting SET EnteredByStaffKey = @KeepKey, LastUpdated = GETDATE() WHERE EnteredByStaffKey = @OrphanKey;
UPDATE FactAssessmentMath    SET EnteredByStaffKey = @KeepKey, LastUpdated = GETDATE() WHERE EnteredByStaffKey = @OrphanKey;

-- AFTER: all three should now read 0 under the orphan key.
SELECT 'AFTER' AS Phase,
       (SELECT COUNT(*) FROM FactAssessmentReading WHERE EnteredByStaffKey = @OrphanKey) AS Reading_Orphans,
       (SELECT COUNT(*) FROM FactAssessmentWriting WHERE EnteredByStaffKey = @OrphanKey) AS Writing_Orphans,
       (SELECT COUNT(*) FROM FactAssessmentMath    WHERE EnteredByStaffKey = @OrphanKey) AS Math_Orphans;

-- Belt-and-suspenders: ANY remaining EnteredBy orphan across the three facts (should be 0 rows).
SELECT 'Reading' AS FactTable, f.ReadingAssessmentID AS KeyValue, f.EnteredByStaffKey
FROM FactAssessmentReading f LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
WHERE d.StaffKey IS NULL
UNION ALL
SELECT 'Writing', f.WritingAssessmentID, f.EnteredByStaffKey
FROM FactAssessmentWriting f LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
WHERE d.StaffKey IS NULL
UNION ALL
SELECT 'Math', f.MathAssessmentID, f.EnteredByStaffKey
FROM FactAssessmentMath f LEFT JOIN DimStaff d ON d.StaffKey = f.EnteredByStaffKey
WHERE d.StaffKey IS NULL;
