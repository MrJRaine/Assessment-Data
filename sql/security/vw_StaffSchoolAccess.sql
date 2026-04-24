/*******************************************************************************
 * View: vw_StaffSchoolAccess
 * Purpose: School-level RLS authorization for admins and regional analysts.
 *          Derived at query time from FactStaffAssignment — single source of truth,
 *          no rebuild step needed.
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Replaces the StaffSchoolAccess table,
 *                       which was being rebuilt on every staff ingest from the
 *                       same source data this view now derives live.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Access rules encoded here:
--   RoleCode = 'Administrator'    -> one row per school where they hold that role
--   RoleCode = 'RegionalAnalyst'  -> one row per school where they hold that role
--     (Regional analysts' full-district view can additionally be granted by
--      the Power BI semantic model RLS role; it is not materialized here.)
--   RoleCode = 'Teacher'          -> NOT surfaced by this view. Teachers use
--                                    section-level RLS via FactSectionTeachers.
--
-- Changes to access come from the PowerSchool staff report only — adding/removing
-- a role at a school updates FactStaffAssignment, which flows through this view
-- automatically on the next query.

CREATE VIEW vw_StaffSchoolAccess AS
SELECT
    fsa.StaffKey,
    ds.Email,
    fsa.SchoolID,
    fsa.RoleCode AS AccessLevel
FROM FactStaffAssignment fsa
JOIN DimStaff ds
    ON ds.StaffKey = fsa.StaffKey
WHERE fsa.IsCurrent = 1
  AND ds.IsCurrent = 1
  AND ds.ActiveFlag = 1
  AND fsa.RoleCode IN ('Administrator', 'RegionalAnalyst');
