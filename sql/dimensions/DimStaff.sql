/*******************************************************************************
 * Table: DimStaff
 * Purpose: Person-level staff identity. One row per unique staff email,
 *          versioned by SCD Type 2 on active/inactive transitions only.
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-24 - Email is now the business key. PowerSchool's staff record
 *                       ID (StaffID) was removed because PowerSchool creates a
 *                       separate record per staff-school combination, making it
 *                       unreliable for identifying a person. StaffNumber removed
 *                       because certification numbers are not in PowerSchool and
 *                       don't cover non-teaching staff.
 *            2026-04-24 - ActiveFlag reclassified as SCD Type 2. Its value is NOT
 *                       pulled from a PowerSchool column — the staff export comes
 *                       from a PS report already filtered to active staff, so
 *                       inclusion implies active. ActiveFlag is derived at ingest
 *                       by reconciling presence against the prior DimStaff state.
 *            2026-04-24 - Moved per-school/per-role detail to FactStaffAssignment
 *                       bridge. DimStaff is now pure person identity. Dropped
 *                       columns: RoleCode, HomeSchoolID, SourceSystemID.
 *                       ActiveFlag is now the ONLY Type 2 trigger.
 *            2026-04-27 - Added per-person access attributes (all Type 1):
 *                       HomeSchoolID, CanChangeSchool, IsDistrictLevel.
 *                       Sourced from PS staff record (joined into the staff
 *                       export). Drives StaffSchoolAccess for non-teaching
 *                       staff school-level RLS.
 *            2026-04-28 - SCD policy change: ALL business attributes are now Type 2
 *                       triggers (FirstName, LastName, HomeSchoolID, CanChangeSchool,
 *                       IsDistrictLevel, ActiveFlag). Same rationale as DimStudent:
 *                       reports cite point-in-time values, and a later re-query
 *                       must reproduce the original numbers regardless of intervening
 *                       name corrections, school reassignments, or access changes.
 *            2026-04-28 - Added Title column (VARCHAR(100) NULL). Pulled from PS
 *                       Title field. Also a Type 2 trigger per the policy above.
 *            2026-04-29 - Added AccessLevel column (VARCHAR(50) NULL). Derived at
 *                       ingest from FactStaffAssignment.RoleCode (highest-priority
 *                       school-tier role per person). Type 1 (overwrite, no SCD
 *                       version) — historical AccessLevel is recoverable from
 *                       FactStaffAssignment's own Type 2 history; on DimStaff this
 *                       is just a denormalized snapshot used by StaffSchoolAccess
 *                       for fast RLS lookups.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- SCD policy: ALL business attributes trigger a new version (Type 2)…
--   …WITH ONE EXCEPTION: AccessLevel is Type 1 (overwrite). It's a derived
--   denormalized snapshot of the staff member's highest-priority school-tier
--   RoleCode in FactStaffAssignment. Historical AccessLevel queries are
--   answered against FactStaffAssignment, not DimStaff.
--
-- Lifecycle/audit columns (never trigger a version):
--   StaffKey, Email, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated
--
-- Type 2 trigger fields (any change creates a new SCD version):
--   FirstName, LastName, Title, HomeSchoolID, CanChangeSchool, IsDistrictLevel, ActiveFlag
--
-- Type 1 fields (overwrite the current row only):
--   AccessLevel
--
-- Business key: Email (normalized to lowercase during ingest)
-- Surrogate key: StaffKey (warehouse-generated, unique per SCD version)
--
-- Multi-school / multi-role handling: PowerSchool exports one row per staff-
-- school-role combination. The staff merge procedure collapses these rows to a
-- single DimStaff record per unique email. All per-school/per-role detail lives
-- in FactStaffAssignment (email x school x role bridge), not here. There is no
-- SourceSystemID on this table because multiple PS records collapse to one
-- DimStaff row — the PS record ID is preserved on each FactStaffAssignment row.
--
-- Per-person access attributes (added 2026-04-27):
--   * HomeSchoolID     — primary/home school. NULL for itinerant staff with no
--                        single primary school.
--   * CanChangeSchool  — raw PS field, semicolon-separated list of provincial
--                        school IDs the user can navigate to in PS. Populated
--                        only when the user has multi-school access. Includes
--                        special markers: '0' (district-level tier), '999999'
--                        (graduates pseudo-school — should not appear for staff).
--                        Parsed live by StaffSchoolAccess.
--   * IsDistrictLevel  — derived flag set at ingest: 1 if '0' appears in the
--                        CanChangeSchool list, else 0. Drives whether the
--                        '0000' aggregate row surfaces for the user in
--                        StaffSchoolAccess.
--
-- ActiveFlag lifecycle (import-driven, not pulled from PowerSchool):
--   Staff are exported from a PowerSchool report that filters to currently active
--   staff only (teachers, school specialists, and administrators). Every row in
--   the import is active by definition. The merge procedure derives ActiveFlag
--   via reconciliation against prior DimStaff state. Combined with the
--   all-Type-2 policy, the merge logic per email is:
--     * Email not in warehouse                        -> INSERT new row, ActiveFlag = 1
--     * Email in warehouse & current row matches all  -> no-op (touch LastUpdated)
--       fields in import (incl. ActiveFlag = 1)
--     * Email in warehouse & ANY business field       -> close current row, INSERT
--       differs (name correction, HomeSchoolID,          new version with updated values
--       access list, returning from inactive, etc.)      and ActiveFlag = 1
--     * NOT in current import & currently active      -> close active row, INSERT
--                                                        new version with ActiveFlag = 0
--     * NOT in current import & currently inactive    -> no change
--   Inactive does NOT mean no-longer-employed. Possible causes: on leave,
--   sabbatical, retired, role change, left the region. Rows are retained (never
--   deleted) to preserve historical joins on StaffKey from fact tables.

CREATE TABLE DimStaff (
    StaffKey            BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    Email               VARCHAR(255)    NOT NULL,           -- Business key (Entra ID UPN, lowercased)
    FirstName           VARCHAR(100)    NOT NULL,
    LastName            VARCHAR(100)    NOT NULL,
    Title               VARCHAR(100)    NULL,               -- PS Title (e.g. "Vice Principal", "Educational Assistant")
    HomeSchoolID        VARCHAR(10)     NULL,               -- Primary school; NULL for itinerant staff
    CanChangeSchool     VARCHAR(255)    NULL,               -- Raw PS semicolon-separated school list
    IsDistrictLevel     BIT             NOT NULL,           -- Derived: '0' present in CanChangeSchool
    ActiveFlag          BIT             NOT NULL,           -- Derived at ingest via import reconciliation
    AccessLevel         VARCHAR(50)     NULL,               -- Type 1 — derived per-person from FactStaffAssignment highest-priority school-tier role: 'RegionalAnalyst' / 'Administrator' / 'SpecialistTeacher'. NULL for staff with no school-tier access (Teacher-only, ProvincialAnalyst, SupportStaff).
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
