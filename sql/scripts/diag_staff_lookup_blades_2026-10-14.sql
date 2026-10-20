/*******************************************************************************
 * Script: diag_staff_lookup_blades_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: 'kimberly.blades@tcrce.ca' returned nothing — find the real record. Searches
 *          DimStaff (ALL versions) + the raw Stg_Staff landing by last name / partial email,
 *          to catch a different email form (e.g. kim.blades) or a PowerSchool typo.
 *
 * Reads:  DimStaff, Stg_Staff, DimRole. Staff name/email are NOT PII. No student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Needle VARCHAR(100) = 'blades';   -- last-name / email fragment to search for

-- (1) DimStaff — any version whose email or last name contains the needle.
SELECT
    d.StaffKey, d.Email, d.FirstName, d.LastName,
    d.AccessLevel, d.HomeSchoolID, d.IsDistrictLevel,
    d.IsCurrent, d.EffectiveStartDate, d.EffectiveEndDate
FROM DimStaff d
WHERE LOWER(d.Email) LIKE '%' + LOWER(@Needle) + '%'
   OR LOWER(d.LastName) LIKE '%' + LOWER(@Needle) + '%'
ORDER BY d.LastName, d.FirstName, d.IsCurrent DESC, d.EffectiveStartDate;

-- (2) Raw staging (Stg_Staff) — the last ingested PS staff rows (shows email + PS Group + its role).
--     Catches someone present in PowerSchool but under a different email than expected.
SELECT DISTINCT
    LOWER(s.Email_Addr)  AS Email,
    s.[Group]            AS PSGroup,
    r.RoleCode           AS MapsToRole,
    s.SchoolID
FROM Stg_Staff s
LEFT JOIN DimRole r ON TRY_CAST(s.[Group] AS INT) = r.RoleNumber AND r.ActiveFlag = 1
WHERE LOWER(s.Email_Addr) LIKE '%' + LOWER(@Needle) + '%'
ORDER BY Email, s.SchoolID;
