---
name: project_feature_ideas_and_backlog
description: Release-triaged work queue. LIVE through 0.6.0 (2026-09-22). Forward triage 1.0 → post-launch → post-1.0 set by the user 2026-09-18 — respect those calls; do not re-litigate or re-order. Keep current per feedback_keep_memories_current.
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-11-17T16:23:14.081Z
---

**Triaged by the user 2026-09-18.** Release targets are THEIR calls. Work top-down within a section;
don't promote, defer, or re-order an item without asking. Prune this list as items ship
([[feedback_keep_memories_current]]).

---

# SHIPPED — history, do NOT re-raise

- **0.5.0** — LIVE 2026-09-21. Students→Reports rename (+ redirect) & home reorg (Data Entry/Reports
  swap + gated Admin Tools section + brand-logo-home); reading/writing **re-record checkbox**;
  self-contained reading/writing facts; **Math P–6 task entry**; **Programming (IPP + Adaptations)
  makeover**; group-picker redesign; **maintenance mode**; dual-language literacy + per-cycle scoping.
- **0.5.1** — LIVE 2026-09-21. Roster streams via in-page `<Suspense>` (fixes the dead-click from
  `prefetch={false}` — `loading.tsx` doesn't fire on non-prefetched dynamic nav).
- **0.6.0** — LIVE 2026-09-22. "**The SCoR Hub**" rename; **French math answer key**; **RegionalAnalyst
  RLS scoped by `StaffSchoolAccess`** (security fix, all 13 TVFs); reading cycle-card count fix; 14
  mislocated immersion results migrated; math task bank `AnswerKeyFR` + widened `AnswerKey`. All three
  local containers (awlive :3000 / awdev :3001 / awdev-impersonation :3002) on 0.6.0.
- **Re-record ("New Data") — CLOSED.** Reading + Writing shipped it (0.5.0). **Math is EXCLUDED BY
  DESIGN — settled**: binary mastery, the only change is no→yes which the cell edit already captures;
  do not re-open ([[project_math_assessment_model]]).
- **Demo dev data — DONE 2026-09-22.** Prior-year June + partial SC1 results seeded via
  `sql/scripts/seed_demo_results_dev.sql` (hash-seeded per-student bell curves; DEV-guarded, idempotent).
- **Math outcome "met-ever" / subsequent-opportunities framework — RESOLVED 2026-09-21, no new schema.**
  User: *"that's all the math stuff we just decided on."* "Met an outcome in any opportunity this year"
  is answerable from `DimMathTask.OutcomeCode` (frozen on the fact) + dated `FactAssessmentMath` history —
  **no** `DimMathOutcome` dimension, **no** non-null enforcement, **no** carry-forward hook for this.
  (Split-grade pacing + linked-task carry-forward are separate post-launch items below.)

---

# ACTIVE QUEUE — user priorities set 2026-11-10 (work in this order)

1. ~~Reports release (1.4.0)~~ — **SHIPPED, LIVE 2026-11-18** (tag v1.4.0; Missing results, filters on
   every report tree incl. Math, Math donut + by-cycle bars, filter carry-over). Math band palette
   alignment REJECTED 2026-11-10: the math-band colours are the math team's specific request — a
   deliberate deviation; see [[stakeholder-preferences]]. Do not re-propose.
2. **Split-grade math pacing delivery** — promoted from post-launch; new UI direction + structural
   delta (section-scoped exceptions) in [[project_math_split_pacing_model]] §2026-11-10.
3. **Math task chains / carry-forward** — promoted from post-launch; additions (flagged-role editing,
   fill-on-cycle-open, earliest-origin provenance) in [[project_math_split_pacing_model]] §2026-11-10.
4. **Quick QoL + finishable in-flight items** — e.g. HS one-list-per-section entry fix (below; needs a
   50-ft decision on save routing across cycle instances), LOTO confirm dialog, maintainer note.

- **Repo review 2026-11-09 — PARKED (user 2026-11-10) until a full feature set is out.** Removal triage
  (~215 files), flag→state transition plan, congruence findings + streamlining plan:
  `docs/repo-review-2026-11-09.md` (committed 7843929). Nothing in it actioned; don't act unprompted.
- **ONE feed per subject + client-held cohort (user floated 2026-11-10, Claude agreed directionally).**
  Replace the per-subject trio (tvf_StudentCohort / *All / *Group) with ONE TVF per assessment type,
  fetch once, derive Summary AND Student list client-side → instant view switching, no Fabric trip per
  switch, drills free. Joins the parked review's C-8/C-5 streamlining; trade-offs flagged: heavier
  single query/payload (region-wide with names for analysts), the all-cycles trend copy is still a
  second read (or a per-cycle grain), freshness vs TTL caching. DESIGN with the review follow-ups
  after the feature set is out — the 2026-11-10 summary-filter work widened the duplication (the
  demographics now live in 4 TVFs), which strengthens the case.

# OPEN — near-term (not release-bound)

- **Math report: expand a unit to see task-level achievement roll-ups when filtered to ONE grade
  (user 2026-11-18, NOT yet triaged to a release).** User's words: "when we filter down to a single
  grade in the math report … we can then expand the units to see the achievement roll ups of the
  individual tasks." So: on the Math summary tree, once the Grade filter is narrowed to a single grade,
  each unit column/row becomes expandable into its individual tasks, each showing its own achievement
  roll-up. *My reading, unconfirmed:* single-grade is the gate because tasks are grade-specific (a
  multi-grade view has no common task set); the roll-up per task would be the share of students who
  can do it (tasks are binary), shown the same way the unit cells are. *Open before building:* what
  the per-task cell shows (% can-do vs a band), whether it respects the Blanks mode + filters like the
  unit cells, and the data source — the tree feed (`tvf_StudentCohortMathAll`) is unit-grain counts
  only; task grain exists only in the per-group feed (`tvf_StudentCohortMath`), so this needs either a
  task-grain roll-up feed or a client roll-up of the per-group rows. Needs the 50-ft proposal first.
- **Math regional "pick your homerooms" report, for targeting PD (user 2026-11-18, NOT yet triaged to
  a release).** User's words: "a regional report that lets me select a grade level for math and then
  select specific homerooms that I can click checkboxes to include them in the report and create
  essentially a bespoke roll up tree with just those homerooms so that we can better target PD to the
  teachers that are coming in rather than the general whole region data set. The report would show all
  of the tasks within the given time period (Current/Cycles) and the rolled up performance of each
  homeroom and then a roll up at the top for the whole active data set." So: pick ONE math grade ->
  tick homerooms (across schools, region-wide) -> a tree of just those homerooms; columns/rows = every
  task in the selected period (Current or a cycle); one roll-up per homeroom + a top roll-up over the
  whole ticked set. Purpose = PD sessions built around the teachers attending.
  **RULED by the user 2026-11-18:** (1) AUDIENCE = Regional Analyst ONLY "to start" (access still via
  per-school StaffSchoolAccess rows — no region-wide branch); (2) TASK CELL = a % with colour-coding
  "according to achievement level"; (3) FILTERS apply — yes (Blanks mode + the demographic filters);
  (4) SELECTIONS are fresh each visit "to start for now" (no saved/named sets yet); (5) SPLIT
  HOMEROOMS show under EVERY grade they hold, but ONLY the students of the picked grade enter the
  roll-up; (6) rows are labelled by the HOMEROOM IDENTIFIER only — no teacher names; (7) the % =
  share of students who can do the task — user's exact words: "percentage, yes, omitting anyone with
  an IPP in that field, and omitting anyone who has an unconfirmed IPP." CORRECTED 2026-11-18 (I
  first recorded this as "omit every Math-IPP student = the existing rule"; the user: "That is not
  what I said and it is not the existing math report rule" — both true). Corrected reading, ACCEPTED by
  the user 2026-11-18 ("that's better"): "that field" = the TASK cell — a CONFIRMED-IPP student is left out of a
  task's % only for the tasks their plan deletes, and still counts on every other task; a student with
  an UNCONFIRMED IPP is left out of every task. The existing rule is in [[math-ipp-display-rules]]
  (confirmed IPP COUNTS with deleted outcomes dropped from the numerator; unresolved = unmeasured) —
  READ IT before describing it. Per [[feedback_never_silently_omit]] the report must SAY how many were
  left out.
  (8) COLOUR — user 2026-11-18: "colour coded the same way it is for the tasks in data entry." Read
  from the code that day: `heatClass` in `MathRosterEntry.tsx` (same function exported from
  `reports/math/mathModel.ts`) — >80% h4, >=65% h3, >=50% h2, below 50% h1, no scored marks = none.
  These are the TASK heat cut-offs, NOT the unit band cut-offs (50/75/90) I had assumed. The entry
  grid's `taskPct` = can-do / students with a 0 or 1 mark on that task (IPP-deleted cells and blanks
  out of the denominator) — consistent with ruling 7.
  HOW THE EXISTING MATH CLASS VIEW ALREADY HANDLES THE TASK % (read 2026-11-18,
  `reports/math/[groupKey]/MathCohortView.tsx` `taskPct` + `mathModel.ts` `buildMarks`): identical
  formula — can-do / cells marked 0 or 1. (a) BLANKS MODE DOES NOT TOUCH IT: `blankMode` only feeds
  the unit/student averages (`unitStat`), never the per-task %. (b) A confirmed-IPP student's
  unmarked cells become 'ipp' and drop out; their marked cells count. (c) It is fed `g.students` —
  ALL the group's students — so an UNCONFIRMED-IPP student's existing 0/1 marks DO count in the task
  % there (the entry gate blocks NEW marks, but marks saved before the flag remain). TWO DIVERGENCES
  from the user's rulings to put to the user as questions, both behaviours named: ruling 3 (Blanks
  applies) vs (a); ruling 7 (unconfirmed IPP out of every task) vs (c).
  *My reading, unconfirmed:* task-grain like the item above, so the two likely share one
  task-grain feed; "Current" for Math is current-year (task x grade x month model,
  [[project_current_mode_semantics]]). Still needs the 50-ft proposal (tables/fields) before building.

- **FIX, NEXT VERSION WE WORK ON (user 2026-11-04): secondary data-entry splits a section into
  per-program lists.** On the data-entry page, a SECONDARY (HS) section's students are divided into
  separate lists by their program; they should be ONE list per section on the page. User wants this
  bundled into the next version worked on (1.4.0 candidate, alongside the pending charts fix).
- **Write-rule rescue path for NOT-in-export coach-role overrides (gap found 2026-10-30).** usp_MergeStaff
  Step 2's not-in-staging rescue UNION covers ONLY `Maintenance` overrides — an active
  Administrator/RegionalAnalyst/SpecialistTeacher override for someone absent from the PS staff export is
  re-dropped by EVERY ingest (the Save can restore them only while they're in the latest staging). Fix =
  widen the UNION — but it needs a USER scope decision first: a not-in-PS RegionalAnalyst would have the
  role with NO PS-derived schools (empty StaffSchoolAccess) — synthesize all-schools scope, or require a
  PS record for region-wide access?
- **Section-merge gate vs on-leave teachers w/ subs (census done 2026-11-06, decision pending).** A section
  whose PRIMARY fails the merge's resolve gate (current+active DimStaff) is excluded, killing even
  good-standing CO-TEACHERS' assignments (`usp_MergeSectionTeachers` current-DimSection check). Real case:
  long-term sub Sarah Thornton lost 15 Meadowfields sections because on-leave primary (jocelyne.veinot@,
  on the 28-email SIS hand-off list) dropped from the staff export. Census
  (`sql/scripts/count_sections_inactive_primary_trap.sql`): this is the ONLY instance with a resolvable
  co-teacher stranded; every other trapped section is a stale not-purged PS section the gate is CORRECTLY
  filtering. **PARKED by user 2026-11-06** — follow up later if the leave-with-sub pattern recurs; do not
  build the gate relaxation unprompted (it would resurrect the stale sections as live DimSection rows).
  **Chosen remedy (user, SIS-side): make the SUB the section LEAD teacher in PS for those sections** — the
  better records-keeping fix (export then names who is actually teaching), and the sections self-heal on
  the next ingest. Not "add the on-leave teacher back to the staff export."
- **Maintenance + ingest end-to-end dry-run on dev.** The lockout + ingest flow ship in the containers
  but have never been run start-to-finish. Prove on dev (schedule → land → `/enter` locks while
  `/ingest` + `/admin/maintenance` stay usable → clear) BEFORE any live use.
- **Memory consistency audit — DEFERRED (user 2026-09-22).** One-time sweep of the memory set for
  stale / contradictory / superseded entries; hand the user a findings list BEFORE editing.

*(Math task-bank completeness is NOT ours — the math team owns delivering the grades 4/5/6 outcomes;
we're not blocked and it's not our queue item.)*

---

# 1.0 — in progress

- **"Areas meeting/exceeding" report** *(user: "should make it into 1.0 if at all possible")*. Per
  student, the COUNT of subjects (Reading / Writing / Math) currently Meeting or Exceeding (0–3).
  Cross-subject roll-up; overlaps the Reports area.
- **Auto-pair an IPP section with its regular section** *(user: "nice to have for 1.0 but can drop")*.
  PS keeps IPP students in a SEPARATE section (`MT151` / `MT151IP`). Manual multi-select already handles
  it → convenience only, must stay OPTIONAL. Prefer a partner column on `DimCourseAssessment` over
  inferring from the `IP` suffix (a PS naming convention, not a guarantee).
- **Writing student-cohort page layout — NEEDS RE-SCOPING.** User 2026-09-18: *"I don't even remember
  the plan."* Ask what the layout problem actually is before building anything.

---

# Post-launch — after 1.0

- **Math reporting** *(user: "skip for now, only relevant in SCoR 2")*. Cohort/reporting for Math
  (by-task proportion + by-student achievement level). Entry is built; reporting is not.
- ~~Split-grade math pacing~~ / ~~Linked math tasks carry mastery forward~~ — **PROMOTED 2026-11-10 to
  the ACTIVE QUEUE (priorities 2 & 3 above)**; full design + new direction in
  [[project_math_split_pacing_model]].

---

# Post-1.0

- **Achievement-chip typography/shape pass** *(user 2026-11-17, cosmetic)*. 1.4.0 standardized every
  Reading/Writing report achievement cell on chips (`.ach-chip`, matching Math's `.mband` geometry;
  `IPP?` orange, `IPP` purple). "Fine for now" — revisit font size / chip shape in a future version so
  the chips better fill the column space (they currently sit small inside the row height). Pure CSS.
- **LOTO sysadmin-override confirm dialog** *(user 2026-10-27, QoL/safety)*. When a **sysadmin** clears a
  maintenance window they did **not** open, prompt a confirm first naming the owner — e.g. "You are
  cancelling a maintenance window set by user: XYZ" (XYZ = `AppMaintenance.SetByEmail`). Fires ONLY on the
  sysadmin-override case (caller is sysadmin AND caller ≠ owner); the owner clearing their own window, and
  the ingest auto-clear, get no prompt. LOTO itself ships in 1.3.0 ([[project_maintenance_mode]]); this is
  the "are you sure you're breaking someone else's lock" guardrail on top. **Impl hook:** the client clear
  paths (`MaintenanceControl.clear`, `MaintenanceProvider.clearNow`) don't currently know the owner email —
  `/api/status` returns only `maintenanceAt`/`serverNow`/`message`, so surface `SetByEmail` (and whether the
  viewer is the owner) there first, then gate the `confirm()` on it.
- **Maintainer-only lockout reason field** *(user 2026-10-27, QoL/ops comms)*. On the maintenance page, a
  field where whoever opens a window records WHY it's locked (e.g. "Fabric server being migrated — no DB
  alterations"), **visible only to other maintenance-flagged staff** (CanMaintain / sysadmin), so peers
  understand the lock without tracking the opener down. **DISTINCT from the public `AppMaintenance.Message`**
  (the banner/overlay text every user sees) — this is an INTERNAL note. **Impl hook:** add a column to
  `AppMaintenance` (e.g. `MaintainerNote`); `usp_SetMaintenanceWindow` takes it; render it only to a
  maintainer — do NOT put it in the public `/api/status` payload (it would leak to teachers); gate it
  server-side (separate maintainer-only read, or include only when the viewer is CanMaintain/sysadmin).
  Pairs with the owner-naming lock message (shipped 1.3.0) and the sysadmin-override confirm dialog (above).
  See [[project_maintenance_mode]].
- **Read-only Coach role (view-only entry unless flagged)** *(user 2026-10-27)*. A new role that follows the
  **Administrator** access pattern (school-scoped visibility via `StaffSchoolAccess` — sees the same data an
  Administrator sees for their schools) with ONE difference: on the **data-entry** pages they can **view but
  not edit/save** — every cycle behaves as if **locked (view-only)** for them — UNLESS granted an
  **edit-override flag**, which un-gates editing. Refines today's stop-gap where a coach is classified as
  `Administrator` via a role override (which currently gives them FULL entry edit); this gives coaches their
  own role with read-only entry by default. **Impl hooks:** add the role to the AccessLevel/override taxonomy
  (new value, e.g. `Coach`, Administrator-equivalent for RLS/StaffSchoolAccess — see [[project_assessment_platform]]
  RLS taxonomy and the "Coaches role" open decision there); the entry UI's edit/save gate must force view-only
  for the role regardless of cycle state (the entry grids already compute a per-cycle locked/view-only state —
  extend that so `Coach` + no edit-flag = locked); add the per-user edit-override flag (a capability on
  `StaffAppAccess`, same shape as `CanMaintain`, or a flag on the override) that lifts the lock. Pairs with the
  role-override work shipped in 1.3.0 ([[project_assessment_language_tracks]] has the course-based WRITE-scoping
  precedent for gating entry).
- ~~Roll-up tree "Collapse all" button~~ — **CODED 2026-11-10** into the 1.4.0 candidate (close-only as
  specified; commit 0811582). Ships with the reports hotfix.
- **Design/aesthetics pass + WCAG 2.1 AA sweep** *(user: "post 1.0")*. Flag a11y in passing, collect
  here, do NOT stop to fix. Math cell marks are already AA-compliant. **Reusable technique:** SC 1.4.11
  wants 3:1 against ADJACENT colours, not the page — a fill too light to pass alone works if a
  sufficient-contrast EDGE **≥ 1px rendered** defines the shape (a sub-pixel stroke antialiases away and
  the fill silently carries the ratio; a checker can't see this). Chasing the fill colour can't work.
- **Dark mode** *(user: "1.2 or later")*. Full scoping in [[project_dark_mode]].
- **Persistent per-USER preferences (server-side)** *(user 2026-10-20: "QoL for down the road; per-browser is fine for now")*.
  UI prefs (COIL/IOLC trait order via `useTraitOrder` → localStorage key `writingTraitOrder`; later others)
  are per-BROWSER today. Move to a per-UPN store so a preference follows the user across devices. Would need
  a small prefs table + read/write path (SP-scoped) + a load on sign-in. Low priority; don't build until asked.

---

# Lowest priority — someday, low value (user 2026-09-22)

**Group-picker latency cluster — TIED, tackle together (user 2026-09-22).** Both feed the same "picker
feels slow" symptom, so measure the picker COLD vs WARM before touching either — don't do one blind.
- **`tvf_TeacherGroups`** (~1.5s) — the STEADY-STATE query cost; profiling/design pass, can't go
  section-first (enumerating sections IS its job). Can't self-profile (no SQL execution here) →
  iterative measure-and-rework, no firm estimate. Reconfirm it's still felt (picker streams since 0.5.1).
- **Connection pre-warm / `pool.min`** — the COLD-start cost (first query after idle); holding
  connections open. Deferred pending the user's call on keeping connections open. Pre-warming may mask
  part of the picker's cold cost, so pair it with the tvf_TeacherGroups measurement. Measurements in
  [[project_perf_qol_backlog]].

**Cleanup (unrelated):**
- **8 remaining `J020` refs in `tvf_TeacherRoster`** — dead fallback branches (scale/IPP-family for
  UNSCOPED cycles, retired by the canonical 8-instance model). ~1 hr edit, but gate on a "no unscoped
  cycles remain" check + a dev verify (security TVF). Tidiness only.

