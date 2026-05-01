/*******************************************************************************
 * Script: migrate_DimRole_22_32_to_Teacher.sql
 * Purpose: Reclassify PS RoleNumbers 22 (IB/O2/Co-op Coordinators) and 32
 *          (APSEA Itinerant Teachers) from RoleCode 'SpecialistTeacher' to
 *          'Teacher'. Both groups ARE teachers (vs the remaining
 *          SpecialistTeacher list which is admin-tier — counsellors,
 *          registrars, resource teachers).
 *
 * Side effect: removes the only AccessLevel-branching case in the
 * SchoolAdmins DAX RLS — Administrator and remaining SpecialistTeacher now
 * have identical staff-visibility rules (both see school-tier staff).
 *
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Run order:
 *   1. This script — UPDATEs the two DimRole rows.
 *   2. usp_MergeStaff (or full usp_RunFullIngestCycle) — cascades the
 *      RoleCode change through FactStaffAssignment via the standard
 *      anti-join pattern (old triples close, new triples open) and
 *      recomputes DimStaff.AccessLevel (any staff member with ONLY
 *      groups 22/32 will have AccessLevel transition from
 *      'SpecialistTeacher' to NULL — they drop out of vw_StaffSchoolAccess).
 *
 * Verification after migration:
 *   SELECT RoleNumber, RoleName, RoleCode FROM DimRole WHERE RoleNumber IN (22, 32);
 *   -- expect: both rows show RoleCode = 'Teacher'
 *
 * Idempotent: safe to re-run.
 ******************************************************************************/

UPDATE DimRole
SET RoleCode    = 'Teacher',
    LastUpdated = GETDATE()
WHERE RoleNumber IN (22, 32)
  AND RoleCode = 'SpecialistTeacher';
