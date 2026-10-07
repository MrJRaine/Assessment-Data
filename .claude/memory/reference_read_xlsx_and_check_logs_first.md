---
name: reference_read_xlsx_and_check_logs_first
description: "When the user says 'we did this before / do you remember how', search the session archive + transcripts for the ACTUAL method before reconstructing or saying you can't. Includes: how to read a .xlsx without Excel (PowerShell OOXML unzip)."
metadata:
  node_type: memory
  type: reference
---

**Set 2026-10-04**, after I twice claimed "I can't read a binary .xlsx" — wrong; I'd done it twice
before (math-task bank 2026-09-02; prior-year baseline) and the user had to remind me.

## Behaviour: check the logs for HOW, don't reconstruct or disclaim
When the user references prior work ("you've done this before", "do you remember how", "like last time"),
**search `project_session_archive.md` (and the transcripts) for the actual method FIRST** — before saying
"I can't" or rebuilding from scratch. The archive is my memory of *how*; use it. This is the same failure
family as [[reference_gh_cli_token_via_git]] (don't declare something impossible without checking).

## How to read a .xlsx WITHOUT Excel / Python / ImportExcel
A `.xlsx` is OOXML = a ZIP of XML parts. Read it with a PowerShell unzip script (last used
`parse-xlsx.ps1` in the scratchpad → `xlsx-dump.txt`):
1. Expand the `.xlsx` as a zip (`Expand-Archive` after copying to `*.zip`, or `System.IO.Compression`).
2. Read `xl/worksheets/sheet*.xml` + `xl/sharedStrings.xml`.
3. Resolve shared-string indices and the `r=` cell refs (A1-style) back to rows/columns.
4. Dump **values AND `<f>` formulas** to a text file, then Read that.
Flow: user drops the workbook in a folder → point the script at it → read the dump → transcribe.

## Math-task update: transcribing the math team's workbook -> load-ready CSV (RECURRING)
The math team's workbook does NOT line up with our schema — it needs these tweaks EVERY time (done twice:
2026-09-02 initial, and a later more-recent reload):
1. **Month 10 -> 9 (grades 1/2/3 fall).** They author fall tasks as AssessmentMonth 10 (October) but the
   fall Short Cycle runs month 9 (September), so month-10 tasks resolve to NOTHING. Remap 10->9 **IN THE
   TRANSFORM/CSV**, not just SQL: `sql/scripts/fix_math_task_month_10_to_9.sql` fixes the dim, but the source
   still says 10, so the NEXT `usp_LoadMathTasks` REVERTS it. Grade P already uses 9.
2. **Column titles differ** — their headers don't match ours; map them onto our column order (re-derive per
   workbook — their titles drift between versions, so read the dump and map fresh).
   **Strip the trailing outcome-code parenthetical** from TaskDescriptionEN/FR (e.g. ` (N01.01)`): the code
   lives in its own OutcomeCode column and was never in the team's sheet (user-confirmed convention, both
   prior loads). **Preserve internal whitespace** (only neutralize newlines/tabs + trim) — collapsing
   double-spaces churns ~70 existing rows for nothing and muddies the differential.
3. **Target CSV = 12 columns** (`Stg_MathTask` order; comma, header row skipped, double-quote qualifier):
   `GradeCode, AssessmentMonth, UnitName, UnitOrder, QuestionNumber, DisplayOrder, OutcomeCode,
   TaskDescriptionEN, TaskDescriptionFR, AnswerKey, AnswerKeyFR, ActiveFlag`. (AnswerKeyFR was added by
   `migrate_MathTask_add_AnswerKeyFR_live.sql`; the `run_math_task_ingest_live.sql` header still lists the
   old 11 — stale.) The math team's workbook (`Math SCoR App Data Spreadsheet 2026-27.xlsx`, one sheet per
   grade Primary/One..Six) maps: Grade→GradeCode, Month→AssessmentMonth (10→9), **Unit#→UnitName as
   `Unit <#>`**, SCoROrder→UnitOrder, QuestionNumber→QuestionNumber, DisplayOrder→DisplayOrder,
   `PerformanceIndicator Number`→OutcomeCode, EN/FR task + AnswerKeyEN/FR direct; drop
   `PerformanceIndicatorDescription`. Read it with `parse-xlsx.ps1` (XmlDocument.Load for UTF-8 French).
   CONFIRM the UnitName/UnitOrder convention against current DimMathTask before loading (NK depends on it).

**Tracked tooling + reference (2026-10-04):** CSVs now live in `data/mathtasks/` (NOT git-ignored, unlike
`data/imports/*`): `MathTasks_2026-27.csv` (current authoritative bank, overwrite per update so `git diff` =
the differential) + `baseline-2026-09/` (prior per-grade load, as received). Reusable scripts in
`scripts/mathtasks/`: `transform-mathtasks.ps1` (xlsx -> load CSV, does all the tweaks), `diff-mathtasks.ps1`
(old-vs-new, normalizes old 10->9 first), `parse-xlsx.ps1` (dump xlsx to text). See `data/mathtasks/README.md`.

Load + differential: upload to `Files/imports/mathtasks/`, then
`EXEC usp_LoadMathTasks @SourceUri='…/mathtasks/MathTasks_*'` (`sql/scripts/run_math_task_ingest_live.sql` /
`_dev.sql`). The loader is **INCREMENTAL** — retires-dropped only within the `(GradeCode, AssessmentMonth)`
pairs present in the batch, and returns **Inserted / Updated / Retired** = the differential. Type-1 upsert on
NK `(GradeCode, AssessmentMonth, UnitName, QuestionNumber)`, so re-loading is idempotent.
**`COPY INTO` path = storage path, NOT a URL: spaces LITERAL, never `%20`** (silent 0-row load otherwise);
filename must match the `MathTasks_*` wildcard. See [[project_math_assessment_model]].
