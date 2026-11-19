/*******************************************************************************
 * Diagnostic: is the section-school binding patch on this warehouse, and how many
 * rows did repair step 1 capture? TWO result grids.
 * Purpose: Confirm the state after running
 *          patch_upsert_section_school_binding_2026-11-18.sql and
 *          repair_rebind_1_capture_and_precheck.sql when their own output came back
 *          empty.
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse_Dev or Assessment_Warehouse (LIVE) - safe on both.
 * READS:  sys.objects, sys.sql_modules (procedure metadata only);
 *         dbo.RepairLog_FactStudentKeyRebind_20261118 (counts only).
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - no student data returned.
 * NOTE:   two statements on purpose - Fabric cannot mix catalog views and a user
 *         table in one statement (Msg 15816).
 *
 * Read the result:
 *   GRID 1 - three procedure rows, HasSectionSchoolBinding = 'YES', ModifiedUTC =
 *            when the patch ran -> the patch is in place. A 'NO' = old version.
 *            Fewer than three rows = a procedure is MISSING (rerun the patch).
 *   GRID 2 - one row per capture run (CapturedAt). No rows = step 1 captured
 *            nothing here. More than one CapturedAt, or FactRows > DistinctFacts,
 *            = step 1 was run more than once and appended.
 *            Error "Invalid object name ... RepairLog..." = step 1 never ran here.
 ******************************************************************************/

SELECT o.name AS ProcedureName,
       CASE WHEN m.definition LIKE '%@SectionSchoolID%' THEN 'YES' ELSE 'NO' END AS HasSectionSchoolBinding,
       o.modify_date AS ModifiedUTC
FROM sys.objects o
INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name IN ('usp_UpsertReadingAssessment', 'usp_UpsertWritingAssessment', 'usp_UpsertMathAssessment')
ORDER BY o.name;
GO

SELECT l.CapturedAt, l.Subject, l.RepairGroup, l.WouldCollide,
       COUNT(*)                 AS FactRows,
       COUNT(DISTINCT l.FactID) AS DistinctFacts
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
GROUP BY l.CapturedAt, l.Subject, l.RepairGroup, l.WouldCollide
ORDER BY l.CapturedAt, l.Subject, l.RepairGroup, l.WouldCollide;
GO
