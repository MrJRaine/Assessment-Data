---
name: Assessment Types and Window-Type Modeling
description: Three valid assessment types (Reading, Writing, Math), each modeled as its own single-type window. Concurrent multi-type efforts use multiple overlapping windows, not bundled multi-type rows. Decided 2026-05-13.
type: project
originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---
**Three valid `AssessmentType` values: `'Reading'`, `'Writing'`, `'Math'`.** One assessment type per `DimAssessmentWindow` row — concurrent multi-type efforts are modeled as **multiple separate windows with overlapping dates**, not one bundled window.

**Why:**

User confirmed 2026-05-13 (Step 18 prereq #2 design pass) that:
- Math is a valid assessment type for this platform (not previously documented — earlier scope was just Reading + Writing).
- A `DimAssessmentWindow` row represents one assessment-type/scope/date envelope; bundling multiple types into one window row was considered (bridge table `DimAssessmentWindowType`) and rejected.

Rejected the multi-type-per-window design because:
1. `FactAssessmentReading` and `FactAssessmentWriting` are already physically separate fact tables, so the DB doesn't push toward bundling.
2. Reading and Writing use entirely different scoring instruments (reading-level vs. 4-axis rubric); Math will be a third. Bundling at the window grain doesn't reduce taps in Power Apps; it adds a sub-selection step.
3. A "Fall 2025 Report Card season" bundling need is solved at the naming/UX layer (visually group windows that share `SchoolYear` + date overlap) — no schema support needed.
4. Each fact row points at one `AssessmentWindowID` — multi-type windows would force a bridge join to answer "what type was this assessment under?", losing simple `WHERE w.AssessmentType = 'Reading'` filters.

**How to apply:**

**Schema implications (locked in by [sql/dimensions/DimAssessmentWindow.sql](../../../../Git-Repos/Assessment-Data/sql/dimensions/DimAssessmentWindow.sql) v2):**
- `AssessmentType VARCHAR(20) NOT NULL` — single-valued, allow-list of `'Reading' | 'Writing' | 'Math'`.
- `ScaleSystem VARCHAR(20) NULL` — **reading-specific**. Populated for Reading windows (`'EN_Reading'` or `'FR_Reading'`); NULL for Writing and Math windows.
- When proc/view code needs to know the scoring approach, dispatch on `AssessmentType`, not `ScaleSystem`.

**Power Apps implications:**
- `scrWindowSelect` lists all applicable windows; teacher picks one. Concurrent Reading + Writing = teacher sees two list items with overlapping dates and chooses which to enter.
- Each window's entry screen branches on `AssessmentType` to pick the right input UI (level dropdown for Reading; rubric grid for Writing; TBD for Math).
- `cmbNewLevel` dropdown filter (`Filter(DimReadingScale, ScaleSystem = gblSelectedWindow.ScaleSystem)`) only applies to Reading windows; Writing/Math have their own input controls.

**Scoring approach per type:**

| Type | Where scoring is recorded | Reference dimension |
|---|---|---|
| `Reading` | `FactAssessmentReading.ReadingScaleID` + `ReadingDelta` | `DimReadingScale` + `DimReadingBenchmark` |
| `Writing` | `FactAssessmentWriting.IdeasScore` / `OrganizationScore` / `LanguageScore` / `ConventionsScore` (1-4 each) | None — scores stored directly |
| `Math` | **TBD** — not yet designed | **TBD** — not yet seeded |

**Math is post-MVP.** Phase 5+ work. When Math arrives, design decisions needed:
- Scoring instrument (rubric? numeric score? level-based scale?).
- New fact table `FactAssessmentMath` or extend an existing one.
- Whether Math gets a `ScaleSystem` value (`'EN_Math'` / `'FR_Math'`) — likely yes if it's level-based, no if it's numeric/rubric.
- Power Apps entry UI for Math.

**Validation rules (for write procs and Layer 1 client gating):**
- `usp_UpsertReadingAssessment` requires `DimAssessmentWindow.AssessmentType = 'Reading'` for the target window — Layer 2 check, THROW 51030+ range.
- Same pattern applies to future `usp_UpsertWritingAssessment` / `usp_UpsertMathAssessment` procs.
- A teacher cannot enter a reading-level value against a Writing window even if the proc is invoked directly — the proc cross-checks the window's `AssessmentType`.

**Don't litigate this again:** the single-type-per-window decision is settled (2026-05-13). If a future stakeholder pushes for bundled windows, the answer is "name-bundle them at the UX layer, not the schema layer." Multi-type at the schema would force schema changes to every view, proc, and fact reference for marginal UX benefit.
