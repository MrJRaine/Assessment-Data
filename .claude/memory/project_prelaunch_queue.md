---
name: project_prelaunch_queue
description: Release-triaged work queue. LIVE through 0.6.0 (2026-09-22). Forward triage 1.0 → post-launch → post-1.0 set by the user 2026-09-18 — respect those calls; do not re-litigate or re-order. Keep current per feedback_keep_memories_current.
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-22T21:07:21.574Z
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

# OPEN — near-term (not release-bound)

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
- **Split-grade math pacing** — a split-grade class runs different pacing per grade, so the task set
  must follow that grade's pacing, not just grade+month. Revisit `tvf_TeacherRosterMath` selection.
  Design in [[project_math_split_pacing_model]]; confirm against what the math team actually delivers.
- **Linked math tasks carry mastery forward** — a task LINKED to a later one should start the later
  cycle already Meeting. Needs a task-link model in `DimMathTask` + carry-forward logic.

---

# Post-1.0

- **Design/aesthetics pass + WCAG 2.1 AA sweep** *(user: "post 1.0")*. Flag a11y in passing, collect
  here, do NOT stop to fix. Math cell marks are already AA-compliant. **Reusable technique:** SC 1.4.11
  wants 3:1 against ADJACENT colours, not the page — a fill too light to pass alone works if a
  sufficient-contrast EDGE **≥ 1px rendered** defines the shape (a sub-pixel stroke antialiases away and
  the fill silently carries the ratio; a checker can't see this). Chasing the fill colour can't work.
- **Dark mode** *(user: "1.2 or later")*. Full scoping in [[project_dark_mode]].

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

