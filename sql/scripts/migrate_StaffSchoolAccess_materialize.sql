/*******************************************************************************
 * Script: migrate_StaffSchoolAccess_materialize.sql
 * Purpose: Replace the dynamic vw_StaffSchoolAccess view with a materialized
 *          StaffSchoolAccess table. Rebuilt on every usp_MergeStaff run.
 *          See sql/security/StaffSchoolAccess.sql for the full rationale.
 *
 * Created: 2026-05-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Why: The Power BI semantic model needs RLS expressions to use the full DAX
 *      surface (notably `[Column] IN tablevar` → CONTAINSROW). Direct Lake on
 *      SQL forces RLS through the DirectQuery DAX subset where CONTAINSROW
 *      is blocked. Switching the model to Direct Lake on OneLake gives full
 *      DAX, but OneLake mode does not permit views. Materializing this view
 *      to a Delta table fixes both at once.
 *
 * Run order (top to bottom):
 *   1. THIS script — drops the old view + dependent view + proc, creates
 *      the new StaffSchoolAccess table.
 *   2. sql/security/vw_SchoolStudents.sql — re-run to recreate the view
 *      pointing at StaffSchoolAccess instead of vw_StaffSchoolAccess.
 *   3. sql/procedures/usp_MergeStaff.sql — re-run to recreate the proc with
 *      the new Step 6 (StaffSchoolAccess rebuild).
 *   4. sql/scripts/reset_and_run_full_ingest.sql — populates StaffSchoolAccess
 *      via the new merge proc.
 *   5. Manual: delete and recreate the Power BI semantic model in Direct
 *      Lake on OneLake mode, including StaffSchoolAccess as a TABLE (not
 *      a view). See docs/semantic-model-setup.md.
 *
 * Idempotent: safe to re-run.
 ******************************************************************************/

-- 1. Drop the dependent view first (vw_SchoolStudents references vw_StaffSchoolAccess).
DROP VIEW IF EXISTS vw_SchoolStudents;

-- 2. Drop the now-deprecated unpacking view.
DROP VIEW IF EXISTS vw_StaffSchoolAccess;

-- 3. Drop the staff merge proc (will be recreated in step 3 of run order).
DROP PROCEDURE IF EXISTS usp_MergeStaff;

-- 4. Drop and recreate the materialized RLS-oracle table.
DROP TABLE IF EXISTS StaffSchoolAccess;

CREATE TABLE StaffSchoolAccess (
    StaffSchoolAccessID BIGINT       NOT NULL IDENTITY,
    StaffKey            BIGINT       NOT NULL,
    Email               VARCHAR(255) NOT NULL,
    SchoolID            VARCHAR(10)  NOT NULL,
    AccessLevel         VARCHAR(50)  NOT NULL,
    LastRebuilt         DATETIME2(0) NOT NULL
);
