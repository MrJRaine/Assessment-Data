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
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Type 2 attributes (trigger a new version): ActiveFlag
-- Type 1 attributes (update in place): FirstName, LastName
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
-- ActiveFlag lifecycle (import-driven, not pulled from PowerSchool):
--   Staff are exported from a PowerSchool report that filters to currently active
--   staff only (teachers, school specialists, and administrators). Every row in
--   the import is active by definition. The merge procedure derives ActiveFlag
--   via reconciliation against prior DimStaff state:
--     * In current import & not in warehouse          -> INSERT new row, ActiveFlag = 1
--     * In current import & currently active          -> Type 1 update for name only
--     * In current import & currently inactive        -> returning staff;
--                                                        close inactive row, INSERT
--                                                        new version with ActiveFlag = 1
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
    ActiveFlag          BIT             NOT NULL,           -- Type 2 trigger; derived via import reconciliation
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    LastUpdated         DATETIME2(0)    NOT NULL
);
