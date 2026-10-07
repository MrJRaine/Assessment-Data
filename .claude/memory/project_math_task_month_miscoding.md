---
name: project_math_task_month_miscoding
description: "Math team mis-codes SCoR task months in DimMathTask (uses Feb/May for SCoR-3/SCoR-5 instead of the canonical Jan/Apr). RECURRING — re-apply the 2→1, 5→4 AssessmentMonth correction after EVERY math-task seed."
metadata:
  node_type: memory
  type: project
  originSessionId: 81b06086-0f59-47db-b6fb-84b7a577c17f
  modified: 2026-10-07T16:35:24.304Z
---

**Set 2026-10-07.** The canonical **SCoR cycle months are 9, 11, 1, 3, 4, 6** (Sep, Nov, Jan, Mar, Apr, Jun)
— and they apply to **both Reading (benchmark month) AND Math (task-pull month)**; Writing has no month.
`DimMathTask.AssessmentMonth` must equal the cycle's SCoR month for `tvf_TeacherRosterMath` to show the
tasks (it joins `DimMathTask.AssessmentMonth = COALESCE(window.BenchmarkMonth, dominant month)`).

**The recurring defect:** the **math team codes the task CSVs with the WRONG month** — SCoR-3 tasks as
**Feb (2)** instead of **Jan (1)**, and SCoR-5 tasks as **May (5)** instead of **Apr (4)**. They have been
told and **won't change**, so **every re-seed via `usp_LoadMathTasks` / the share doc re-introduces it.**

**The standing correction — re-apply after EVERY math-task seed:**
```sql
UPDATE DimMathTask SET AssessmentMonth = 1 WHERE AssessmentMonth = 2 AND ActiveFlag = 1;  -- SCoR-3: Feb->Jan
UPDATE DimMathTask SET AssessmentMonth = 4 WHERE AssessmentMonth = 5 AND ActiveFlag = 1;  -- SCoR-5: May->Apr
```
(Safe: no cycle uses months 2 or 5 under the SCoR mapping, and there are no month-1/4 tasks to collide with.
Re-verify the month set after each seed in case they mis-code a different month next time.)

**Why it surfaced:** Math cycle instances saved with `BenchmarkMonth = NULL` (the `/cycles` form exposed the
month for Reading only), so the roster TVF fell back to each window's DOMINANT calendar month — which for 3
of the 6 cycles (Oct=10, Jan via Nov-Feb, Apr=4) landed on a month with no tasks → blank math grid. Fix was
two-part: (1) set `BenchmarkMonth` = {9,11,1,3,4,6} on the Reading+Math windows per cycle, (2) this task
re-code, (3) expose a "Task month" selector for Math on `/cycles` (`subject === 'Reading'` gate → `!== 'Writing'`).
See [[project_math_assessment_model]], [[project_math_report_blank_roster_bug]].
