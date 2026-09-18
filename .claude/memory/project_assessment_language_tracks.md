---
name: project_assessment_language_tracks
description: "DESIGN (scoping, 2026-09-17) — dual-language (EN/FR) assessment for immersion: reading+writing become language-tracked via the CYCLE (no fact schema change), an EN/FR toggle on picker + entry rosters, and course-based WRITE scoping. J020 reading = English only."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-17T18:42:39.382Z
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

## COURSE-SCOPED ENTRY + CYCLE-BASED /enter (design decided 2026-09-17, NOT yet built)
The entry flow is being reworked from window-based to **cycle-based + course-scoped**. Design (all
confirmed by user; do not re-decide — see [[feedback_no_unilateral_scope_decisions]]):
- **/enter** shows one card per (open SCoR × subject) grouped under Reading/Writing/Math headings. NO
  language toggle. -> choose group -> roster.
- **Language comes from the COURSE the teacher teaches, not a toggle.** Course→(subject,language) map:
  ELA + Immersion-ELA-3–6 → English literacy; FLA → French literacy; Math → Math. A Language-Arts
  course = BOTH Reading+Writing in its language. Course list saved in docs/course-assessment-mapping.md.
- **Group picker** = the caller's **sections whose CourseCode is in the map** only (their gym/science
  drop off). Cards are **multi-selectable within ONE language** (same-language cards combine into one
  roster; can't mix EN+FR). Cards are **grouped under language headings** (like /enter groups by
  subject), shown only when >1 language applies.
- **Roster/save**: combined roster across the picked sections; each student's result routes to THEIR
  program's instance window for that language.
- **Oversight KEEPS its broad scope — over mapped-course SECTIONS** (corrected 2026-09-18; the earlier
  "oversight loses broad entry / view-only" line here was MY INFERENCE from "cut the section list to
  mapped courses", never the user's decision — don't repeat that mistake, see
  [[feedback_no_unilateral_scope_decisions]]). Non-teacher users see cards for **all** sections from the
  mapped course list they would normally be able to see: a **school principal / specialist** sees every
  ELA / FLA / Math section **in their school(s)** (via StaffSchoolAccess); a **RegionalAnalyst** sees
  them region-wide. Teachers see only the sections they teach.
  **Cards for above-teacher users show the section TEACHER'S NAME** so they know whose class it is
  (FactSectionTeachers → DimStaff; a co-taught section lists all of them).
- Chain that makes it work: teacher → FactSectionTeachers → SectionID → DimSection.CourseCode → map.
- **The EN/FR toggle built 2026-09-17 (roster + reverted picker) is INTERIM — remove it** once course
  scoping lands.
- **~~BLOCKER~~ RESOLVED 2026-09-18.** Dev's DimSection has 11 synthetic sections with made-up codes
  (FRA-1-FI, MTH-K-FI, LET-K-FI, HR, SCI-7-FI…), none matching the real list and no English LA at all.
  User's call: the map is a **TABLE** (`DimCourseAssessment`), so **dev seeds the fake codes and live
  seeds the real list** — identical code reads both, and courses are added/removed by row, never by a
  code change. Dev therefore exercises French-literacy + Math scoping; the English side is verified on
  live. Seeds: `seed_DimCourseAssessment_dev.sql` / `seed_DimCourseAssessment_live.sql`.

## FINAL MODEL (2026-09-17) — supersedes everything below. READ THIS.
The user's binding requirement: **assessment methodology (which grades/programs/languages are
assessed how) is configured at the APP LEVEL, per cycle — never hardcoded in a TVF/proc.** I relapsed
into hardcoding rules (grade-3 threshold, "reading is single-language") multiple times; do NOT.
See [[feedback_no_unilateral_scope_decisions]].

**Cycle scope (set on /cycles, stored on DimAssessmentWindow):**
- `AssessmentLanguage` 'English' | 'French' | NULL(Both). Writing "Both" → EN/FR toggle on the entry
  roster; a language-scoped cycle fixes the language (static label, no toggle). Reading: the cycle IS
  the language (English/French sets ScaleSystem; no reading toggle).
- `ProgramScope` — comma-delimited **multi-select** of buckets {English, Early Immersion, Late
  Immersion}; NULL = all. Buckets = `DimProgram.ScopeBucket` (added; non-immersion incl. FSL → English;
  FI name-contains-'Late' → Late; other FI → Early). Roster filters via delimiter-guarded LIKE.
- Grade band `MinGrade`/`MaxGrade` (already existed).
- The admin creates whatever cycles express current policy; e.g. "Immersion 3-6 writing French only" =
  ProgramScope 'Early Immersion,Late Immersion' + grades 3-6 + Language French. Reading in English for
  early immersion 3-6 = just create an English reading cycle scoped to them.

**Result-level language (storage, separate concern):** `FactAssessmentWriting.AssessmentLanguage`
(backfilled by program family) lets a student hold an EN and a FR writing result per cycle;
`usp_UpsertWritingAssessment` stores it. Reading language is already on the result via ReadingScaleID.

**The ONLY hardcoded (structural, factual) rule:** French literacy = French Immersion program (reading
also excludes J020 — late immersion, no French reading benchmarks). Everything else (grades, programs,
language) is cycle config.

**Deploy (dev, this feature):** migrate_DimProgram_add_ScopeBucket.sql +
migrate_DimAssessmentWindow_add_AssessmentLanguage.sql (adds AssessmentLanguage + ProgramScope) +
migrate_FactWriting_add_AssessmentLanguage.sql (done) → usp_UpsertShortCycle.sql →
usp_UpsertWritingAssessment.sql → tvf_TeacherRoster.sql + tvf_TeacherRosterWriting.sql → grants →
swap app image.

---
## (Superseded working notes below)
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
