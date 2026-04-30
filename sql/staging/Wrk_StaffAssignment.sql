/*******************************************************************************
 * Table: Wrk_StaffAssignment
 * Purpose: Per-import-row working set for FactStaffAssignment merge. ONE row
 *          per Stg_Staff row (so itinerant staff with N school assignments
 *          contribute N rows). Populated by usp_MergeStaff from Stg_Staff with:
 *            - Email lowercased (matches Wrk_StaffPersons / DimStaff)
 *            - SchoolID '0' -> '0000' (district-tier aggregate marker)
 *            - SchoolID otherwise zero-padded to 4 chars
 *            - RoleCode resolved via JOIN DimRole on PS Group number
 *              (rows with no DimRole match are excluded from this Wrk and
 *              logged as a warning by usp_MergeStaff)
 *            - SourceSystemID (PS staff ID) carried verbatim
 *
 *          StaffKey is intentionally NOT stored here — the FactStaffAssignment
 *          merge resolves it at query time via JOIN DimStaff on Email +
 *          IsCurrent = 1 after the DimStaff merge has run.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_StaffAssignment (
    Email               VARCHAR(255)    NOT NULL,
    SchoolID            VARCHAR(10)     NOT NULL,
    RoleCode            VARCHAR(50)     NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL
);
