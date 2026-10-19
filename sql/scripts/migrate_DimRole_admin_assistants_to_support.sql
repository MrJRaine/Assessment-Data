/*******************************************************************************
 * Migration: DimRole — reclassify admin assistants to SupportStaff (1.3.0)
 * Purpose: The DimRole seed (sql/dimensions/DimRole.sql) is a one-time CREATE+INSERT.
 *          The live/dev warehouse already holds the table, so this UPDATE applies the
 *          2026-10-19 reclassification of the four "Admin Assistant" PS groups
 *          (RoleNumbers 11, 13, 17, 20) from 'Administrator' to 'SupportStaff'.
 * Created: 2026-10-19 (1.3.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads/Writes: DimRole (RoleCode for RoleNumber IN (11,13,17,20))
 *
 * Effect on the merge: with the usp_MergeStaff write rule (persist a person only if
 * they hold an access role, teach a section, or carry a manual override), these groups
 * now resolve to SupportStaff (no access) and — unless they also teach — fall out of
 * Wrk_StaffPersons on the NEXT ingest, which closes out their DimStaff rows and drops
 * them from StaffSchoolAccess. No student data is affected.
 *
 * Idempotent: re-running changes nothing once the four rows already read SupportStaff.
 ******************************************************************************/

UPDATE DimRole
SET RoleCode    = 'SupportStaff',
    LastUpdated = GETDATE()
WHERE RoleNumber IN (11, 13, 17, 20)
  AND RoleCode <> 'SupportStaff';

-- Verify (optional): expect all four to read SupportStaff.
-- SELECT RoleNumber, RoleName, RoleCode FROM DimRole WHERE RoleNumber IN (11,13,17,20) ORDER BY RoleNumber;
