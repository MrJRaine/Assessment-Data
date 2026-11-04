/*******************************************************************************
 * Script: list_srhs_specialist_access_staff.sql
 * Purpose: List staff holding LST/Resource-teacher-tier access (AccessLevel
 *          'SpecialistTeacher') at SRHS, with name, email, PS title, whether it
 *          came from a role override, and their other school scopes.
 * Created: 2026-11-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  StaffSchoolAccess, DimStaff, StaffRoleOverride
 * Writes: nothing (read-only)
 *
 * Notes:
 *   - StaffSchoolAccess is the materialized access oracle (rebuilt every staff
 *     merge, role overrides already applied via DimStaff.AccessLevel), so this
 *     IS effective access as the app enforces it right now — no history.
 *   - 'SpecialistTeacher' covers every PS role mapped there, not only Resource
 *     Teacher (45): registrars (19) and counselors (21/23/37) land in the same
 *     tier. The Title column shows which flavour each person is.
 *   - Staff name + work email are not PII; results are fine to discuss.
 ******************************************************************************/

DECLARE @SchoolID VARCHAR(10) = '0716';   -- SRHS (Shelburne Regional High School)

SELECT
    ds.FirstName + ' ' + ds.LastName AS StaffName,
    ssa.Email,
    ds.Title                         AS PSTitle,         -- e.g. 'Resource Teacher', 'Counselor'
    ssa.AccessLevel,
    CASE WHEN sro.Email IS NOT NULL THEN 'Yes (' + COALESCE(sro.Notes, 'no note') + ')'
         ELSE 'No' END               AS ViaOverride,
    ds.HomeSchoolID,
    oth.OtherSchools                                      -- other schools this access extends to
FROM StaffSchoolAccess ssa
INNER JOIN DimStaff ds
        ON ds.StaffKey = ssa.StaffKey
LEFT  JOIN StaffRoleOverride sro
        ON sro.Email = LOWER(ssa.Email)
       AND sro.ActiveFlag = 1
       AND sro.OverrideRole = 'SpecialistTeacher'
OUTER APPLY (
    SELECT STRING_AGG(x.SchoolID, ', ') AS OtherSchools
    FROM (SELECT DISTINCT ssa2.SchoolID
          FROM StaffSchoolAccess ssa2
          WHERE ssa2.Email = ssa.Email
            AND ssa2.SchoolID <> @SchoolID) x
) oth
WHERE ssa.SchoolID = @SchoolID
  AND ssa.AccessLevel = 'SpecialistTeacher'
ORDER BY ds.LastName, ds.FirstName;
