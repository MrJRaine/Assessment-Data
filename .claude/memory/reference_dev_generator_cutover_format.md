---
name: reference_dev_generator_cutover_format
description: "The dev ingest test generator MUST be run with -Format Cutover; its default (Legacy) produces filenames/format the current loaders don't match → silent 0-row COPY INTO."
metadata:
  node_type: memory
  type: reference
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-10-26T16:43:50.381Z
---

**Run the dev test-data generator as `_generate_ingest_testset.ps1 -Format Cutover`, not the default.**

The staging loaders (`usp_LoadStudentsStaging` etc.) glob OneLake for the **Cutover / live-PS**
filenames, `FILE_TYPE='CSV'`, comma-delimited, default CRLF `ROWTERMINATOR`:
`Files/imports/students/Students*`, `.../staff/Staff*`, `.../sections/Sections*`,
`.../enrollments/Enrollments*`, `.../section-teachers/Co-Teachers*`.

The generator **defaults to `-Format Legacy`** (self-labeled "dev TAB/.text"), which emits
`AssessmentDataStudentsExport.text` etc. — TAB-delimited, CR-only (0x0D), `.text`. `AssessmentData…`
does NOT start with `Students`/`Enrollments`/… so the glob matches **nothing** → `COPY INTO` loads
**0 rows silently** (no error; the cycle "completes" and `usp_RunDataQualityChecks` even PASSES, because
an empty warehouse has zero violations — see [[feedback_troubleshooting_method]]). `-Format Cutover`
emits `StudentsExport.csv` / `StaffExport.csv` / `SectionsExport.csv` / `EnrollmentsExport.csv` /
`Co-TeachersExport.csv` (comma, CRLF) which the globs DO match.

Why the Legacy default exists: it simulates the RAW PS sqlReport export *before* the prod Power Automate
rename/normalize flow (`AssessmentData*.text` → live `*.csv`). Dev has no such flow, so for direct dev
ingest you must generate the FINAL Cutover names yourself.

**THE TRAP (bit us 2026-10-26):** the generator's clean step DELETES every `.text`/`.csv` in each topic
folder before writing. So regenerating in the DEFAULT (Legacy) to apply an UNRELATED fix (e.g. unique
surnames, current-year dates) silently **wipes the working Cutover `.csv` and replaces it with Legacy
`.text`** — reverting a good dev load to the 0-row failure. ANY regen for ANY reason must pass
`-Format Cutover`, or it un-does the format. (Flipping the default to Cutover was considered — not done
unilaterally; the Legacy default is intentional for the raw-PS simulation. Just always pass the flag.)

**Symptom signature of this bug:** config dims intact (cycles/windows/benchmarks/tasks all present) but
`Stg_*` = 0 AND `DimStudent` total = 0 after a reset+ingest, while the file is clearly present in OneLake
with valid content. First check on an empty dev load: `SELECT COUNT(*) FROM Stg_Student` and the loader
glob vs the actual filename — do NOT assume the upload was skipped. Diag scripts:
`sql/scripts/diag_ingest_landing_dev.sql` (staging/dim landing), `diag_demo_seed_scope_dev.sql`.
Related: [[project_dev_live_environment_split]], [[project_dev_enrollment_year_rollover]].
