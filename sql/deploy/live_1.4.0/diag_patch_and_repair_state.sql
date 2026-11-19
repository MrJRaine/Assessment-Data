/*******************************************************************************
 * Diagnostic: is the section-school binding patch on this warehouse, and how many
 * rows did repair step 1 capture? ONE result grid, four rows.
 * Purpose: Confirm the state after running
 *          patch_upsert_section_school_binding_2026-11-18.sql and
 *          repair_rebind_1_capture_and_precheck.sql when their own output came back
 *          empty.
 * SCD Type: n/a (read-only)
 * Created: 2026-11-19
 * Run on: Assessment_Warehouse_Dev or Assessment_Warehouse (LIVE) - safe on both.
 * READS:  sys.objects, sys.sql_modules (procedure metadata only);
 *         dbo.RepairLog_FactStudentKeyRebind_20261118 (row count only).
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant) - no student data returned.
 *
 * Read the result:
 *   Three procedure rows, Detail = 'YES', ModifiedUTC = when the patch ran
 *       -> the patch is in place.
 *   A procedure row with Detail = 'NO'  -> that procedure is still the old version.
 *   Fewer than three procedure rows     -> a procedure is MISSING (saving for that
 *                                          subject is broken; rerun the patch).
 *   RepairLog row, Detail = '0'         -> step 1 ran and found nothing to re-bind
 *                                          (expected on dev).
 *   Error "Invalid object name ... RepairLog..." -> step 1 never created the table.
 ******************************************************************************/

SELECT o.name AS CheckedItem,
       CASE WHEN m.definition LIKE '%@SectionSchoolID%' THEN 'YES' ELSE 'NO' END AS Detail,
       o.modify_date AS ModifiedUTC
FROM sys.objects o
INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name IN ('usp_UpsertReadingAssessment', 'usp_UpsertWritingAssessment', 'usp_UpsertMathAssessment')
UNION ALL
SELECT 'RepairLog rows captured',
       CAST(COUNT(*) AS VARCHAR(20)),
       CAST(MAX(l.CapturedAt) AS DATETIME)
FROM dbo.RepairLog_FactStudentKeyRebind_20261118 l
ORDER BY CheckedItem;
GO
