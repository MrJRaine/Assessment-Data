---
name: project_prelaunch_queue
description: Running list of user-requested build items ahead of the ~1-week-out launch (0.5.x cycle). Work through these; each may get its own memory when tackled. Not all designed yet.
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-17T13:28:24.109Z
---

**Pre-launch work queue** (captured 2026-09-17; launch ~1 week out). Order not fixed — user directs.
Tackle the live-writing / live-warehouse ones with scope-first sign-off. Mark items done as they ship
and keep this list current (see [[feedback_changelog_as_you_go]]).

1. **Writing `SCR` (Scribed)** — IN PROGRESS (scoping). Full spec [[project_writing_scribed_score_code]].
   Add SCR on Conventions/Organization only; omit from the average (sum/count over scored traits).
2. **Immersion reading: early vs late immersion.** Differentiate how FI reading is treated for EARLY
   vs LATE immersion students (different entry points / expectations). Design TBD — clarify the rule
   with the user (which grades = late entry, and how the benchmark/expectation differs).
3. **Revisit the Writing student-cohort page layout.** UX rework of `/students` (writing subject view);
   specifics TBD.
4. **Math reporting.** Cohort/reporting pages for Math (by-task proportion + by-student achievement
   level) — the reporting side of [[project_math_assessment_model]] (entry is built, reporting is TODO).
5. **Rename the "Students" page → "Reports".** Nav + page title + home card; the page is really the
   reporting/cohort view.
6. **Math task → score pull respects split-grade pacing.** A split-grade homeroom can have different
   pacing guides per grade to align content across the split; the task set pulled for a student must
   reflect that grade's pacing, not just grade+month. Revisit `tvf_TeacherRosterMath` task selection
   (currently DimMathTask by GradeCode + AssessmentMonth). Design TBD.
7. **Linked math tasks carry mastery forward.** If a task is LINKED to a later task and the student was
   "Meeting" on the earlier one, the later task starts the cycle already showing Meeting for that
   student. Needs a task-link model in DimMathTask + carry-forward logic in the roster read/entry.
8. **Math data entry: red ✗ → yellow circle.** Cosmetic — the "cannot / 0" cell glyph/colour in the
   math matrix (`MathRosterEntry`, `.mtoggle .no`) should be a yellow circle instead of a red X.
9. **Dark mode** — if it fits before launch. Full scoping in [[project_dark_mode]] (POST-1.0 wishlist,
   but user may pull it in).
