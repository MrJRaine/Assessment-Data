/*******************************************************************************
 * Script: diag_staff_katrina_mood_2026-10-22.sql   (READ ONLY)
 * Purpose: Pull DimStaff + all the access/"tagging" data for one staff member —
 *          identity, the per-(school x role) assignment bridge, the materialized
 *          RLS school-access tags, any manual role override, and app capabilities.
 * Email:   katrina.mood@tcrce.ca (lowercased at ingest; matched with LOWER()).
 *
 * Reads:   DimStaff, FactStaffAssignment, StaffSchoolAccess, DimSchool,
 *          StaffRoleOverride, StaffAppAccess. Staff email + role/school metadata
 *          are public (NOT student PII). Writes: NOTHING.
 * Region:  Canada East (PIIDPA compliant). The user runs this; Claude does not.
 ******************************************************************************/

SET NOCOUNT ON;
DECLARE @Email VARCHAR(255) = 'katrina.mood@tcrce.ca';

-- (1) DimStaff — identity, ALL SCD versions (IsCurrent = 1 is the live row).
SELECT
    StaffKey, Email, FirstName, LastName, Title,
    HomeSchoolID, CanChangeSchool, IsDistrictLevel,
    ActiveFlag, AccessLevel,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
FROM DimStaff
WHERE LOWER(Email) = LOWER(@Email)
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;

-- (2) FactStaffAssignment — the email x school x role bridge (what PS assigns),
--     joined to DimStaff by StaffKey. Shows current + historical assignments.
SELECT
    fsa.StaffAssignmentID, fsa.StaffKey, d.Email,
    fsa.SchoolID, sch.SchoolName, fsa.RoleCode,
    fsa.EffectiveStartDate, fsa.EffectiveEndDate, fsa.IsCurrent, fsa.SourceSystemID, fsa.LastUpdated
FROM FactStaffAssignment fsa
JOIN DimStaff d        ON d.StaffKey = fsa.StaffKey
LEFT JOIN DimSchool sch ON sch.SchoolID = fsa.SchoolID
WHERE LOWER(d.Email) = LOWER(@Email)
ORDER BY fsa.IsCurrent DESC, fsa.SchoolID, fsa.RoleCode, fsa.EffectiveStartDate DESC;

-- (3) StaffSchoolAccess — materialized RLS tags (the schools + AccessLevel that scope their reads).
SELECT ssa.StaffKey, ssa.Email, ssa.SchoolID, sch.SchoolName, ssa.AccessLevel
FROM StaffSchoolAccess ssa
LEFT JOIN DimSchool sch ON sch.SchoolID = ssa.SchoolID
WHERE LOWER(ssa.Email) = LOWER(@Email)
ORDER BY ssa.SchoolID;

-- (4) StaffRoleOverride — any manual RLS-role override (coaches/Tech Services etc.; blank = none).
SELECT Email, OverrideRole, Notes, ActiveFlag, LastUpdated
FROM StaffRoleOverride
WHERE LOWER(Email) = LOWER(@Email);

-- (5) StaffAppAccess — app capabilities (sysadmin / cycles / ingest / overrides / maintenance; blank = none).
SELECT Email, IsSysAdmin, CanManageCycles, CanRunIngest,
       CanOverrideMath, CanOverrideLiteracy, CanMaintain, LastUpdated
FROM StaffAppAccess
WHERE LOWER(Email) = LOWER(@Email);
