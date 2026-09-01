/*******************************************************************************
 * Seed: StaffAppAccess — initial admin capabilities
 * Purpose: Grant the starting administrator both app capabilities so access
 *          isn't lost when the /cycles and /ingest gates switch from the
 *          RegionalAnalyst role to this table. Adjust the list for your admins.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * To ADD a person:      INSERT one row with the flags they should have.
 * To CHANGE someone:    UPDATE StaffAppAccess SET CanManageCycles = 0/1 ... WHERE Email = ...
 * To REMOVE all access: DELETE the row (or set both flags to 0).
 * Emails are matched case-insensitively; store them lowercased.
 *
 * Run once after StaffAppAccess.sql. Idempotent guard avoids a duplicate row.
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM StaffAppAccess WHERE Email = 'jeffrey.raine@tcrce.ca')
    INSERT INTO StaffAppAccess (Email, CanManageCycles, CanRunIngest, LastUpdated)
    VALUES ('jeffrey.raine@tcrce.ca', 1, 1, GETDATE());
GO

SELECT Email, CanManageCycles, CanRunIngest FROM StaffAppAccess ORDER BY Email;
