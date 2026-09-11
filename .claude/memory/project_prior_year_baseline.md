---
name: project_prior_year_baseline
description: "Prior-year (2025-2026) June reading/writing baseline so teachers see where new students started. Table + load DONE on live; the DISPLAY (v0.4.0 minor, main-based) is NOT built yet. Includes the year-flip abstraction + cumulative-Δ spec."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-10T17:32:03.359Z
---

**Goal:** teachers see each student's **starting point** (prior-year reading level + writing) on
their roster, plus how far they've progressed/regressed **cumulatively vs that anchor** each cycle.

**Data — DONE on LIVE (2026-09-09):** `PriorYearBaseline` (denormalized "option B"; full
star-schema historical integration = "option A" deferred). Loaded by
`sql/scripts/load_prior_year_baseline.sql` from four ELA/FLA Reading/Writing sheets
(`Assessment_Landing/Files/imports/prior-year-baseline/`, literal spaces in the abfss path — NOT
`%20`). Grain = **(StudentNumber, AssessmentLanguage)**; `AssessmentLanguage` = the LANGUAGE of the
assessment (ELA→`English`, FLA→`French`), NOT the program — so an immersion student assessed in both
languages, or a mid-year immersion→English transfer, correctly gets TWO rows (one per language).
Cross-school transfers legitimately produce same-language dupes (sheets are aggregated per school).
Writing = 4 traits; scores VARCHAR to hold codes. Loaded: 6221 rows / 5797 students / 5385 match a
current student. Reading covers ~half of writing (fewer reading rows) — confirm that's expected.

**THE YEAR-FLIP ABSTRACTION (design locked, must build this way):** the display must NOT hardcode a
`PriorYearBaseline` join. Build a **"starting point" read** =
`COALESCE(latest prior-school-year FactAssessment*, PriorYearBaseline seed)`:
- This year (2026-2027) the prior year (2025-2026) has NO in-system facts → resolves to
  `PriorYearBaseline`.
- Sept 2027 on: the prior year IS in `FactAssessmentReading/Writing` → resolves to the latest
  prior-year entry automatically, **zero code change at the flip**. `PriorYearBaseline` is just the
  seed for the pre-system year.
- `DimAssessmentWindow.SchoolYear` gives the year (prior = Y−1); match the student's current-program
  language to the baseline's `AssessmentLanguage`.

**Cumulative Δ spec:** `current − startingPoint`, always vs the fixed prior-year anchor (not the
previous cycle). Reading Δ = `DimReadingScale.LevelOrder` difference (DT=0, A=1…Z=26; FR similar) —
a level count (e.g. `M→P = +3`). Writing Δ = change in the 4-trait **average**. Score codes
(`SCR`/`ABS`/`INS`/`EAL`) become **NULL** in any average (excluded from numerator AND denominator,
never 0) — see [[project_writing_scribed_score_code]]. All-codes → NULL average → no starting point.

**READING display SHIPPED to LIVE 2026-09-10 (v0.4.0):** built from `feature/prior-year-baseline`
(off `main`). Reading roster row now shows Prev June / Since June / Expected / Current / Diff from
Prev Cycle / New level; 7-8 auto-hide of already-Meeting students (+ accordion note); optimistic
instant save (revalidatePath/router.refresh removed). Year-flip view `dbo.vw_StudentReadingStartingPoint`
= COALESCE(prior-year FactAssessmentReading, PriorYearBaseline seed). Cutover clean.
**WRITING intentionally has NO prior-June baseline** — last year's writing was too sporadic to anchor.
Still DEFERRED: student-detail per-cycle Δ (fast follow), option-A full historical star-schema.
See [[project_assessment_platform]], [[project_ongoing_assessment_model]] (latest-in-window picks).
