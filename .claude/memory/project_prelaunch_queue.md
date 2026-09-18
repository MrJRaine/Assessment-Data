---
name: project_prelaunch_queue
description: Running list of user-requested build items ahead of the ~1-week-out launch (0.5.x cycle). Work through these; each may get its own memory when tackled. Not all designed yet.
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-18T16:30:06.809Z
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
8. **Math data entry: red ✗ → yellow circle.** ✅ DONE on dev 2026-09-18. Final form: a HOLLOW circle,
   bright `#ffd21f` band between `#b07d05` edges, drawn in CSS (not a glyph) so its weight is settable;
   the check is drawn to match. Marks scaled to ~32px in the 44px cell. WCAG-compliant — see item 9.
   Stored value and click-cycle unchanged.
9. **Design/aesthetics pass — includes a WCAG 2.1 AA sweep.** The project IS working toward WCAG 2.1
   AA (user, 2026-09-18), but deliberately NOT letting it block feature work: *"good to keep in mind,
   [but] I don't want to get bogged down in it before we are working on cleaning up design
   aesthetics."* So flag contrast/a11y issues in passing, do NOT stop to fix them, and collect them
   here for the pass.

   **RESOLVED 2026-09-18 — math "not yet" ring is now COMPLIANT.** Final form: a hollow circle with a
   bright `#ffd21f` band (5px) sandwiched between `#b07d05` edges (2px, via `box-shadow` outer +
   inset). The EDGE carries SC 1.4.11, measured **3.38:1 on `#f5f7f9`** and **3.32:1 on `#eef6fb`**
   (hover) — both over the 3:1 bar.

   **The transferable lesson for the rest of this pass:** 1.4.11 asks for 3:1 against ADJACENT
   colours, not against the page. So a colour too light to pass on its own can still be used as the
   fill, provided a sufficient-contrast EDGE defines the shape. Chasing the fill colour was the wrong
   move and could not have worked (see the failing values below); moving the burden to the edge let
   the yellow be as bright as the design wanted AND pass.

   Shape matters independently of colour: a FILLED disc reads as "done" and inverts the meaning — the
   open centre is what says "not yet". Both are drawn in CSS, not glyphs, because a font character
   has no adjustable stroke (the check is two borders on a rotated box; as text it stayed hairline
   beside the ring and made the green look washed out).

   The failing attempts, MEASURED by the user (trust these, not my hand arithmetic, which was wrong
   twice) — kept because they show why fill-only cannot work here:

   | colour | on `#f5f7f9` (cell bg) | on `#eef6fb` (hover) | on `#ffffff` |
   |---|---|---|---|
   | `#c9930a` (deployed) | 2.55:1 | 2.50:1 | 2.74:1 |
   | `#c28c00` | 2.77:1 | 2.72:1 | 2.98:1 |

   SC 1.4.11 (Non-text Contrast) wants **3:1**, so BOTH fail — my earlier claim that `#c28c00`
   "clears it" was wrong. The page background is `#f5f7f9` (body `--bg`; the math grid sets no
   background of its own and `.mtoggle` is transparent), NOT white.

   Two traps I fell into, worth not repeating: (a) a DARKER background does not help a mid-dark
   foreground — it reduces the difference, so the grey ground scores WORSE than white; (b) SC 1.4.11
   has NO thickness exemption — only the TEXT rule (1.4.3) scales with size, so the 3px stroke
   improves perceptibility but buys no formal latitude.

   (Superseded by the resolution above.) At the time this read: no yellow in this family reaches 3:1
   unaided, so fixing it means the brown-amber back, or a TREATMENT change — a darker ring with a
   pale fill, or shape carrying the state. The treatment change is what worked — as an EDGE, not a
   fill.
10. **Dark mode** — if it fits before launch. Full scoping in [[project_dark_mode]] (POST-1.0 wishlist,
   but user may pull it in).
11. **Re-record an identical subsequent result.** Data-entry sheets must let a teacher record a NEW
    assessment on a later date whose result is IDENTICAL to the student's existing/latest one (a genuine
    second data point, not a no-op). Today the upsert procs are latest-by-date per window; re-entering
    the same value likely reads as "no change" / doesn't register a fresh dated result. Needs a way to
    stamp a new dated result even when the value is unchanged (reading/writing/math). Design TBD.
12. **QoL (POST-launch): auto-pair an IPP section with its regular section.** PowerSchool keeps IPP
    students in a SEPARATE section from the regular programming section (course code suffix `IP`:
    `MT151` / `MT151IP`, `ENG10` / `ENG10IP`). Course-based entry therefore shows them as two cards,
    and today the teacher selects BOTH via the picker's multi-select to see all their students at
    once — which works (same Kind, and the `IP` row carries the same `Language` as its partner, so
    they land in the same language block). The QoL improvement is to detect the pairing and merge
    them automatically. User (2026-09-18): *"a way to merge them automatically later but that's a QoL
    item for the queue and doesn't apply to every teacher or section."* So it must stay OPTIONAL —
    not every teacher or section has an IPP counterpart, and the manual multi-select has to keep
    working. Likely approach: a partner column on `DimCourseAssessment` rather than inferring from
    the `IP` suffix, since the suffix is a PS naming convention, not a guarantee.
13. **"Areas meeting/exceeding" report.** A report page showing, per student, the COUNT of subjects
    (out of Reading, Writing, Math) where they are currently Meeting or Exceeding expectations — i.e.
    0–3 areas at/above expectation. Cross-subject roll-up; overlaps with Math reporting (#4) and the
    Students→Reports rename (#5). Design TBD.
