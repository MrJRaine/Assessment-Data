/*******************************************************************************
 * Diagnostic: do the three save procedures carry the 2026-10-30 section-school binding?
 * Purpose: Confirm whether usp_UpsertReadingAssessment / usp_UpsertWritingAssessment /
 *          usp_UpsertMathAssessment on this warehouse are the pre- or post-2026-10-30
 *          versions. The 2026-10-30 change introduced a variable named @SectionSchoolID;
 *          it appears nowhere in the earlier versions.
 * SCD Type: n/a (read-only diagnostic)
 * Created: 2026-11-18
 * Run on: Assessment_Warehouse (live). Safe on dev too.
 * READS:  sys.objects, sys.sql_modules (procedure metadata + source text only).
 *         No table data, no student rows.
 * WRITES: nothing.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SELECT
    o.name,
    o.create_date,
    o.modify_date,
    CASE WHEN m.definition LIKE '%@SectionSchoolID%' THEN 'YES' ELSE 'NO' END AS HasSectionSchoolBinding
FROM sys.objects o
INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name IN ('usp_UpsertReadingAssessment', 'usp_UpsertWritingAssessment', 'usp_UpsertMathAssessment')
ORDER BY o.name;
