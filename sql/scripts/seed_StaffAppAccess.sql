/*******************************************************************************
 * Seed: StaffAppAccess — initial admin capabilities
 * Purpose: Grant the starting administrator sysAdmin so access isn't lost when
 *          the /cycles and /ingest gates switch to this table, and so they can
 *          run the FIRST ingest after a production reset (DimStaff empty). Adjust
 *          the list for your admins. IsSysAdmin implies every capability.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * To ADD a sysadmin:    INSERT a row with IsSysAdmin = 1 (implies all).
 * To ADD a scoped user: INSERT with IsSysAdmin = 0 + the specific flags they need.
 * To CHANGE someone:    UPDATE StaffAppAccess SET IsSysAdmin = 0/1 ... WHERE Email = ...
 * To REMOVE all access: DELETE the row (or set every flag to 0).
 * Emails are matched case-insensitively; store them lowercased.
 *
 * Run once after StaffAppAccess.sql. Idempotent guard avoids a duplicate row.
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM StaffAppAccess WHERE Email = 'jeffrey.raine@tcrce.ca')
    INSERT INTO StaffAppAccess (Email, IsSysAdmin, CanManageCycles, CanRunIngest, LastUpdated)
    VALUES ('jeffrey.raine@tcrce.ca', 1, 0, 0, GETDATE());   -- sysAdmin: implies cycles + ingest
GO

SELECT Email, IsSysAdmin, CanManageCycles, CanRunIngest FROM StaffAppAccess ORDER BY Email;
