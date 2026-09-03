---
name: project_math_assessment_model
description: P-6 Math assessment model (task-based binary mastery) + its warehouse schema and CSV-mirror seed loader. Math was pulled into the 1.0 rollout 2026-09-02; supersedes the old "Math post-MVP, scoring TBD".
metadata:
  type: project
---

**Math pulled into the 1.0 rollout (2026-09-02)** on a condensed timeline — no
longer post-MVP. Scope: **Primary–Grade 6**. Supersedes [[project_assessment_types]]'s
"Math scoring TBD".

**Scoring model — task-based binary mastery.** Each grade has a bank of
outcome-based **tasks**; a student is scored **1 = can do / 0 = cannot** per task.
Two derived layers (from the curriculum exemplar's Term-1 format — the authoritative
one; the sheet's Term 2/3 were half-revised, ignore them):
- **By task:** proportion correct (`SUM/#students`) → colour heatmap `>80 / 65-80 / 50-64 / <50` (class-weakness spotlight).
- **By student, per unit:** average of their 0/1 over the unit → **4-tier Achievement Level** (UI label; table stays `DimMathComprehensionBand`): Emerging `<0.50` · Developing `0.50–<0.75` · Meeting `0.75–<0.90` · In-depth `≥0.90`; **"Incomplete"** when `<80%` of the unit's tasks are scored. IPP handling per unit: **all-IPP** → plain IPP flag; **no IPP** → normal level; **mix of IPP-omitted + assessed** → the calculated level gets a **purple ring** (the IPP colour) to flag it as partly assessed.

**Cadence:** Math rides the SAME region-wide **Short Cycles** as Reading/Writing —
NO separate term cadence (the exemplar's Term 1/2/3 split was just spreadsheet
formatting). A task maps to a cycle by **month** (`DimMathTask.AssessmentMonth`),
matched against the cycle's benchmark/dominant month — the reading-targets pattern.

**Program:** one task set for all programs; EN vs FI is **display-only** — `DimMathTask`
has `TaskDescriptionEN` + `TaskDescriptionFR` on one key, so school/regional rollups
stay unified. (Not split scales.)

**Schema (built on branch `feat/math-p6-entry`, DEV only):**
- `DimMathTask` — bilingual task bank. Natural key `(GradeCode, AssessmentMonth, UnitName, QuestionNumber)` (UnitName is in the key — `2a` recurs across units). `QuestionNumber` ('2a'/'2b') is separate from `DisplayOrder` (multi-part sort). `OutcomeCode` (e.g. `N02.01`) split out of the description. `AnswerKey` kept as a teacher marking reference. Type-1 (ActiveFlag soft-retire).
- `FactAssessmentMath` — **KEEPS CHANGE HISTORY like Reading/Writing (decided 2026-09-03)**: grain `(StudentKey, AssessmentWindowID, MathTaskKey, AssessmentDate) → Result BIT`; the write inserts a new dated row (date capped at MIN(today, window EndDate)), same-date re-entry updates that day's row, and every read picks the **latest-by-date** per (student, window, task). Columns were already present, so the deployed dev table needs no rebuild.
- `DimMathComprehensionBand` — the 4 tiers, code→(label, colour); thresholds live in the read view (mirrors Writing's avg→`DimAchievementLevel`-by-code pattern).

**Seed pipeline (proven on dev):** grade-level CSVs authored to **mirror `DimMathTask`'s
columns** → `Stg_MathTask` ← `COPY INTO` ← OneLake `Files/imports/mathtasks/` →
`usp_LoadMathTasks @SourceUri` (parameterized path via `sp_executesql` — env-agnostic;
dev lakehouse GUID `8c5589bd-d04e-4e94-bb2c-482db645afab`). Type-1 upsert; the retire
step is **scoped to the (Grade, Month) pairs in the batch**, so a single-grade load
never touches other grades. Loaded Primary Term-1 on dev: **35 tasks** (Unit 1 = 13,
Unit 3 = 22). Only the Primary sheet is complete; more grades finishing by the hour.
Seed-template lives at `C:\Git-Repos\DimMathTask-seed-template.csv` (not in repo).

**Still to build (next session):** the read/write path — `usp_UpsertMathAssessment`
(validate `AssessmentType='Math'`, student-in-roster, task matches grade+month, write
0/1), `tvf_TeacherRosterMath` (the student×task **matrix** entry grid grouped by unit),
the by-task / by-student-per-unit summary reads, DQ checks, and the **web matrix entry
UI for teachers**. Also open: **IPP handling now that Math is a distinct type** — a
student may carry a Math IPP and/or a Literacy IPP; `FactStudentIPP` is already
per-`Subject` and [[project_ipp_type_labelling]] already labels "Math IPP", so this is
mainly clarifying the confirm-gate UX across both. Plus: FR descriptions, full P-6 seed,
and one remaining confirmation — show AnswerKey on the entry grid. (History grain
decided 2026-09-03: keep it, like reading/writing.)
