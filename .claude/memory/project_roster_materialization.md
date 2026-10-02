---
name: project_roster_materialization
description: Roster load perf pass — materialized membership tables + card-metadata pass-through + dead-column cut. LIVE in 0.6.2 (2026-09-23). Two tables must stay in LOCKSTEP with the roster TVFs; D (fast-path routing) parked.
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-23T20:35:06.665Z
---

**Shipped LIVE 2026-09-23 as part of 0.6.2** (tag `v0.6.2`). Took the warm roster load from
~3.47s → ~2.3s app-observed. Origin: `diag_roster_timing.sql` proved the ~2s roster TVF was
QUERY-bound (not connection), and a roster page also fired a redundant ~1s `getTeacherGroups`.

**What was built (three independent wins):**
1. **Materialized membership.** The ingest-stable half of the roster (which students sit in which
   subject-mapped section per window + static attrs) is pre-joined into two tables:
   - `SectionRosterMembership` — SECTION-keyed source of truth (viewer-INDEPENDENT, so oversight
     roles can't explode it region-wide). Carries `SectionLanguage` (DimCourseAssessment.Language) so
     WRITING filters the EN/FR track by the SECTION's course language, NOT the student's program.
   - `TeacherRosterMembership` — Taught-scope projection = base ⨝ FactSectionTeachers (bounded per
     teacher, join-free). For the teacher fast path.
   Rebuilt every ingest by `usp_RebuildRosterMembership` (wired into `usp_RunFullIngestCycle` AFTER the
   DQ gate). The four roster TVFs (`tvf_TeacherRoster` / `...Own` / `...Writing` / `...Math`) read the
   base + a LIVE access predicate (FactSectionTeachers / StaffSchoolAccess). Volatile enrichment
   (levels/scores/tasks, IPP, benchmark, starting point) stays live. No new staleness — membership was
   already ingest-cadence.
2. **Card-metadata pass-through.** `GroupCards.cardHref` puts the group's `windowIds`/label/language/
   school on the link; `page.tsx` reads `searchParams` and SKIPS `getTeacherGroups` (~1s/open), falling
   back for direct links / combined rosters. Safe — the roster TVF still authorizes by section.
3. **Dropped dead server work.** The reading/writing grids recompute the delta + achievement band
   CLIENT-side (must update live as a level is picked), so the `DimAchievementLevel` join +
   `ExistingDelta`/`Achievement*` columns were removed from the roster TVFs and `data.ts`.

**⚠ LOCKSTEP COUPLING (the maintenance risk):** `usp_RebuildRosterMembership` DUPLICATES the roster
TVFs' membership logic (grade band, program scope, section→subject mapping, language). If anyone
changes how rosters filter students, they MUST update the rebuild proc too or rosters silently
diverge. Both live in `sql/security/` + `sql/procedures/`.

**Perf state (dev warm, 20-student):** original ~2050ms → base+dead-cut ~1461ms → teacher fast-path
~1157ms; Fabric per-query floor ≈ ~1015ms (the untouched groups TVF). LIVE app warm ~2.3s = ~1.4s SQL
+ ~0.9s connection/render. Remaining levers (both bigger, deferred): pre-warm/min-connections for the
~0.9s, and the ~1s Fabric floor (an F8 capacity question — see [[project_capacity_rightsizing_intent]]).

**D PARKED:** `tvf_TeacherRosterOwn` (teacher fast-path, no access-check) is DEPLOYED but INERT — the
app still calls the base `tvf_TeacherRoster`. Wiring the app to route Taught cards → `Own` by group
Scope (in `data.ts`) is D; measured only ~160ms (near the floor), so it was parked as low-value.

Related: [[project_webapp_fabric_connection]], [[project_perf_qol_backlog]], [[feedback_git_workflow]].
