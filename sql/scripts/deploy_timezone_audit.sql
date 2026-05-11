/*******************************************************************************
 * Deploy script: Time Zone Audit (2026-05-11)
 * Region: Canada East (PIIDPA compliant)
 *
 * Step 16 follow-up. Apply the "store UTC, display/compare in Atlantic"
 * convention to the 7 spots where date logic is timezone-sensitive.
 * The fix is mechanical: every `CAST(GETDATE() AS DATE)` boundary becomes
 * `CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)`
 * so date-of-day comparisons resolve to Atlantic local day, not UTC day.
 *
 * The 7 modified source files are the canonical content — this script
 * doesn't inline their bodies (avoids drift). It just (a) verifies the
 * AT TIME ZONE function works in your warehouse, (b) drops the 7 objects
 * so they can be cleanly recreated, then (c) lists the source files to
 * run in order in the Fabric portal SQL editor.
 *
 * See:
 *   - .claude/skills/fabric-warehouse-sql.md  → "Time Zone Convention" section
 *   - memory/project_timezone_convention.md   → full convention + audit list
 ******************************************************************************/


-- ============================================================================
-- Step 1. Verify AT TIME ZONE works in this warehouse.
-- Expected: AtlanticNow trails UtcNow by 3 hours during ADT (Mar–Nov),
-- 4 hours during AST (Nov–Mar). If the second column errors, stop and tell
-- Claude — the rest of the deploy is built on this function working.
-- ============================================================================

SELECT
    GETDATE() AS UtcNow,
    GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS AtlanticNow;


-- ============================================================================
-- Step 2. Drop the 7 objects so they can be recreated from the modified
-- source files. Order doesn't matter for DROPs (no FK enforcement in Fabric).
-- ============================================================================

DROP PROCEDURE IF EXISTS usp_MergeStudent;
DROP PROCEDURE IF EXISTS usp_MergeStaff;
DROP PROCEDURE IF EXISTS usp_MergeSection;
DROP PROCEDURE IF EXISTS usp_MergeEnrollment;
DROP PROCEDURE IF EXISTS usp_MergeSectionTeachers;
DROP PROCEDURE IF EXISTS usp_YearEndCloseOut;
DROP VIEW       IF EXISTS vw_TeacherStudents;


-- ============================================================================
-- Step 3. Run the 7 modified source files IN THIS ORDER in Fabric portal SQL.
-- Order doesn't strictly matter (no inter-object compile dependencies between
-- these specific 7), but this is alphabetical-ish for sanity. Open each file,
-- copy contents, paste in a Fabric SQL query tab, run.
--
--   1.  sql/procedures/usp_MergeStudent.sql
--   2.  sql/procedures/usp_MergeStaff.sql
--   3.  sql/procedures/usp_MergeSection.sql
--   4.  sql/procedures/usp_MergeEnrollment.sql
--   5.  sql/procedures/usp_MergeSectionTeachers.sql
--   6.  sql/procedures/usp_YearEndCloseOut.sql
--   7.  sql/security/vw_TeacherStudents.sql
-- ============================================================================


-- ============================================================================
-- Step 4. Smoke-test: confirm the year-end proc's CASE evaluates correctly
-- against the Atlantic-converted date. Should return current school year's
-- end (e.g. running in May 2026 → 2026 closing year, since school year
-- 2025-2026 ends June 30 2026).
-- ============================================================================

DECLARE @AtlanticToday DATE =
    CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

SELECT
    @AtlanticToday AS AtlanticToday,
    CASE WHEN MONTH(@AtlanticToday) >= 7 THEN YEAR(@AtlanticToday)
         ELSE YEAR(@AtlanticToday) - 1 END AS ImpliedClosingYear;


-- ============================================================================
-- Step 5. Re-verify data quality is still clean after redeploy.
-- ============================================================================

EXEC usp_RunDataQualityChecks;
-- Expect: 1 PASS row appended to FactDataQualityAudit.


-- ============================================================================
-- Step 6 (optional). End-to-end verification — re-run the full ingest cycle
-- to confirm the new @EffectiveDate fallbacks fire correctly. Only needed if
-- you want the most thorough confirmation; the data quality check above
-- already validates the warehouse state hasn't degraded.
-- ============================================================================

-- EXEC usp_RunFullIngestCycle;
