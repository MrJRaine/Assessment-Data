---
name: Reading Scale Design Decisions
description: Schema + semantics for DimReadingScale and DimReadingBenchmark. Captures decisions made 2026-05-12 with assessment-team data.
type: project
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**English reading scale data + schema decisions, 2026-05-12.**

**Two-table model:**
- **`DimReadingScale`** — valid levels for a given system (DT + A-Z for English). Columns: ReadingScaleID, LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag, LastUpdated. The dropdown source in Power Apps.
- **`DimReadingBenchmark`** — expected ranges by (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth). Long-format. Source of `ReadingDelta` computation.

**`ScaleSystem` naming convention:** vendor-neutral. `'EN_Reading'` for the English scale (currently the only seeded system). `'FR_Reading'` (or similar) for the French Immersion French-literacy scale when that arrives. **Do not refer to the English scale as F&P in code, comments, or descriptions** — political constraint from the user (2026-05-12), even though the level codes happen to match F&P A-Z.

**LevelOrder convention:** `DT = 0`, `A-Z = 1-26`. Used for arithmetic delta computation. Each scale system can have its own ordering (the French scale will likely use different codes / ordering).

**ReadingDelta formula** (implement in `usp_UpsertReadingAssessment`):

Two parts: input validation (THROW on NULL), then the CASE itself.

```sql
-- Part 1: validate inputs. Any NULL means a lookup failed — either the
-- student's LevelCode didn't resolve to a LevelOrder, or DimReadingBenchmark
-- has no row for (ScaleSystem, ProgramFamily, GradeCode, DominantMonth).
-- Either way, the answer is "I don't know" — surface it loudly, don't
-- silently compute a wrong delta.
IF @StudentLevelOrder IS NULL
   OR @ExpectedMinOrder IS NULL
   OR @ExpectedMaxOrder IS NULL
BEGIN
    ;THROW 51001, 'usp_UpsertReadingAssessment: failed to resolve LevelOrder for student level, benchmark min, or benchmark max. Check DimReadingScale + DimReadingBenchmark lookups.', 1;
END;

-- Part 2: three exhaustive WHENs on validated non-NULL integers. No ELSE.
SET @ReadingDelta = CASE
    WHEN @StudentLevelOrder >= @ExpectedMinOrder
     AND @StudentLevelOrder <= @ExpectedMaxOrder      THEN 0
    WHEN @StudentLevelOrder <  @ExpectedMinOrder      THEN @StudentLevelOrder - @ExpectedMinOrder
    WHEN @StudentLevelOrder >  @ExpectedMaxOrder      THEN @StudentLevelOrder - @ExpectedMaxOrder
END;
```

`@StudentLevelOrder`, `@ExpectedMinOrder`, `@ExpectedMaxOrder` are all `LevelOrder` values from `DimReadingScale` joined on `LevelCode` within the same `ScaleSystem`. The pre-CASE `IF…THROW` is the explicit error path the user requested — replaces the previous `ELSE 0` fallback which silently produced a wrong "in-range" answer on NULL inputs.

**AssessmentMonth derivation — "dominant month" rule:**

The benchmark month for a window is computed from the window's `[StartDate, EndDate]` range — pick the calendar month with the most days within the range. Ties broken by earlier month.

Implementation using `DimCalendar`:

```sql
SELECT TOP 1 dc.Month
FROM DimCalendar dc
WHERE dc.Date BETWEEN @WindowStart AND @WindowEnd
GROUP BY dc.Month
ORDER BY COUNT(*) DESC, dc.Month;
```

The dominant month is a **property of the window**, not the individual assessment date. All assessments in a given window use the same benchmark, regardless of when each assessment was actually recorded by the teacher. (Important for the case where Teacher A enters all their students on the last day of the window but Teacher B spread them across the month — both should be evaluated against the same expectation.)

**DT is submittable.** Teachers can record a student at `'DT'` as their actual reading level (not just an expectation marker for Primary). The dropdown in `scrRosterGrid.cmbNewLevel` must include DT as a selectable option.

**Grade 7 carry-over.** Students who didn't reach grade-level by end of Grade 6 (the Z benchmark) continue to be assessed in Grade 7 against the Grade 6 end-of-year expectation (Z to Z) for all months. The Grade 7 rows in the seed mirror this. **Open question (asked 2026-05-12)**: does Grade 8+ extend the same carry-over pattern, or do students "graduate out" of the assessment program after Grade 7? Currently the seed has Grade 7 only.

**Coverage today (2026-05-12):**
- **English scale (`EN_Reading`)**: Grades P-7 seeded (P-6 per-month progressions; 7 is the Grade-6-June Z-Z fixed carry-over). 27 levels (DT + A-Z). ProgramFamily = 'English'.
- **French scale (`FR_Reading`)**: Grades P-7 seeded (P-6 per-month progressions; 7 is the Grade-6-June 30/30+ fixed carry-over). 32 levels (TD + 1-30 + 30+). ProgramFamily = 'French Immersion' only — French Second Language NOT covered.

**French scale specifics:**
- `'TD'` (Texte Dicté) is the FR equivalent of EN's `'DT'` — pre-emergent reader, LevelOrder = 0, submittable.
- Numeric levels `'1'`-`'30'` have LevelOrder = level number. Trivially ordered.
- `'30+'` (LevelOrder = 31) is **submittable** for strong readers past level 30. Also serves as `ExpectedMaxLevel` in benchmarks for Grade 6 Nov-Jun, meaning "no upper bound — student at any level >= 30 is in range."
- Decision recorded 2026-05-12: 30+ chosen as a real submittable level (vs expectation-only marker) for symmetry — makes ReadingDelta computation uniform (a student at 30+ in a max-30+ window correctly produces delta=0).

**Edge case — student grade not in benchmark table** (e.g., a Grade 8 student gets assessed somehow): `usp_UpsertReadingAssessment` should set `ReadingDelta = NULL` and audit a warning. Don't fall back silently — surface the gap so admin can decide.

**Power Apps integration notes:**
- `cmbNewLevel.Items` filters `DimReadingScale` by the student's window's `ScaleSystem` (for English window → `ScaleSystem = 'EN_Reading'`)
- The screen design's `Items` expression in `powerapps-screen-design.md` should be updated from `Filter(DimReadingScale, ProgramCode = ThisItem.ProgramCode && Grade = ThisItem.Grade)` to `Filter(DimReadingScale, ScaleSystem = gblSelectedWindow.ScaleSystem && ActiveFlag = TRUE)`. (Window-driven, not student-driven.)
- The window needs to know its ScaleSystem — likely add a `ScaleSystem` column to `DimAssessmentWindow` so the window declares which scale applies. Each window seeded with `'EN_Reading'` or `'FR_Reading'`.

**Reciprocal schema change implied:**
- `DimAssessmentWindow` should gain a `ScaleSystem VARCHAR(20) NOT NULL` column — adds to the migration already planned (drop AppliesTo, drop IsCurrentWindow, rename ProgramCode → ProgramFamily). Default value for the MVP pilot window: `'EN_Reading'`.

**Future expansion** (Phase 5+):
- French scale seeding (`'FR_Reading'`)
- Grade 8-12 carry-over rows if needed
- Multi-system windows? (probably not — each window picks one ScaleSystem)
