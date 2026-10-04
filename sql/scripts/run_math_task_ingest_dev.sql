/*******************************************************************************
 * Script: run_math_task_ingest_dev.sql   (DEV)
 * Purpose: Load the math task bank into DimMathTask on DEV via usp_LoadMathTasks —
 *          same as the live run, but pointed at the DEV lakehouse.
 *
 * PREREQS:
 *   1. Run migrate_MathTask_add_AnswerKeyFR_live.sql on DEV first (it's schema-only /
 *      env-agnostic — adds AnswerKeyFR + widens AnswerKey). Its pre-check "must be 0"
 *      is a LIVE safety: on DEV, if DimMathTask already holds old synthetic tasks that
 *      is FINE — recreating + reloading is expected (dev is disposable). Proceed.
 *   2. Deploy the updated usp_LoadMathTasks.sql on DEV.
 *   3. Upload data/imports/MathTasks_2026-27.csv to the DEV lakehouse Files/imports/mathtasks/.
 *
 * 2026-10-04 load: MathTasks_2026-27.csv (428 rows, P/1/2/3/4; grades 5-6 sheets empty).
 * Source month 10 remapped -> 9 (fall = September) in the CSV. SourceUri points at the EXACT
 * file so a stale file in the folder can't be swept in by a wildcard.
 *
 * GUIDs: workspace a1b49041-... / DEV lakehouse 8c5589bd-... (same dev lakehouse the
 * dev cutover loaders use). Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

EXEC usp_LoadMathTasks
    @SourceUri = 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/8c5589bd-d04e-4e94-bb2c-482db645afab/Files/imports/mathtasks/MathTasks_2026-27.csv';

-- Sanity check after (returns per grade/month like the live run):
SELECT GradeCode, AssessmentMonth, COUNT(*) AS Tasks, SUM(CAST(ActiveFlag AS INT)) AS ActiveTasks
FROM DimMathTask
GROUP BY GradeCode, AssessmentMonth
ORDER BY GradeCode, AssessmentMonth;
