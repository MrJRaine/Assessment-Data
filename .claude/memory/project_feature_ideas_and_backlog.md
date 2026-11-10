---
name: project_feature_ideas_and_backlog
description: Release-triaged work queue. LIVE through 0.6.0 (2026-09-22). Forward triage 1.0 → post-launch → post-1.0 set by the user 2026-09-18 — respect those calls; do not re-litigate or re-order. Keep current per feedback_keep_memories_current.
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-11-10T15:30:03.002Z
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

1. **Reports hotfix (1.3.1)** — list-view charts follow filter chips (coded 10-30), RWM score colours
   → standard DimAchievementLevel palette + roll-up tree "Collapse all" (both coded 2026-11-10).
   Awaiting user test on imp/awdev → bump → prod swap + release ritual. Math band palette alignment
   REJECTED 2026-11-10: the math-band colours are the math team's specific request — a deliberate
   deviation; see [[stakeholder-preferences]]. Do not re-propose.
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

- **FIX, NEXT VERSION WE WORK ON (user 2026-11-04): secondary data-entry splits a section into
  per-program lists.** On the data-entry page, a SECONDARY (HS) section's students are divided into
  separate lists by their program; they should be ONE list per section on the page. User wants this
  bundled into the next version worked on (1.3.1 candidate, alongside the pending charts fix).
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
- ~~Roll-up tree "Collapse all" button~~ — **CODED 2026-11-10** into the 1.3.1 candidate (close-only as
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

