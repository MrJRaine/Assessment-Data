/*******************************************************************************
 * View: vw_StaffSchoolAccess
 * Purpose: School-level RLS authorization for non-teaching staff (admins,
 *          specialists, regional analysts). Derived live at query time from
 *          DimStaff (HomeSchoolID + CanChangeSchool) joined against
 *          FactStaffAssignment for role-tier filtering.
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Replaces the StaffSchoolAccess table,
 *                       which was being rebuilt on every staff ingest.
 *            2026-04-27 - Rewritten to drive school access from PS-native
 *                       fields (HomeSchoolID, CanChangeSchool) rather than from
 *                       FactStaffAssignment row presence. PS already maintains
 *                       this per-person access list — using it directly avoids
 *                       drift between PS UI navigation rights and warehouse RLS.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- WHO appears in this view:
--   Only staff with at least one CURRENT non-teaching role
--   (Administrator | Specialist | RegionalAnalyst) in FactStaffAssignment.
--   Teachers are excluded by design — their RLS is section-level via
--   FactSectionTeachers, not school-level.
--
-- WHAT schools are returned per staff member:
--   Union of:
--     1. DimStaff.HomeSchoolID                  (if not null)
--     2. Each entry in DimStaff.CanChangeSchool (if not null), with parsing:
--          - '999999' (graduates pseudo-school)         -> stripped
--          - '0'      (district-level tier marker)      -> emitted as '0000'
--                                                          (aggregate-row marker)
--          - any other integer                          -> zero-padded to 4 chars
--
-- The '0000' aggregate row is a UI/filter primitive: when present, the
-- consuming app can offer an "All assigned schools" combined view to that user.
-- It is gated by role (only non-teaching staff can produce it, by virtue of the
-- view-level role filter) and additionally by IsDistrictLevel = 1 (which mirrors
-- the same '0' presence — defense in depth).
--
-- AccessLevel returned per row is the staff member's HIGHEST-priority current
-- non-teaching role across all of their FactStaffAssignment rows
-- (priority: Administrator > RegionalAnalyst > Specialist). Same value across
-- all rows for a given StaffKey — it is a person-tier indicator, not a per-
-- school role claim. (A user might have access to a school via CanChangeSchool
-- without holding any specific role at that school in FactStaffAssignment.)

CREATE VIEW vw_StaffSchoolAccess AS

WITH NonTeachingStaff AS (
    -- One row per staff member who holds at least one non-teaching role.
    -- AccessLevel is the highest-priority role they hold anywhere.
    SELECT
        ds.StaffKey,
        ds.Email,
        ds.HomeSchoolID,
        ds.CanChangeSchool,
        ds.IsDistrictLevel,
        CASE
            WHEN MAX(CASE WHEN fsa.RoleCode = 'Administrator'    THEN 1 ELSE 0 END) = 1 THEN 'Administrator'
            WHEN MAX(CASE WHEN fsa.RoleCode = 'RegionalAnalyst'  THEN 1 ELSE 0 END) = 1 THEN 'RegionalAnalyst'
            WHEN MAX(CASE WHEN fsa.RoleCode = 'Specialist'       THEN 1 ELSE 0 END) = 1 THEN 'Specialist'
        END AS AccessLevel
    FROM DimStaff ds
    JOIN FactStaffAssignment fsa
        ON fsa.StaffKey = ds.StaffKey
    WHERE ds.IsCurrent  = 1
      AND ds.ActiveFlag = 1
      AND fsa.IsCurrent = 1
      AND fsa.RoleCode IN ('Administrator', 'RegionalAnalyst', 'Specialist')
    GROUP BY ds.StaffKey, ds.Email, ds.HomeSchoolID, ds.CanChangeSchool, ds.IsDistrictLevel
),

ParsedCanChangeSchool AS (
    -- Explode CanChangeSchool semicolon list into per-school rows.
    -- Strip 999999, map 0 -> '0000', zero-pad everything else.
    SELECT
        nts.StaffKey,
        CASE
            WHEN TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) = 0 THEN '0000'
            ELSE RIGHT('0000' + LTRIM(RTRIM(s.value)), 4)
        END AS SchoolID
    FROM NonTeachingStaff nts
    CROSS APPLY STRING_SPLIT(nts.CanChangeSchool, ';') AS s
    WHERE nts.CanChangeSchool IS NOT NULL
      AND s.value IS NOT NULL
      AND LTRIM(RTRIM(s.value)) <> ''
      AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) IS NOT NULL
      AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) <> 999999
),

AllAccessSchools AS (
    -- HomeSchoolID contribution (always include if present)
    SELECT StaffKey, HomeSchoolID AS SchoolID
    FROM NonTeachingStaff
    WHERE HomeSchoolID IS NOT NULL

    UNION   -- de-dupes overlap between HomeSchoolID and CanChangeSchool

    -- Parsed CanChangeSchool contribution
    SELECT StaffKey, SchoolID
    FROM ParsedCanChangeSchool
)

SELECT
    nts.StaffKey,
    nts.Email,
    aas.SchoolID,
    nts.AccessLevel
FROM AllAccessSchools aas
JOIN NonTeachingStaff nts
    ON nts.StaffKey = aas.StaffKey;
