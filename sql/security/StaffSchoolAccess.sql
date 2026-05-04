/*******************************************************************************
 * Table: StaffSchoolAccess
 * Purpose: Materialized RLS-oracle for school-tier staff access. Replaces the
 *          prior vw_StaffSchoolAccess view (2026-04-29 design — pure DimStaff
 *          unpacking) with a TABLE rebuilt on every staff merge. Same data
 *          shape, same derivation logic, same staleness; the only difference
 *          is materialization.
 * Created: 2026-05-04
 * SCD: None — full rebuild on every usp_MergeStaff run (TRUNCATE + INSERT).
 *      No history retained; this is an access-snapshot, not a fact.
 * Region: Canada East (PIIDPA compliant)
 *
 * Why materialize?
 *   The Power BI semantic model RLS expressions need the full DAX surface
 *   (notably `[Column] IN tablevar`, which compiles to CONTAINSROW). Direct
 *   Lake on SQL forces RLS through the SQL endpoint with the DirectQuery
 *   DAX subset — CONTAINSROW is blocked there. Switching the model to
 *   Direct Lake on OneLake gives full DAX RLS, but OneLake mode does NOT
 *   permit views in the model. Materializing this view as a Delta table
 *   resolves both: the model includes the table under OneLake mode, and
 *   RLS expressions get the full DAX surface.
 *
 *   Also aligns with the project's documented preference (memory:
 *   feedback_no_live_ps_connection) — materialization on ingest is
 *   preferred for any RLS / lookup / pre-aggregation use case in this
 *   project: same staleness as a view, faster queries, lower capacity
 *   utilization.
 *
 * No-manual-entries principle preserved:
 *   This table is fully derived from authoritative DimStaff data on every
 *   ingest — same guarantee the prior view provided. No manual rows ever.
 *
 * Rebuild trigger:
 *   usp_MergeStaff Step 6 — runs after DimStaff and FactStaffAssignment
 *   reconciliation. Logic identical to the prior view: union of HomeSchoolID
 *   contribution + parsed CanChangeSchool entries (with '999999' stripped,
 *   '0' rewritten to '0000', others zero-padded to 4).
 *
 * WHO appears:
 *   Only staff with a non-NULL AccessLevel on their current DimStaff row:
 *   Administrator, SpecialistTeacher, RegionalAnalyst.
 *
 * Excluded by design (their AccessLevel is NULL):
 *   - Teacher           — section-level RLS via FactSectionTeachers.
 *   - ProvincialAnalyst — never authenticates to the PowerApp.
 *   - SupportStaff      — no student-data access in the app.
 *
 * Consumers:
 *   - vw_SchoolStudents (SQL-layer RLS view consumed by Power Apps)
 *   - Power BI semantic model Assessment_Analytics (DAX RLS oracle)
 ******************************************************************************/

CREATE TABLE StaffSchoolAccess (
    StaffSchoolAccessID BIGINT       NOT NULL IDENTITY,
    StaffKey            BIGINT       NOT NULL,
    Email               VARCHAR(255) NOT NULL,
    SchoolID            VARCHAR(10)  NOT NULL,
    AccessLevel         VARCHAR(50)  NOT NULL,
    LastRebuilt         DATETIME2(0) NOT NULL
);
