---
name: project_programming_makeover
description: "The 'IPP + Adaptations makeover' — rename the IPP nav to 'Programming', add Math IPPs (not just Literacy), add an Adaptations recording area, and give the section a role-based group picker. Scoped 2026-09-10; build is the next 0.5.0 feature. NOT built yet."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-10T18:16:26.984Z
---

**The "IPP + Adaptations makeover"** (sprint item from [[project_teacher_testing_sprint]]). Scoped
with the user 2026-09-10; **planning only so far — no code written.** Ships as part of **0.5.0**
(branch `feature/prior-year-baseline`, now at 0.5.0-dev). Bigger than one sitting — see schedule note.

## The vision (user's words, distilled)
- **Core goal: IPPs identifiable for BOTH Math and Literacy.** Current app only does Literacy.
- **Rename the "IPP" nav item → "Programming."** (REVISED 2026-09-11 — collapsed from 6 cards.)
  Programming has **TWO rosters: an IPP roster and an Adaptations roster** (not 6 per-subject cards).
  Each roster = **one grid, one row per student, `Reading | Writing | Math` as COLUMNS**; each cell
  is that subject's confirm control. Data model unchanged (still per student×subject×programFamily) —
  this is a UI pivot from long to wide.
  - **Adaptive cell (handles the FI EN/FR literacy split in one column):**
    - English-program students, and FI students **below grade 3** (single literacy context) → cell is
      **No / Yes**.
    - **FI students grade 3+** (both FLA + ELA literacy rows) → Reading/Writing cell is a 4-way
      **No / FLA Only / ELA Only / Both**, writing the two rows: No→(FR 0,EN 0), FLA Only→(FR 1,EN 0),
      ELA Only→(FR 0,EN 1), Both→(FR 1,EN 1). [FLA=French Language Arts=French Immersion row;
      ELA=English Language Arts=English row.]
    - **Math** → always **No / Yes** (single row, P-6 only).
    - Any cell whose underlying row(s) are NULL shows **Needs confirmation** until set.
  - `usp_UpsertStudentIPP` / `usp_UpsertStudentAdaptation` already take `(Subject, ProgramFamily)`, so
    the 4-way just sends the right PAIR of upserts — no proc change needed for the split.
- **Grade-band pre-filter (2026-09-11) — fewer cells per student.** A subject's cell only appears where
  that subject applies to the student's grade, matching the per-subject cycle bands: **Reading P-8,
  Writing P-RG (all), Math P-6**. So a grade-10 flagged student shows only a Writing cell; grade-7
  shows Reading+Writing; grade-3 shows all three. Driven by the **seeding**: `usp_MergeStudent` seeds a
  subject's rows only for in-band grades (Reading GradeOrder 0-8, Writing 0-13, Math 0-6; PP=-1
  excluded — bands start at P), so the roster shows a control only where a row exists.
  **Consequence:** this CHANGES the existing literacy IPP seeding — Reading rows are no longer created
  for grades 9-12 (and PP), so those moot rows get closed on the next merge (Step 6a). Bands hardcoded
  here to mirror the cycle config; if the cycle bands change, update both.
- **Adaptations = per-subject yes/no, exactly like IPP (RESOLVED 2026-09-11).** NOT a taxonomy of
  adaptation types/focus — the "more specific than PowerSchool" simply means breaking PS's ONE global
  `DimStudent.Adap` flag out **per subject** (has an adaptation for Reading / Writing / Math). So the
  Adaptation pages are the SAME per-subject confirmation grid as IPP, just keyed on `Adap`. Recorded
  only, for now (not shown on data entry; "used as a data filter later"). No category list needed.
- **Role-based landing for the Programming pages** (mirrors [[project_group_display_redesign]]).
  **The group/card selection GATES the rosters for non-teachers — it is NOT skippable.** Flow:
  - **Teacher** → straight to their students (auto-scoped; picks among their own homerooms/sections
    if they teach more than one).
  - **Larger role, single school** → **P-9 homeroom cards + 10-12 section cards** first, then the roster
    for the chosen group (like data entry's group picker).
  - **Larger role, multi-school** → same cards **with a school filter on top** (+ grade filter).
  - THEN the roster (IPP ⟷ Adaptations) for the selected group. Same shared picker as Data Entry
    (Phase 1) — this is what lets a teaching-admin reach their OWN classes, not the school-wide dump.

## Current state (grounded 2026-09-10)
- **IPP data model is ALREADY per-subject and Math-ready.** `FactStudentIPP` grain = (StudentKey,
  **Subject**, ProgramFamily); header explicitly says Subject accommodates 'Math' with **no schema
  change**, and a student can have a Reading IPP but not Writing. Rows seed as `IsIPP=NULL` ("needs
  confirmation") when PS flags `CurrentIPP`, teacher confirms Yes/No.
- **What blocks Math IPP today:** `usp_UpsertStudentIPP` throws 51012 unless @Subject IN
  ('Reading','Writing') — a deliberate "Math added when ready" guard. And the **seeding** logic (in
  `usp_MergeStudent`, which inserts the Reading/Writing NULL rows on IPP flag) does not insert a Math
  row. So Math = relax the guard + seed Math rows + expose Math in reads/UI. Not a rebuild.
- **Current IPP UI:** single flat page `/ipp` ([webapp .../ipp/page.tsx], IPPManager.tsx) titled "IPP
  Subject Confirmation"; `getStudentIPPList(upn)` returns ALL in-scope rows (Reading+Writing), no
  subject filter, **no group picker**, role handled only by the TVF's RLS. Confirm control labels
  "Yes (Literacy IPP)" (see [[project_ipp_type_labelling]] — Math label = "Yes (Math IPP)").
- **Adaptations: nothing in the webapp.** Only `DimStudent.Adap` BIT exists. No table for focus
  detail, no proc, no view, no page.
- **Inline roster IPP confirm** (built today, in the reading roster "New level" cell) coexists with
  the `/ipp` page — need to decide if it stays once Programming exists.

## Build plan (phased; confirm open questions first)
1. **Nav + landing.** Rename nav "IPP"→"Programming"; route `/ipp`→`/programming` (redirect old).
   Landing = two sections (IPP, Adaptations) × three subject cards each. Cards show a count of
   students needing confirmation in scope.
2. **Math IPP (data path).** Allow 'Math' in `usp_UpsertStudentIPP`; seed Math `IsIPP=NULL` rows in
   `usp_MergeStudent` for IPP-flagged students; extend `vw_StudentIPP`/`tvf_StudentIPP`/`getStudentIPPList`
   to carry subject filter incl. Math. Decide Math's ProgramFamily (math isn't EN/FR-split).
3. **Per-subject IPP page.** IPPManager filtered to one subject (reuse as-is, add subject prop);
   Math label "Yes (Math IPP)".
4. **Role-based group picker** for the Programming section — the [[project_group_display_redesign]]
   pattern (teacher direct / single-school homeroom+section cards / multi-school + school filter).
   Decide: build as a SHARED component to reuse in data entry, or Programming-only for now.
5. **Adaptations recording area** — a **clone of the IPP machinery**, keyed on `DimStudent.Adap`
   instead of `.IPP`: `FactStudentAdaptation` mirrors `FactStudentIPP` (SCD Type 2, grain
   StudentKey × Subject × ProgramFamily, `HasAdaptation` NULL=unresolved gate), seeded in
   `usp_MergeStudent` from `Adap=1` the same way IPP seeds from `IPP=1` (incl. Math P-6). A parallel
   `usp_UpsertStudentAdaptation` / `vw_StudentAdaptation` / `tvf_StudentAdaptation`, and the SAME
   per-subject confirmation component (parameterized IPP-vs-Adaptation) renders both. NO focus fields.
   Record-only; not surfaced in data entry yet. (Alt considered: one generalized table with a
   Type column — rejected to avoid disturbing the working IPP path; parallel table is lower risk.)

## DECISIONS (2026-09-11)
1. ✅ **Adaptations** = per-subject yes/no, mirror IPP — NO focus/category taxonomy (see vision bullet).
2. ✅ **Math IPP seeding** (recommended, not vetoed): seed one Math `IsIPP=NULL` row per `IPP=1`
   student **in grades P-6 only** (where Math cycles live), `ProgramFamily` = the student's OWN
   program — a **single row, no EN/FI dual-split** (math isn't language-split). Same for Math
   Adaptations. Confirm via the Math card.
4. ✅ **Inline roster IPP confirm KEPT** alongside the Programming pages (inline = convenient during
   entry; Programming = bulk management). Not either/or.
5. ✅ Adaptations wants all three subject cards (Reading/Writing/Math), same per-subject way as IPP.

3. ✅ **Group picker = FULL SHARED REDESIGN (chosen 2026-09-11).** User: "go ahead with the proposed
   changes to the picker to help with teaching admin… so it's consistent and we don't reinvent the
   wheel." So build [[project_group_display_redesign]] ONCE as a shared component adopted by BOTH Data
   Entry AND Programming — teacher → their taught groups; above-teacher roles → Homeroom⟷Section toggle
   over full P-RG + grade filter atop the school filter; **dual-role teaching-admin sees their OWN
   classes, not just the school-wide dump** (the whole point). This RETIRES the group_display_redesign
   backlog item. Touches the LIVE Data Entry flow → design carefully + test every role combo.

## BUILD SEQUENCE (2026-09-11)
- **Phase 0 — backend, picker-agnostic (start now):** Math IPP guard relax + `usp_MergeStudent` seed
  (Math P-6, own program, single row); `FactStudentAdaptation` + `usp_UpsertStudentAdaptation` +
  vw/tvf mirrors, seeded from `DimStudent.Adap`.
- **Phase 1 — shared group picker (the big/risky piece):** redesign the group-resolution SQL
  (`tvf_TeacherGroups` etc.) + a shared choose-a-group UI adopted by Data Entry AND Programming.
- **Phase 2 — Programming pages:** nav rename `/ipp`→`/programming`; TWO rosters (IPP + Adaptations),
  each a student×`Reading|Writing|Math` grid with the adaptive cell (2-way / 4-way FLA-ELA / Math),
  rendered by ONE shared roster component parameterized IPP-vs-Adaptation. Reads return the per-student
  per-subject statuses for BOTH program families (so the cell can pick 2-way vs 4-way); writes reuse
  the existing per-(subject,programFamily) upsert procs.

## Schedule note (user owns the call)
This grew past a Thu-EOD slice: nav restructure + Math IPP data path + a NET-NEW Adaptations data
model + a role-based group picker. It competes Fri 2026-09-11 with Math cleanup + teacher-guide
updates, all before teacher testing week of 2026-09-14. Likely can't ALL land before testing — flag
the tradeoff, don't unilaterally defer ([[feedback_no_unilateral_scope_decisions]]).
