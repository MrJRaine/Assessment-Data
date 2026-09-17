---
name: project_prelaunch_queue
description: Running list of user-requested build items ahead of the ~1-week-out launch (0.5.x cycle). Work through these; each may get its own memory when tackled. Not all designed yet.
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-17T14:39:46.129Z
---

**Pre-launch work queue** (captured 2026-09-17; launch ~1 week out). Order not fixed — user directs.
Tackle the live-writing / live-warehouse ones with scope-first sign-off. Mark items done as they ship
and keep this list current (see [[feedback_changelog_as_you_go]]).

1. **Writing `SCR` (Scribed)** — ✅ DONE on dev (built cabdd56, deployed + verified 2026-09-17). SCR on
   **Conventions only** (updated from Conventions+Organization); omitted from the average (sum/count
   over scored traits). ConventionsScore INT→VARCHAR via multi-step migration. Still to ship LIVE at
   the 0.5.0 release (see CHANGELOG deploy list). Full spec [[project_writing_scribed_score_code]].
2. **Dual-language assessment + course write-scoping** — SCOPED, see [[project_assessment_language_tracks]].
   Reading+writing become language-tracked (EN/FR) via the CYCLE (no fact schema change); EN/FR toggle
   on picker + entry rosters; J020 reading = English only; course-based WRITE scoping (course-name list
   PENDING from user). Reuses the IPP/Adaptation split rule. Phased: (1) J020 reading carve-out now,
   (2) language track + toggle, (3) course write-scoping when list arrives.
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
10. **Re-record an identical subsequent result.** Data-entry sheets must let a teacher record a NEW
    assessment on a later date whose result is IDENTICAL to the student's existing/latest one (a genuine
    second data point, not a no-op). Today the upsert procs are latest-by-date per window; re-entering
    the same value likely reads as "no change" / doesn't register a fresh dated result. Needs a way to
    stamp a new dated result even when the value is unchanged (reading/writing/math). Design TBD.
11. **"Areas meeting/exceeding" report.** A report page showing, per student, the COUNT of subjects
    (out of Reading, Writing, Math) where they are currently Meeting or Exceeding expectations — i.e.
    0–3 areas at/above expectation. Cross-subject roll-up; overlaps with Math reporting (#4) and the
    Students→Reports rename (#5). Design TBD.
