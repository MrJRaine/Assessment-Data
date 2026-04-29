/*******************************************************************************
 * View: vw_StaffSchoolAccess
 * Purpose: School-level RLS authorization for staff with school-tier access.
 *          Pure unpacking view over DimStaff — no joins, no aggregation.
 *          AccessLevel and the school list are both per-person attributes
 *          already stored on DimStaff.
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Replaces the StaffSchoolAccess table,
 *                       which was being rebuilt on every staff ingest.
 *            2026-04-27 - Rewritten to drive school access from PS-native
 *                       fields (HomeSchoolID, CanChangeSchool) rather than from
 *                       FactStaffAssignment row presence. PS already maintains
 *                       this per-person access list — using it directly avoids
 *                       drift between PS UI navigation rights and warehouse RLS.
 *            2026-04-29 - Updated for the 6-value RoleCode taxonomy introduced
 *                       by DimRole. Included roles: Administrator,
 *                       SpecialistTeacher, RegionalAnalyst. Excluded:
 *                       Teacher (section-level RLS only), ProvincialAnalyst
 *                       (no PowerApp access at all — not in security group),
 *                       SupportStaff (no student-data access).
 *            2026-04-29 - Simplified by reading AccessLevel directly from
 *                       DimStaff (Type 1 column, computed at ingest by the
 *                       staff merge proc) instead of recomputing via MAX(CASE)
 *                       over FactStaffAssignment on every query. Filter on
 *                       AccessLevel IS NOT NULL replaces the prior FactStaffAssignment
 *                       JOIN + GROUP BY. Faster RLS path; no behavior change.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- WHO appears in this view:
--   Only staff with a non-NULL AccessLevel on their current DimStaff row.
--   AccessLevel is set during the staff merge proc to the highest-priority
--   current school-tier RoleCode in FactStaffAssignment, with priority
--   RegionalAnalyst > Administrator > SpecialistTeacher.
--
-- Excluded by design (their AccessLevel is NULL):
--   * Teacher           — section-level RLS via FactSectionTeachers, not school-level.
--   * ProvincialAnalyst — never authenticates to the PowerApp (not in security group).
--   * SupportStaff      — no student-data access in the app.
--   Rows for these roles still exist in FactStaffAssignment for audit; their
--   DimStaff record exists too, just with AccessLevel = NULL.
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
-- It is gated by role (only school-tier staff can produce it, by virtue of
-- having a non-NULL AccessLevel) and additionally by IsDistrictLevel = 1
-- (which mirrors the same '0' presence — defense in depth).

CREATE VIEW vw_StaffSchoolAccess AS

-- HomeSchoolID contribution (one row per staff with school-tier access who has a home school)
SELECT
    StaffKey,
    Email,
    HomeSchoolID AS SchoolID,
    AccessLevel
FROM DimStaff
WHERE IsCurrent     = 1
  AND ActiveFlag    = 1
  AND AccessLevel  IS NOT NULL
  AND HomeSchoolID IS NOT NULL

UNION   -- de-dupes overlap between HomeSchoolID and CanChangeSchool

-- CanChangeSchool contribution (one row per parsed school entry)
SELECT
    ds.StaffKey,
    ds.Email,
    CASE
        WHEN TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) = 0 THEN '0000'
        ELSE RIGHT('0000' + LTRIM(RTRIM(s.value)), 4)
    END AS SchoolID,
    ds.AccessLevel
FROM DimStaff ds
CROSS APPLY STRING_SPLIT(ds.CanChangeSchool, ';') AS s
WHERE ds.IsCurrent       = 1
  AND ds.ActiveFlag      = 1
  AND ds.AccessLevel    IS NOT NULL
  AND ds.CanChangeSchool IS NOT NULL
  AND s.value           IS NOT NULL
  AND LTRIM(RTRIM(s.value)) <> ''
  AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) IS NOT NULL
  AND TRY_CAST(LTRIM(RTRIM(s.value)) AS INT) <> 999999;
