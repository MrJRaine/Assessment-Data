---
name: project_assessment_language_tracks
description: "DESIGN (scoping, 2026-09-17) — dual-language (EN/FR) assessment for immersion: reading+writing become language-tracked via the CYCLE (no fact schema change), an EN/FR toggle on picker + entry rosters, and course-based WRITE scoping. J020 reading = English only."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-17T15:10:21.615Z
---

**Dual-language assessment + course-based write scoping — design decided 2026-09-17, not yet built.**
Grew out of pre-launch queue item "immersion reading" ([[project_prelaunch_queue]]). Scope-first;
touches live warehouse + write-permission model, so build in confirmed phases.

## The problem
Immersion students are assessed in BOTH French and English literacy from grade 3 up (French only
below gr 3). Today each student gets exactly ONE reading scale, derived from ProgramFamily
(`tvf_TeacherRoster` ~line 233: English→EN_Reading, FI→FR_Reading) — no second track. Writing is
worse structurally: `FactAssessmentWriting` has no language column at all (grain = student, window).

## The model (reuse the IPP/Adaptation split — already in prod)
Language track = a per-(subject) axis, SAME rule already seeded in `usp_MergeStudent` Step 6 /
`FactStudentAdaptation`:
- **English track (reading+writing):** English program any grade OR FI grade ≥ 3.
- **French track (writing):** FI any grade.
- **French track (reading):** FI any grade **EXCEPT J020** (late immersion — no French reading
  benchmarks; they read in English). This J020-reading carve-out is the ONLY reading exception.
- **Math:** single track, own family, P–6 only — never language-split (same as adaptations).

## CORRECTED MODEL (2026-09-17, after user clarified) — language on the RESULT
Supersedes the "language on the cycle" approach explored below (kept for context). The user
confirmed: **reading is single-language per student** (English program + J020 -> English; early
immersion -> French; one reading result per student -> reading needs ONLY the J020 fix, no language
cycles), and **writing is dual** for FI grade>=3 (English AND French) -> language must live ON THE
WRITING RESULT. Existing results are tagged by PROGRAM language (English/FSL -> 'English', French
Immersion -> 'French'); no ambiguity because existing data predates dual-track.
- **FactAssessmentWriting**: add `AssessmentLanguage VARCHAR(10)`; grain becomes
  (StudentKey, AssessmentWindowID, AssessmentLanguage, AssessmentDate). Backfill by program family
  (migrate_FactWriting_add_AssessmentLanguage.sql). Writing cycles stay region-wide.
- **usp_UpsertWritingAssessment**: add @AssessmentLanguage param + grain + validation.
- **tvf_TeacherRosterWriting**: add @Language param (from the EN/FR toggle); track membership
  (English = English-program OR FI grade>=3; French = FI incl J020); return that language's scores.
- **Reading**: single-language, per-student derivation + J020->English (tvf_TeacherRoster, DONE).
  Reading needs NO language column, NO @Language param.
- **Toggle**: EN/FR on the WRITING entry roster (and picker) switches the language being entered.
- The DimAssessmentWindow.AssessmentLanguage column + usp_UpsertShortCycle language changes started
  earlier are being UNWOUND (wrong home; reading is region-wide single-language, writing is fact-level).

## (Superseded) Key structural insight — language rides on the CYCLE, so NO fact schema change
The window is already in both fact grains (writing grain = StudentKey, AssessmentWindowID,
AssessmentDate). So an FI gr-5 student's French writing lands in the FR writing cycle and their
English writing in the EN writing cycle — two rows, existing grain. Same for reading. The fix is to
make cycles carry (assessment type × grade range × program × **language/scale**) and make the roster
**HONOR the window's ScaleSystem/scope** instead of re-deriving scale from the student's family
(that re-derivation at `tvf_TeacherRoster` ~line 233 is the actual bug). DimAssessmentWindow already
has MinGrade/MaxGrade/ProgramFamily/ScaleSystem; the gap is that a single ProgramFamily value can't
express "English track = English-program OR FI-grade-3+" — so a cycle needs richer membership than one
family (a cycle→(program×grade) scope mapping, or a Track/Language column + a resolver reusing the
adaptation rule). This is the user's ask: "scope EN/FR from inside the system."

**WHERE cycles are configured (corrected 2026-09-17):** the monthly generator
(`usp_GenerateMonthlyWindows`) is ABANDONED. Cycles are created/edited MANUALLY on the `/cycles` page
(`ShortCyclesManager.tsx` → `usp_UpsertShortCycle`). That proc TODAY forces every cycle region-wide:
`ProgramFamily = NULL`, `ScaleSystem = NULL` (grade band MinGrade/MaxGrade already supported;
multi-subject cycles group per-subject rows via `@CycleGroupID`). So broadening = expose **language/
scale + program scope** on that page + proc (extend the per-subject CycleGroup pattern to per-(subject
× language)), then make the rosters honor it. No monthly-generator change needed.

## UX
- **EN/FR language toggle** at the top of the group picker AND on data-entry rosters, to switch the
  language of assessment being entered. (Shown when both tracks are in play.)

## Write scoping (NEW requirement, 2026-09-17) — narrow WHO can submit, by course
Submit ability is narrowed by the specific course the teacher teaches:
- English reading + writing entry → only teachers of the student's **English** course.
- French reading + writing entry → only teachers of their **French** course.
- Math entry → only teachers of their **Math** course.
Needs a course-name → (subject, language) classification. **DEPENDENCY: user is sending the list of
applicable course names.** Likely a reference map (course name → subject+language) applied to
DimSection; narrows the existing FactSectionTeachers-based write roster (the `allowed` scope-gate in
the entry server actions).
**Data VIEW is UNCHANGED / stays broad:** anyone who teaches the student OR has PS school access can
view cohort/reports. Only WRITE/submit is course-gated.

## Proposed build sequence (confirm each)
1. **J020 reading carve-out** — self-contained, unblocked, folds into the cycle model later:
   Programming seeding emits Reading→English only for J020 (no FI reading row); Writing→both;
   reading data-entry resolves J020 to EN_Reading. Writing untouched.
2. **Language track + EN/FR toggle** — extend the manual `/cycles` page + `usp_UpsertShortCycle` to
   set language/scale + program scope per cycle; rosters honor it; EN/FR toggle on picker + entry
   rosters; enables dual-language reading + writing.
3. **Course-based write scoping** — when the course-name list arrives: classify sections by
   subject+language; narrow write rosters; keep view rosters broad.

Launch is ~1 week out (from 2026-09-17) — decide per phase whether it lands pre-launch or fast-follow.
