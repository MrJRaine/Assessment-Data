# Math task bank — transcription & load reference

The math team authors the SCoR math task bank in an Excel workbook (one sheet per grade,
Primary–Six) and sends updates **incrementally** ("dribs and drabs"). This folder keeps the
load-ready CSVs **tracked** so every update has a baseline to diff against — unlike
`data/imports/` (the PII drop zone), which is git-ignored. Task content is curriculum, not PII,
so it is safe to commit.

## What's here

| Path | What it is |
|---|---|
| `MathTasks_2026-27.csv` | **Current authoritative bank** — load-ready, all grades combined. This is the file uploaded to OneLake and loaded by `usp_LoadMathTasks`. |
| `baseline-2026-09/` | The prior per-grade load (`MathTasks_P/1/2/3.csv`) **as received** (month 10, some codes un-stripped). Kept for provenance / the first differential. |

Going forward, each update **overwrites `MathTasks_2026-27.csv`** (or starts a new `MathTasks_<year>.csv`),
so `git diff` / `git log` on that file *is* the differential history.

## The workbook does NOT line up with our schema — tweaks applied every time

Target CSV = `Stg_MathTask` column order (12 cols, comma-delimited, `"`-quoted, header row that
the loader skips via `FIRSTROW=2`):

```
GradeCode, AssessmentMonth, UnitName, UnitOrder, QuestionNumber, DisplayOrder,
OutcomeCode, TaskDescriptionEN, TaskDescriptionFR, AnswerKey, AnswerKeyFR, ActiveFlag
```

Their sheet → our column, with the transforms (all handled by `scripts/mathtasks/transform-mathtasks.ps1`):

| Our column | From their sheet | Transform |
|---|---|---|
| GradeCode | `Grade` (P, 1…6) | — |
| AssessmentMonth | `Month` | **10 → 9** (fall Short Cycle is September; team authors October) |
| UnitName | `Unit#` | `"Unit " + Unit#` |
| UnitOrder | `Unit#` | integer |
| QuestionNumber | `QuestionNumber` | verbatim (`1`, `2a`, …) — part of the natural key, do not reformat |
| DisplayOrder | `DisplayOrder` | — |
| OutcomeCode | `PerformanceIndicator Number` | — |
| TaskDescriptionEN | `TaskDescriptionEN` | **strip trailing outcome-code parenthetical** e.g. ` (N01.01)` — the code lives in OutcomeCode and was never in the team's sheet |
| TaskDescriptionFR | `TaskDescriptionFR` | same strip |
| AnswerKey | `AnswerKeyEN` | — |
| AnswerKeyFR | `AnswerKeyFR` | — |
| ActiveFlag | `ActiveFlag` | default 1 |
| *(dropped)* | `PerformanceIndicatorDescription`, `SCoROrder` | no column for them |

Whitespace: only CSV-breaking chars (newline/tab) are neutralized and ends trimmed —
**internal spacing is preserved** so a reload doesn't churn existing rows over cosmetic
double-spaces.

## Updating when the team sends a new sheet

1. Drop the workbook in `data/imports/` (git-ignored).
2. Transcribe:
   ```powershell
   scripts\mathtasks\transform-mathtasks.ps1 -Path "data\imports\<workbook>.xlsx" -OutCsv "data\mathtasks\MathTasks_2026-27.csv"
   ```
   It reports per grade+month row counts and how many months were remapped 10→9.
3. Diff against the baseline to see the true differential (normalizes old 10→9 first):
   ```powershell
   scripts\mathtasks\diff-mathtasks.ps1 -Old baseline-2026-09\MathTasks_*.csv -New data\mathtasks\MathTasks_2026-27.csv
   ```
   Review ADDED / REMOVED / CHANGED. Whitespace- or code-suffix-only "changes" are noise;
   watch for real wording / answer-key / order edits.
4. Upload `MathTasks_2026-27.csv` to the lakehouse `Files/imports/mathtasks/` (dev first, then live).
5. Run `sql/scripts/run_math_task_ingest_dev.sql` / `run_math_task_ingest_live.sql`.
   The loader (`usp_LoadMathTasks`) is an idempotent SCD Type-1 upsert on the natural key
   **(GradeCode, AssessmentMonth, UnitName, QuestionNumber)**: NK present → update, new → insert,
   present-in-batch-grade/month-but-missing → retire. It returns Inserted / Updated / Retired.
   A non-zero **Retired** you didn't expect = a natural-key drifted — investigate before trusting it.

## 2026-10-04 load

`MathTasks_2026-27.csv` = 428 rows (P/1/2/3/4; grades 5–6 sheets were empty).
Differential vs `baseline-2026-09/`: **+58 new** (grade 3 November = 35, grade 4 September = 23),
0 removed, 0 genuine content edits, 27 description code-strip cleanups the prior load had missed.

`scripts/mathtasks/parse-xlsx.ps1` dumps any `.xlsx` to text (OOXML unzip; UTF-8 for French) when
you want to eyeball the raw workbook.
