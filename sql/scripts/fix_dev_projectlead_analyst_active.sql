/*******************************************************************************
 * Script: fix_dev_projectlead_analyst_active.sql   (DEV / TEST ONLY)
 * Purpose: The project lead resolves to "No cycles" because a re-ingest/merge left
 *          TWO DimStaff rows for the email: a RegionalAnalyst row (ActiveFlag 1) AND
 *          a NEWER deactivation marker (AccessLevel NULL, ActiveFlag 0 -- the anti-join
 *          row from an ingest whose staff file omitted the email). If that NULL row is
 *          IsCurrent = 1, the caller resolves to no AccessLevel -> teacher branch ->
 *          empty roster -> "No cycles" everywhere.
 *
 *          This COLLAPSES the stack to a SINGLE current, active RegionalAnalyst row and
 *          rebuilds StaffSchoolAccess (all active schools) + StaffAppAccess (sysadmin).
 *          Unlike grant_dev_projectlead_access.sql (guarded insert, no-ops when a current
 *          row already exists), this repairs a bad/duplicated current row. Idempotent.
 *
 * Reads/Writes: DimStaff (IsCurrent / ActiveFlag / EffectiveEndDate on this email's rows),
 *          StaffSchoolAccess (DELETE+INSERT), StaffAppAccess (DELETE+INSERT). No PII. DEV only.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Email   VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- dev sign-in UPN (lowercased)
DECLARE @KeepKey BIGINT;

-- 1) Row to keep = the newest RegionalAnalyst row for this email.
SELECT TOP 1 @KeepKey = StaffKey
FROM DimStaff
WHERE LOWER(Email) = LOWER(@Email) AND AccessLevel = 'RegionalAnalyst'
ORDER BY EffectiveStartDate DESC, StaffKey DESC;

IF @KeepKey IS NULL
BEGIN
    ;THROW 60001, 'fix_dev_projectlead_analyst_active: no RegionalAnalyst DimStaff row exists for this email. Run grant_dev_projectlead_access.sql first to create one, then re-run this.', 1;
END;

-- 2) End EVERY other current row for the email (clears the NULL-access deactivation
--    marker and any stacked IsCurrent markers).
UPDATE DimStaff
SET IsCurrent        = 0,
    EffectiveEndDate = COALESCE(EffectiveEndDate, CAST(GETDATE() AS DATE)),
    LastUpdated      = GETDATE()
WHERE LOWER(Email) = LOWER(@Email) AND IsCurrent = 1 AND StaffKey <> @KeepKey;

-- 3) Make the kept RegionalAnalyst row the sole current, active row.
UPDATE DimStaff
SET IsCurrent = 1, ActiveFlag = 1, EffectiveEndDate = NULL, LastUpdated = GETDATE()
WHERE StaffKey = @KeepKey;

-- 4) Analyst school scope = all active schools (a region-wide analyst = every building listed).
DELETE FROM StaffSchoolAccess WHERE LOWER(Email) = LOWER(@Email);
INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
SELECT @KeepKey, LOWER(@Email), sch.SchoolID, 'RegionalAnalyst', GETDATE()
FROM DimSchool sch
WHERE sch.ActiveFlag = 1;

-- 5) Sysadmin super-user (email-keyed; survives ingest).
DELETE FROM StaffAppAccess WHERE LOWER(Email) = LOWER(@Email);
INSERT INTO StaffAppAccess (Email, IsSysAdmin, CanManageCycles, CanRunIngest, LastUpdated)
VALUES (LOWER(@Email), 1, 1, 1, GETDATE());

-- ===== Verify: exactly ONE current row, RegionalAnalyst + active; school count; sysadmin =====
SELECT 'DimStaff current' AS Check_, COUNT(*) AS CurrentRows,
       MAX(AccessLevel) AS AccessLevel, MAX(CAST(ActiveFlag AS INT)) AS ActiveFlag
FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) AND IsCurrent = 1;

SELECT 'StaffSchoolAccess' AS Check_, COUNT(*) AS Schools
FROM StaffSchoolAccess WHERE LOWER(Email) = LOWER(@Email);

SELECT 'StaffAppAccess' AS Check_, IsSysAdmin, CanManageCycles, CanRunIngest
FROM StaffAppAccess WHERE LOWER(Email) = LOWER(@Email);
