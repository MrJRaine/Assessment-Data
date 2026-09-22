/*******************************************************************************
 * Script: run_math_task_ingest_live.sql   (LIVE)
 * Purpose: Ingest the math task bank into DimMathTask on LIVE via usp_LoadMathTasks.
 *
 * PREREQS (already true from the 0.5.0 live deploy):
 *   - usp_LoadMathTasks, Stg_MathTask, DimMathTask exist on live.
 *   - The task CSV(s) are uploaded to the LIVE lakehouse folder:
 *         Files/imports/mathtasks/
 *     CSV format (matches Stg_MathTask column order): comma-delimited, header row
 *     (skipped), double-quote qualifier. Columns, in order:
 *         GradeCode, AssessmentMonth, UnitName, UnitOrder, QuestionNumber,
 *         DisplayOrder, OutcomeCode, TaskDescriptionEN, TaskDescriptionFR,
 *         AnswerKey, ActiveFlag
 *
 * SAFE / INCREMENTAL: the loader retires-dropped only within the (GradeCode,
 * AssessmentMonth) pairs present in this batch, so loading one grade's sheet never
 * touches another grade. Re-run any time to refresh; it returns Inserted/Updated/Retired.
 *
 * The '*' wildcard loads EVERY file in Files/imports/mathtasks/. Narrow it to a
 * filename prefix (e.g. .../mathtasks/PrimaryMathTasks*) if you want one sheet.
 *
 * GUIDs: workspace a1b49041-... / LIVE lakehouse b3819971-... (same path the live
 * PS loaders use). Region: Canada East (PIIDPA compliant).
 ******************************************************************************/

EXEC usp_LoadMathTasks
    @SourceUri = 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/mathtasks/MathTasks_*';

-- The proc returns TasksInserted / TasksUpdated / TasksRetired. Quick sanity check after:
SELECT GradeCode, AssessmentMonth, COUNT(*) AS Tasks, SUM(CAST(ActiveFlag AS INT)) AS ActiveTasks
FROM DimMathTask
GROUP BY GradeCode, AssessmentMonth
ORDER BY GradeCode, AssessmentMonth;
