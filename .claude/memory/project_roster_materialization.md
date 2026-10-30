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

**FIX — SECTION-STABLE membership, LIVE 2026-10-13 (server-side patch under 1.2.0):** closed Short-Cycle
rosters collapsed to ~1 student when a section re-versioned. The rebuild resolved each window's section
to the ONE DimSection version in force on the window EndDate, then joined enrolment on THAT version's
SectionKey. DimSection churns (EnrollmentCount/teacher changes → new SectionKey); live enrolment is
re-pointed to the CURRENT SectionKey, so a CLOSED window (resolved at its past EndDate) matched a dead
key → roster ~0 (CHES SC1: ELA6/ILA3 showed 1 of 18/22). SAME mutable-surrogate theme as the
StudentNumber fact fix ([[project_assessment_fact_scd_policy]]) and the old [[project_section_undercapture_bug]].
**Now:** sections resolve to their CURRENT version; enrolment matches by the STABLE `SectionID` across
ALL section versions (window-date overlap unchanged); student resolves to CURRENT by `StudentNumber`;
DISTINCT collapses dups. **NO ActiveFlag filter** — a student enrolled during the window but since
departed STAYS on that window's roster (teacher may have paper results to enter — user decision). Side
effect: open cycles also recovered a few students stranded on old keys (rosters tick up 1–3). Deploy:
`sql/deploy/live_1.2.0/deploy_rostermembership_section_stable_2026-10-13.sql` (redeploy proc + rebuild).
Validated as a read-only preview (`diag_ches_fixed_membership_preview_*`) against CHES live BEFORE the change.
**STILL OPEN (teacher axis):** step 2's teacher fast-table + the TVFs' teacher-access predicate still use
`WindowEffectiveDate` (= EndDate for closed windows) against FactSectionTeachers — so a TEACHER reassigned
after a cycle closed can still be stranded off that cycle's card. Not yet fixed; same bug shape on the
teacher dimension.

**FOLLOW-ON FIX — enrollment close dates, LIVE 2026-10-30 (server-side patch under 1.3.0):** the
ActiveFlag-blind date overlap above is only correct if `FactEnrollment.EndDate` is the student's ACTUAL
departure — but PS fills `CC.DateLeft` with the SCHEDULED exit (term/year end), and `usp_MergeEnrollment`
step 5's defensive close (row vanished from the export — transfers out, mid-year drops) flipped ActiveFlag
WITHOUT touching EndDate. Result: departed-in-cycle-1 students bled into every later cycle through June.
Fixed: step 5 now CAPS `EndDate = MIN(existing, @EffectiveDate)` (a real earlier PS exit date is kept);
one-time repair `sql/scripts/fix_enrollment_close_dates_2026-10-30.sql` set EndDate = Atlantic date of
`LastUpdated` on `ActiveFlag=0 AND (EndDate IS NULL OR EndDate > that date)` — the guard protects closed
rows still in PS's rolling export, whose LastUpdated keeps getting touched (3258 live rows repaired,
closes 2026-09-09→10-26) + membership rebuild. Paper-backfill keep is now correctly BOUNDED to the cycle
the student left during. Residual edge: the repaired/stamped date is when the closing INGEST ran, not the
true last-attended day — a close that straddles a cycle boundary can legitimately reach one cycle further.
Diagnostic: `sql/scripts/diag_departed_student_cycle_bleed_2026-10-30.sql`.

**Perf state (dev warm, 20-student):** original ~2050ms → base+dead-cut ~1461ms → teacher fast-path
~1157ms; Fabric per-query floor ≈ ~1015ms (the untouched groups TVF). LIVE app warm ~2.3s = ~1.4s SQL
+ ~0.9s connection/render. Remaining levers (both bigger, deferred): pre-warm/min-connections for the
~0.9s, and the ~1s Fabric floor (an F8 capacity question — see [[project_capacity_rightsizing_intent]]).

**D PARKED:** `tvf_TeacherRosterOwn` (teacher fast-path, no access-check) is DEPLOYED but INERT — the
app still calls the base `tvf_TeacherRoster`. Wiring the app to route Taught cards → `Own` by group
Scope (in `data.ts`) is D; measured only ~160ms (near the floor), so it was parked as low-value.

Related: [[project_webapp_fabric_connection]], [[project_perf_qol_backlog]], [[feedback_git_workflow]].
