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
- **Rename the "IPP" nav item → "Programming."** Landing page has **two headers: "IPP" and
  "Adaptations."** Under EACH header, **a card each for Reading, Writing, Math** (3 cards × 2 = 6).
  Each card opens a page that **looks and functions like the current IPP page, scoped to that one
  subject**.
- **Adaptations are recorded only, for now.** They are NOT shown on data entry and are "really just
  going to be used as a data filter later." The reason to build an Adaptations recording surface now
  is that we need **more specific info on the adaptation's FOCUS than PowerSchool keeps** (PS gives
  only `DimStudent.Adap`, a bare "has adaptations" BIT — [[project_assessment_platform]]).
- **Role-based landing for the Programming pages** (mirrors [[project_group_display_redesign]]):
  - **Teacher** → taken straight to the list of students they teach.
  - **Larger role, single school** → a set of **P-9 homeroom cards + 10-12 section cards**, like data
    entry's group picker.
  - **Larger role, multi-school** → same cards **with a school filter on top**.

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
5. **Adaptations recording area** (net-new): a table like `FactStudentAdaptation` (grain student ×
   subject, + focus detail fields — SHAPE IS THE KEY UNKNOWN), proc, view, TVF, and per-subject
   recording pages under the Adaptations header. Record-only; not surfaced elsewhere yet.

## OPEN QUESTIONS (resolve at AM start, before building)
1. **Adaptations focus fields** — what specifically beyond the PS BIT? Free-text focus, a controlled
   list of adaptation categories, both? Per-subject? This defines the new table + UI (biggest unknown).
2. **Math IPP seeding** — seed a Math `IsIPP=NULL` row for EVERY student PS flags `CurrentIPP` (same
   as Reading/Writing today, teacher confirms No if not a math IPP)? And what **ProgramFamily** do
   Math rows carry, since math isn't program-split?
3. **Group picker** — build the role-based picker as a shared component (reused by data entry, finally
   realizing [[project_group_display_redesign]]) or a Programming-local version for now?
4. **Inline roster IPP confirm** (built today) — keep it alongside the Programming pages, or make
   Programming the single home for IPP confirmation?
5. Confirm Adaptations really wants all three subject cards (Reading/Writing/Math) recorded the same
   per-subject way.

## Schedule note (user owns the call)
This grew past a Thu-EOD slice: nav restructure + Math IPP data path + a NET-NEW Adaptations data
model + a role-based group picker. It competes Fri 2026-09-11 with Math cleanup + teacher-guide
updates, all before teacher testing week of 2026-09-14. Likely can't ALL land before testing — flag
the tradeoff, don't unilaterally defer ([[feedback_no_unilateral_scope_decisions]]).
