/*******************************************************************************
 * Script: migrate_DimStudent_strip_current_prefix.sql
 * Purpose: Rename four DimStudent columns to drop the misleading "Current"
 *          prefix:
 *              CurrentGrade    -> Grade
 *              CurrentSchoolID -> SchoolID
 *              CurrentIPP      -> IPP
 *              CurrentAdap     -> Adap
 *          The prefix was inaccurate on a Type 2 dim — every row is a
 *          point-in-time snapshot, so the row's effective dates define
 *          currency, not the column name. New names align with DimStaff
 *          and DimSection conventions (no "Current" prefix anywhere).
 *
 *          PS source column names (Stg_Student.CurrentIPP, .CurrentAdap)
 *          are unchanged — they mirror the actual PowerSchool export
 *          column headers and must continue to.
 *
 * Created: 2026-05-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Approach: drop and recreate (rather than ALTER TABLE RENAME COLUMN, which
 * has uncertain support in Fabric Warehouse). Cheap because the warehouse
 * data is fully derivable from the Lakehouse source files via the
 * orchestrator.
 *
 * Run order (top to bottom):
 *   1. THIS script — drops dependent views, the table, the work-table, and
 *      the merge proc.
 *   2. sql/dimensions/DimStudent.sql — recreates DimStudent with new column names.
 *   3. sql/staging/Wrk_Student.sql — recreates Wrk_Student with new column names.
 *   4. sql/procedures/usp_MergeStudent.sql — recreates the proc using the new names.
 *   5. sql/security/vw_TeacherStudents.sql — recreates the view.
 *   6. sql/security/vw_SchoolStudents.sql — recreates the view.
 *   7. sql/security/vw_RegionalData.sql — recreates the view.
 *   8. sql/scripts/reset_and_run_full_ingest.sql — repopulates from Lakehouse.
 *
 *   After all eight steps, verify with:
 *     SELECT TOP 3 StudentNumber, Grade, SchoolID, IPP, Adap FROM DimStudent;
 *     SELECT COUNT(*) AS TotalRows, SUM(CAST(IsCurrent AS INT)) AS CurrentRows FROM DimStudent;
 *
 * Idempotent: safe to re-run.
 ******************************************************************************/

-- 1. Drop the three security views (they SELECT the renamed columns).
DROP VIEW IF EXISTS vw_TeacherStudents;
DROP VIEW IF EXISTS vw_SchoolStudents;
DROP VIEW IF EXISTS vw_RegionalData;

-- 2. Drop the merge proc (will be recreated with new column references).
DROP PROCEDURE IF EXISTS usp_MergeStudent;

-- 3. Drop the work table (column shape is changing).
DROP TABLE IF EXISTS Wrk_Student;

-- 4. Drop the dimension table itself. Data is recoverable by re-running the
--    orchestrator against the existing Lakehouse files (re-resolves all
--    surrogate keys cleanly via usp_RunFullIngestCycle).
DROP TABLE IF EXISTS DimStudent;
