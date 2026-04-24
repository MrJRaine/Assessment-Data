/*******************************************************************************
 * Table: FactStaffAssignment
 * Purpose: Bridge of staff-to-school-to-role assignments. One row per distinct
 *          (StaffKey, SchoolID, RoleCode) combination, versioned by effective
 *          dates so the history of someone's role changes is preserved.
 * SCD Type: N/A (temporal bridge — uses EffectiveStartDate/EndDate/IsCurrent)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation. Replaces per-school/per-role columns
 *                       that used to live on DimStaff and replaces StaffSchoolAccess
 *                       as the source of truth for admin/analyst school access.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Preserves the full grain of the PowerSchool staff export (one row per staff-
-- school-role combination) so information about multi-school and multi-role
-- staff is not lost when collapsing to a single DimStaff row per person.
--
-- Example: a vice-principal who also teaches one class at School A produces
-- two rows here (one RoleCode='Administrator', one RoleCode='Teacher'), plus
-- a single DimStaff row keyed by their email.
--
-- Source of truth for:
--   * School-level RLS for admins and regional analysts
--     (see sql/security/vw_StaffSchoolAccess.sql — a view over this table)
--   * Historical "who held what role at which school" reporting
--
-- NOT used for section-level RLS — that still comes from FactSectionTeachers
-- (driven by the sections export, not the staff export).
--
-- Rebuild rules on staff ingest:
--   Pass 1 — for each (StaffKey, SchoolID, RoleCode) triple in the staging load:
--     * If the exact triple is already IsCurrent=1 -> leave alone, touch LastUpdated
--     * If new                                    -> INSERT with EffectiveStartDate
--                                                    = import date, IsCurrent=1
--   Pass 2 — anti-join: triples currently IsCurrent=1 but absent from staging:
--     * UPDATE to set EffectiveEndDate = import date - 1, IsCurrent = 0
--   Rows are never deleted.

CREATE TABLE FactStaffAssignment (
    StaffAssignmentID   BIGINT          NOT NULL IDENTITY,  -- Surrogate key
    StaffKey            BIGINT          NOT NULL,           -- References DimStaff.StaffKey
    SchoolID            VARCHAR(10)     NOT NULL,           -- References DimSchool.SchoolID (4-digit provincial)
    RoleCode            VARCHAR(50)     NOT NULL,           -- 'Teacher', 'Administrator', 'Specialist', 'RegionalAnalyst', etc.
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = currently held
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,               -- PowerSchool staff record ID for this specific email x school x role row
    LastUpdated         DATETIME2(0)    NOT NULL
);
