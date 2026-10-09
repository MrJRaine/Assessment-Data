---
name: project_math_task_month_miscoding
description: "Math team mis-codes SCoR task months in the source doc (Feb/May for SCoR-3/SCoR-5 instead of canonical Jan/Apr). FIX AT CONVERSION TIME — correct the months while converting the math-team file into the uploadable version, BEFORE ingest, so DimMathTask lands correct."
metadata:
  node_type: memory
  type: project
  originSessionId: 81b06086-0f59-47db-b6fb-84b7a577c17f
  modified: 2026-10-09T00:00:00.000Z
---

**Set 2026-10-07; approach changed 2026-10-09 (fix at conversion, not post-seed).** The canonical **SCoR
cycle months are 9, 11, 1, 3, 4, 6** (Sep, Nov, Jan, Mar, Apr, Jun) — and they apply to **both Reading
(benchmark month) AND Math (task-pull month)**; Writing has no month. `DimMathTask.AssessmentMonth` must
equal the cycle's SCoR month for `tvf_TeacherRosterMath` to show the tasks (it joins
`DimMathTask.AssessmentMonth = COALESCE(window.BenchmarkMonth, dominant month)`).

**The recurring defect:** the **math team codes the task source doc with the WRONG month** — SCoR-3 tasks as
**Feb (2)** instead of **Jan (1)**, and SCoR-5 tasks as **May (5)** instead of **Apr (4)**. They have been
told and **won't change**, so every pull from the share doc re-introduces it.

**The standing correction — apply at CONVERSION time, before upload (NOT a post-seed UPDATE):** whenever I
convert the math team's file into the uploadable `usp_LoadMathTasks` format, **remap the months as part of
that conversion** so the file is already correct before it is ingested — SCoR-3 `2 → 1` (Feb→Jan), SCoR-5
`5 → 4` (May→Apr), and **verify the whole month set is a subset of {9,11,1,3,4,6}** in case they mis-code a
different month. Doing it here means `DimMathTask` lands right on the first seed and there is no after-the-fact
`UPDATE DimMathTask` to remember. (If a seed ever gets loaded raw, the recovery is still the two UPDATEs
`SET AssessmentMonth = 1 WHERE AssessmentMonth = 2` / `= 4 WHERE = 5`, `ActiveFlag = 1` — safe because no
cycle uses months 2 or 5 and no month-1/4 tasks exist to collide — but the conversion-time fix is the
intended path.)

**Why it surfaced (both issues RESOLVED 2026-10-07):** (1) Math cycle instances saved with
`BenchmarkMonth = NULL` (the `/cycles` form exposed the month for Reading only), so the roster TVF fell back
to each window's DOMINANT calendar month — which for 3 of the 6 cycles (Oct=10, Jan via Nov-Feb, Apr=4)
landed on a month with no tasks → blank math grid; and (2) the months in the math-team doc were wrong. Fixed
by: (a) set `BenchmarkMonth` = {9,11,1,3,4,6} on the Reading+Math windows per cycle, (b) correct the task
months (now done at conversion, per above), (c) expose a "Task month" selector for Math on `/cycles`
(`subject === 'Reading'` gate → `!== 'Writing'`). See [[project_math_assessment_model]],
[[project_math_report_blank_roster_bug]].
