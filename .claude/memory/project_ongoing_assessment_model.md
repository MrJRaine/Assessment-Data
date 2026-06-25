---
name: project_ongoing_assessment_model
description: Assessment windows are now MONTHLY bins (open 1st, closed last day); assessment is ongoing — teachers enter multiple dated results per window (grain Student×Window×Date, latest-by-date wins for cohort, history kept) and may enter AFTER a window closes (late entry). Decided + built 2026-06-25.
metadata:
  type: project
---

**Decided 2026-06-25** (supersedes the old "a few discrete assessment windows per year" model).

**Windows = monthly bins.** One `DimAssessmentWindow` row per (AssessmentType × ProgramFamily × ScaleSystem × grade-range) per **month** — `StartDate` = 1st, `EndDate` = last day of the month. "Open / ClosesToday / Closed / Upcoming" is derived from those dates (Atlantic today). Created by **`usp_GenerateMonthlyWindows '<SchoolYear>'[, @IncludeSummer=0]`** (Sep–Jun by default; `@IncludeSummer=1` adds Jul/Aug for off-season testing). Idempotent (skips existing (scope, StartDate)); NULL-safe on the scale (writing's `ScaleSystem` is NULL). Scope catalog inside the proc — extend it for new (type, program, scale, grade) tuples. Live has 2026-2027 Sep–Jun (reading + writing).

**Multiple dated results per window.** The upsert procs (`usp_UpsertReadingAssessment`, `usp_UpsertWritingAssessment`) key on **(StudentKey, AssessmentWindowID, AssessmentDate)**: a new date = a new fact row (prior entries preserved); a same-date re-save = a correction (UPDATE in place). Reads pull the **latest by `AssessmentDate` then entry order** (`ROW_NUMBER` / the cohort's existing latest-pick). **This means any read that joins an assessment fact per (student, window) must pick the latest** — e.g. `tvf_TeacherRoster` had to be fixed (it was fanning a student out to one grid row per entry date).

**Late entry — closed windows stay writeable.** The teacher "closed window" block (reading 51031) was removed. The date gate (51017) caps the assessment date at **MIN(today, window EndDate)**, so a late entry into a past month is dated inside that month (correct binning, never a later month). The web save action sends `MIN(today, windowEnd)` accordingly.

**UI.** `/enter` window-select shows **open windows above the fold + a collapsed accordion of past (closed) windows** (still selectable for late entry); `WindowStatus` comes from `tvf_UserAssessmentWindows`.

**Why:** the program shifted from point-in-time assessment events to continuous progress monitoring; monthly bins give consistent grouping for trend analysis while letting teachers assess + record whenever, including catching up after a month closes.

Related: [[project_assessment_types]] (one type per window still holds), [[project_reading_scale_design]] (dominant month = the window's month now), [[project_timezone_convention]] (Atlantic date gates), [[project_scd_same_day_reversion_fix]].
