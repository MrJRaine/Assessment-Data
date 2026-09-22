/*******************************************************************************
 * Script: grant_dev_projectlead_access.sql   (DEV / TEST ONLY)
 * Purpose: Give the project lead access on the freshly-ingested dev test set,
 *          without re-ingesting the staff file:
 *          1. A DimStaff RegionalAnalyst row (analyst scope for /enter, group
 *             picker, reports) — the ingest rebuilt DimStaff without this email.
 *          2. StaffAppAccess.IsSysAdmin = 1 (super-user for /cycles, /ingest,
 *             maintenance). This table is keyed by EMAIL and is NOT cleared by
 *             resets, so it likely already exists — this just guarantees it.
 *
 * Idempotent: the DimStaff insert is guarded on "no current row for this email";
 *   the StaffAppAccess grant is DELETE + INSERT.
 *
 * NOTE — survives only until the next staff re-ingest: if you later re-run the
 *   ingest with a staff file that OMITS this email, usp_MergeStaff will close this
 *   DimStaff row (anti-join deactivation). The generator now includes this account,
 *   so re-uploading StaffExport.csv is the durable path; this script is the quick
 *   one for the data already loaded. StaffAppAccess is unaffected by ingest.
 *
 * Change @Email if your dev sign-in UPN differs.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @Email VARCHAR(255) = 'jeffrey.raine@tcrce.ca';   -- your dev Entra UPN (lowercased)

-- ===== 1) Analyst scope: DimStaff RegionalAnalyst row (guarded — no dup current row) =====
IF NOT EXISTS (SELECT 1 FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) AND IsCurrent = 1)
    INSERT INTO DimStaff (
        Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool,
        IsDistrictLevel, ActiveFlag, AccessLevel,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
    )
    VALUES (
        LOWER(@Email), 'Jeffrey', 'Raine', 'Board Director', NULL, '0716;0079;1178',
        1, 1, 'RegionalAnalyst',
        CAST(GETDATE() AS DATE), NULL, 1, GETDATE()
    );

-- ===== 1b) Analyst SCHOOL SCOPE: StaffSchoolAccess rows (analyst RLS is now StaffSchoolAccess-gated) =====
-- The RegionalAnalyst branch of every RLS TVF/view now requires the student's school to be in the
-- caller's StaffSchoolAccess (their CanChangeSchool buildings) -- there is no region-wide branch.
-- The ingest builds these rows; a manual DimStaff insert does not, so add them here. All active
-- schools => this account sees everything (a true region-wide analyst = every building listed).
DELETE FROM StaffSchoolAccess WHERE LOWER(Email) = LOWER(@Email);
INSERT INTO StaffSchoolAccess (StaffKey, Email, SchoolID, AccessLevel, LastRebuilt)
SELECT d.StaffKey, LOWER(@Email), sch.SchoolID, 'RegionalAnalyst', GETDATE()
FROM DimStaff d
CROSS JOIN DimSchool sch
WHERE LOWER(d.Email) = LOWER(@Email) AND d.IsCurrent = 1
  AND sch.ActiveFlag = 1;

-- ===== 2) Sysadmin: StaffAppAccess super-user (email-keyed; DELETE + INSERT = idempotent) =====
DELETE FROM StaffAppAccess WHERE LOWER(Email) = LOWER(@Email);
INSERT INTO StaffAppAccess (Email, IsSysAdmin, CanManageCycles, CanRunIngest, LastUpdated)
VALUES (LOWER(@Email), 1, 1, 1, GETDATE());

-- ===== Verify =====
SELECT 'DimStaff' AS Source, Email, AccessLevel, IsCurrent, ActiveFlag
FROM DimStaff WHERE LOWER(Email) = LOWER(@Email) AND IsCurrent = 1;

SELECT 'StaffAppAccess' AS Source, Email, IsSysAdmin, CanManageCycles, CanRunIngest
FROM StaffAppAccess WHERE LOWER(Email) = LOWER(@Email);

SELECT 'StaffSchoolAccess' AS Source, COUNT(*) AS Schools
FROM StaffSchoolAccess WHERE LOWER(Email) = LOWER(@Email);
