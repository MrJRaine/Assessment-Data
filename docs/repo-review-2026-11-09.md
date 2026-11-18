# Repository Review — 2026-11-09

> Thought-exercise findings document. Produced by a full read-only scan of the repository
> (725 tracked files at commit `0b52e72`). **No existing file was modified during this review;
> this document is the only artifact.** Nothing here is a decision — every recommendation is
> a proposal awaiting the project lead's call.
>
> Scope decisions set by the user before the run:
> - Task 2 (flag→state) covers BOTH the warehouse data model and the web-app code.
> - Task 3 (code review) covers the ACTIVE surface: `webapp/src` + deployed SQL objects +
>   live tooling; one-off diag/repair scripts and legacy Power Apps YAML are classified in
>   Task 1 but not line-reviewed. Variable inventory = shared surface (params, exports,
>   module state, props, cross-file names), not every local.
> - Historical semver deploy bundles are MUST-KEEP (dev catch-up mechanism + audit trail).

## Contents

1. [Task 1 — Repository slim-down triage](#task-1)
2. [Task 2 — Flag-based → state-based transition plan](#task-2)
3. [Task 3 — Per-file code review, congruence analysis, streamlining plan](#task-3)

*(Scan complete 2026-11-09: all three sections final. Nothing in this document has been acted on —
every recommendation awaits a decision.)*

---

<a id="task-1"></a>
# Task 1 — Repository slim-down triage

Ground rules used: "removable" means *delete from the working tree* — git history (and the vX.Y.Z
tags) preserves every byte, so nothing here is unrecoverable. "Without an effect on the current
app" was tested against the active chain: webapp/src → lib/db → @UPN TVFs/procs → tables →
ingest/membership procs → staging ← loaders ← OneLake, plus the operational docs and the Claude
working apparatus (.claude/, .github mirrors). A file is a candidate only when nothing in that
chain reads it and it no longer drives a decision.

## Group A — Superseded Power Apps era (remove first: zero coupling, biggest safe win, ~70 files)

**Why removable:** the live product is the web app (2026-09-22 decision); the canvas app is
maker-only reference, unopened since, and `pac` tooling can always rebuild from git history.
Nothing in the active chain references any of it.
- `powerapps/**` — 41 files: `sources/Src/*.pa.yaml` (10), `from-claude-design/**` incl. the
  handoff prototype (23), `Student Data Staff Portal.msapp` + `waypoints/*.msapp` + `.msapr`
  (binaries — the heaviest blobs in the repo), `bootstrap-checklist.md`, `README.md`.
- `docs/powerapps-build/**` — 29 files (the 7 build guides + 22 `chunks/` duplicates of the same
  content, which were only ever Copilot-grounding splits), `docs/powerapps-screen-design.md`.
- Caveat, not a blocker: keep ONE line in the implementation plan or CHANGELOG noting "canvas-app
  sources removed at <commit>; recover via git" so the maker-only fallback stays findable.

## Group B1 — Dated one-off SQL scripts for RESOLVED incidents (~85 files)

**Why removable:** each was written for a specific dated diagnosis/repair, was run, and its
outcome is recorded in memory/CHANGELOG/audit tables. They never run again by design; several
embed assumptions that are already stale (pre-section-stable logic, old column lists), so keeping
them invites someone re-running an outdated script against live.
- `sql/scripts/diag_*` with date suffixes or tied to closed incidents (~55 — the 2026-10-13/14/15/16
  duplicate/fanout/ghost series, diag_math_report_live, diag_report_objects_live,
  diag_staff_write_rule_trace, diag_sub_coteacher_sections, the SRHS specialist set, etc.).
- One-time repairs already applied to live+dev: `fix_dimstaff_dup_current_2026-10-30.sql`,
  `fix_enrollment_close_dates_2026-10-30.sql`, `fix_dimstaff_stacked_markers.sql`,
  `fix_math_cycle_months_and_task_miscoding*.sql`, `fix_math_task_month_10_to_9.sql`,
  `fix_blank_programcode.sql`, `fix_DimSection_coursename_mojibake.sql`, `fix_dev_*` (3),
  `remediate_*` (2), `relink_stranded_assessment_studentkeys.sql`, `migrate_mislocated_immersion_reading.sql`,
  `cleanup_staff_email_ghosts_2026-10-16.sql`, `backfill_*` (3), `reconcile_*` (2),
  `export_immersion_students_pg1g2_2026-10-16.sql`.
- Superseded deploy helpers: `sql/scripts/deploy_groupkey_tvfs*.sql`, `deploy_analyst_rls_scoping.sql`,
  `deploy_step14_data_quality.sql`, `deploy_timezone_audit.sql`, `deploy_load_staging_procs.sql`,
  `deploy_dev_cutover_loaders.sql`, `deploy_dev_loaders_workspace_identity.sql` (their content
  lives on in the canonical object files + semver bundles); `scripts/generate_live_deploy_0.7.0.sh`,
  `generate_live_deploy_1.0.0.sh` (version-pinned copies; the generic `generate_live_deploy.sh` stays).
- **Explicitly NOT in this group (reusable by design):** the hand-off/census/ops set —
  `list_sections_teacher_not_in_staff_export.sql`, `count_sections_inactive_primary_trap.sql`,
  `count_specialist_entries_by_school.sql`, `list_srhs_specialist_access_staff.sql`,
  `list_teacher_hs_writing_submissions.sql`, `audit_writing_entries_nonsection_staff_srhs.sql`,
  `audit_latest_ingest_today.sql`, `audit_srhs_entries_by_specialists.sql`, `pull_student_full_record.sql`,
  `diag_last_dq_run.sql` / `diag_dq_latest_violations.sql` / `diag_dq_latest_run_dev.sql`,
  `diag_live_deployed_proc_versions.sql`, `diag_cycles_live_vs_dev.sql`, `diag_ingest_*` (ops),
  `reset_*` (4 — operational reset recipes), `rollforward_enrollment_dev.sql` (yearly),
  `run_math_task_ingest_dev/live.sql`, `set_cycle_grade_ranges_by_subject.sql`,
  `reconcile_cycle_instances.sql` (cycle ops), `verify_*` (3), `dev_build_cycles_to_match_live*`,
  the dev-fixture seeds (`seed_demo_results_dev`, `seed_dual_language_sentinel_dev`,
  `seed_mover_sentinel_dev` — the attribution test still PENDS on this one, `seed_split_homeroom_dev`,
  `seed_primary_homeroom_dev`, `seed_dev_resource_teacher`, `classroom_teacher_grades_dev`,
  `who_sees_open_cycle_dev`, `enrollment_currency_dev`, `staff_roster_linkage_dev`,
  `test_slash_homeroom_dev`), and every reference-data seed (next group's must-keeps).

## Group C — Historical / abandoned-path docs and data (~30 files; remove after a skim-confirm)

**Why removable:** they document paths the project explicitly abandoned or phases that completed;
the decisions they record are distilled into memory and CLAUDE.md.
- Abandoned 3a/SharePoint pivot: `docs/sharepoint-entry-pivot.md`, `docs/sharepoint-site-setup.md`,
  `docs/it-request-entra-bridge.md` (header already says DO NOT SEND).
- Completed IT requests: `docs/it-request-login-redirect-uris.md` (resolved),
  `docs/it-request-restore-sp-onelake.md` (closed, not pursuing), `docs/it-request-entra-webapp-dev.md`
  (provisioned), `docs/brief-server-hosting-requirements.md` (hosting live since 08-27).
- Parked/complete analyses: `docs/LOADTEST_HANDOFF.md` (apparatus parked on the loadtest branch —
  the branch keeps it), `docs/backlog-1.2.0.md` (superseded by the memory backlog),
  `docs/release-signoff-1.2.0.md`, `docs/surrogate-key-stranding-sweep.md` (fix shipped 10-13),
  `docs/excel_template_structure.md` + `scripts/dump_excel_structure.ps1` +
  `docs/ABR - 25-26 Combined Reading and Writing.xlsm` (blank predecessor-workbook template, per
  the user 2026-11-09 — kept only as the structural reference the platform replaced).
- Superseded versions: `docs/user-guides/v0.6.0/**` (11 incl. _source-images — current guides live
  at `docs/user-guides/*.docx`), `data/mathtasks/baseline-2026-09/*` (4 — superseded by
  `MathTasks_2026-27.csv`), `data/imports/_generate_test_dummies.ps1` IF
  `_generate_ingest_testset.ps1` fully replaced it (one-line confirm needed),
  `scripts/smoke_test_onelake.ps1` (one-off connectivity proof).
- `sql/deploy/deploy_all_dev.sql` — **stale and actively misleading** (frozen at June; the semver
  bundles are the real catch-up mechanism). Remove or stamp a DO-NOT-USE header; I'd remove.
- `sql/scripts/01_CreateSchema.sql` — superseded by the per-table DDL files; same misleading-staleness
  argument. `sql/scripts/dev_catchup_1.1.0_2026-10-06.md` — completed recovery note.
- Borderline, your call: `docs/semantic-model-setup.md` (Power BI phase is deferred, not abandoned —
  I'd keep), `docs/powerschool-field-mapping.md` / `powerschool-report-specifications.md` (ACTIVE
  export contracts — keep).

## Group B2 — Applied schema migrations (~30 files; remove LAST among scripts, with verification)

**Why removable (with care):** every `sql/scripts/migrate_*` has been applied to live and dev, and
the end-state is captured in the canonical table DDL + the semver bundles. They differ from B1 in
one way: they are the only in-repo record of the ALTER path between schema versions, so before
deleting, verify each migration's end state is truly reflected in the canonical DDL file (spot
check: it is for every one I compared — e.g. GroupKey, AssessmentLanguage, traits-varchar). The
semver bundles + git history then carry the provenance. ~28 `migrate_*` files plus
`load_prior_year_baseline.sql` / `seed_prior_year_baseline_dev.sql` once the baseline becomes
facts-only (Sept 2027 — keep until then), and `migrate_0.7.0_grace_and_overrides.sql` et al.

## Group D — Superseded-but-DEPLOYED SQL surface (do NOT delete files alone; needs a decommission bundle)

**Why different:** these source files mirror objects that still exist in both warehouses. Deleting
the file without dropping the object creates silent drift (an undocumented live object); dropping
the object is a warehouse change that is yours to schedule. Propose: one idempotent
`decommission_powerapps_surface.sql` bundle (DROP the 11 legacy views + bridge views +
usp_InsertSubmissionAudit + usp_GenerateMonthlyWindows), run dev → live, delete the files in the
same commit, note in CHANGELOG internal log.
- `sql/security/vw_UserAssessmentWindows|vw_TeacherGroups|vw_TeacherRoster|vw_StudentCohort|`
  `vw_StudentCohortTeachers|vw_StudentIPP|vw_StudentAssessmentHistory|vw_TeacherStudents|`
  `vw_SchoolStudents|vw_RegionalData|vw_DimReadingScale`, `bridge_views.sql` (never granted,
  explicitly dangerous-by-design — first in line), `usp_InsertSubmissionAudit`,
  `usp_GenerateMonthlyWindows` (retired by /cycles). Also the code-level leftovers that ride along:
  `@SkipCoTeachers` params (both procs' headers already say "remove once 1.1.0 is live" — it is),
  and `webapp/src/components/ui.tsx`'s unused `ScaffoldNote`/`Placeholder`.
- NOT in this group: `vw_StudentReadingStartingPoint` (read by active TVFs) and
  `usp_DeleteReadingAssessment` (legacy caller, but it's the only delete path and C-9 proposes
  extending, not dropping, it).

## Group E — MUST KEEP (the load-bearing set, with why)

- **`webapp/**`** — the product. Includes Dockerfile/load-secrets/compose (the deploy artifact) and
  public/ assets.
- **`sql/dimensions|facts|staging|procedures|security` (active objects)** — the source of truth for
  every deployed warehouse object; the only place the next change starts from.
- **`sql/deploy/live_*/**` + `_grants_0.7.0.sql`** — your ruling: the dev-catch-up mechanism after
  any wipe/revert and the deploy audit trail. All semver bundles stay.
- **Reference-data seeds** (`sql/scripts/seed_DimGrade|DimSchool*|DimReadingScale*|DimReadingBenchmark*|`
  `DimAchievementLevel|DimMathComprehensionBand|DimCourseAssessment*|StaffAppAccess`, `repopulate_DimCalendar`,
  `add_Abbreviation_to_DimSchool`) — the only way to rebuild a warehouse from zero; DimProgram/DimRole/
  DimGender/DimTerm seed inside their DDL files.
- **Operational scripts/ + docs** — `docs/implementation-plan.md` (session-start anchor),
  `ingest-runbook.md`, `prod-container-swap.md`, `dev-environment.md`, `export-procedures.md`,
  `course-assessment-mapping.md`, `powerschool-*.md` (export contracts), `v1.3.0-testing-plan.md`
  (1.3.x still in flight), `docs/reference/*.csv` (benchmark sources), current `docs/user-guides/*.docx`,
  `scripts/generate_live_deploy.sh`, `redeploy-dev.sh`, `build_user_guides.ps1`, `scripts/mathtasks/*`
  (the SCoR-month conversion tooling — the miscoding fix lives there), `data/imports/*` (generators +
  README), `data/mathtasks/MathTasks_2026-27.csv` + README.
- **`.claude/**` and `.github/**`** — memory (travels with git by design), skills + their .github
  mirrors (kept in lockstep per working agreement), hooks/settings (the warehouse-execution guard),
  `power-bi/dax_rls_roles.dax` (deployed semantic-model RLS source), `CLAUDE.md`, `CHANGELOG.md`,
  `.gitignore`.

## Elimination order (the triage)

1. **Group A** (Power Apps era) — ~70 files incl. all repo binaries; no verification needed.
2. **Group B1** (dated one-off scripts) — ~85 files; skim my not-removable list once, then sweep.
3. **Group C** (historical docs/data) — ~30 files; two one-line confirms flagged inline.
4. **Group B2** (applied migrations) — ~30 files after the DDL-reflects-end-state verification.
5. **Group D** (deployed legacy surface) — whenever you want to schedule the decommission bundle;
   the files wait for the objects.

Net effect: roughly **215 of 725 tracked files** (and nearly all binary weight) removed before
touching anything that needs a decision, leaving the repo at approximately the active chain +
deploy history + working apparatus.

---

<a id="task-2"></a>
# Task 2 — Flag-based → state-based transition plan

The app's lifecycle logic is mostly encoded in **boolean flags whose combinations imply states**
(IsCurrent × ActiveFlag × EffectiveEndDate patterns; stage × locked × override × lockedAfterSave in
the grids). The combinations are the real model; the flags are its compressed encoding — and every
recent lifecycle bug (stacked markers, dup current rows, the enrollment EndDate bleed, the
on-leave/long-term-sub section trap) happened in the gap between a combination and the state it was
supposed to mean. This section inventories every flag, maps each into an explicit state, lists the
valid states, and sequences the transition.

## 2.1 Flag inventory — warehouse

| Flag | Where | What it signifies today |
|---|---|---|
| `IsCurrent` (BIT) | DimStudent/DimStaff/DimSection, FactStaffAssignment, FactSectionTeachers, FactStudentIPP/Adaptation | 1 = the business key's live version; 0 = historical. Paired invariants with `EffectiveEndDate` (DQ Rules A–D). |
| `ActiveFlag` (BIT, derived) | DimStaff | Present in the staff export (1) vs absent (0). Absence is MULTI-CAUSE (leave, retired, left region, role change) but stores as one bit. The `IsCurrent=1 ∧ ActiveFlag=0` combination is the "deactivation marker" pseudo-state that required the 4b/4c/4c-prime/4c-prime2 algebra and caused the 10-30 dup-current incident and the 11-04 long-term-sub trap. |
| `ActiveFlag` (BIT) | FactEnrollment | Enrollment episode still open. Encodes three real situations with help from EndDate: open, scheduled exit (future EndDate), actually exited — the missing distinction behind the 10-30 cycle-bleed fix. |
| `EnrollStatus` (INT) | DimStudent | Already an enum (0 Active / −1 Pre-Enrolled / 2 Inactive / 3 Graduated) — the model Task 2 wants, inherited from PS. Absent-from-export closes are close-only because the absent state is unknowable. |
| `IPP`, `Adap` (BIT NULL) | DimStudent | PS tri-state: Y/N/unknown. |
| `IsIPP` / `HasAdaptation` (BIT NULL) | FactStudentIPP / FactStudentAdaptation | A real THREE-state gate dressed as a nullable bit: NULL = Unresolved (blocks achievement display, prompts confirm), 1 = Confirmed, 0 = Not. |
| `ActiveFlag` (BIT) | DimAssessmentWindow, DimShortCycle, StaffRoleOverride, WritingTraitExclusion, reference dims (DimRole, DimReadingScale, DimAchievementLevel, DimMathTask, DimCourseAssessment, DimSchool…) | Soft-retire / config-enabled. Genuine binary; fine as flags. |
| Capability bits | StaffAppAccess (IsSysAdmin, CanManageCycles, CanRunIngest, CanOverrideMath, CanOverrideLiteracy, CanMaintain) | Independent capabilities. Genuinely parallel booleans — NOT a state machine; keep. |
| `IsDistrictLevel` (BIT, derived) | DimStaff | '0' present in CanChangeSchool. Derived convenience; fine. |
| `MaintenanceAt` NULL-ness | AppMaintenance | Window exists/doesn't. The real state machine lives client-side (stage derivation). |
| Trait sentinels `'-'`, `'SCR'`, NULL, '1'–'4' | FactAssessmentWriting trait columns | Value-level states on a VARCHAR: scored / excluded-by-config / scribed / never recorded. Already explicit; keep (documented contract). |
| Status enums | FactSubmissionAudit (Accepted/AcceptedWithWarnings/Rejected), IngestRunLog (Started/Loaded/Completed/Failed), FactDataQualityAudit categories | Already state-based; the pattern to emulate. |
| Derived `WindowStatus` | tvf_UserAssessmentWindows, the 3 upsert procs (×2 each: status + grace-lock), usp_DeleteReadingAssessment, data.ts getShortCycles | `Upcoming / Open / ClosesToday / Closed / Locked` derived from dates + GraceHours. A real 5-state lifecycle — but the derivation is REPEATED in at least seven places (five SQL, one TS, plus vw_ legacy), each a drift risk. |

## 2.2 Flag inventory — web app

| Flag | Where | Signifies |
|---|---|---|
| `MaintenanceStage` | MaintenanceProvider | ALREADY a 6-state FSM (`none→warn→lockAfterSave→fullLock→autoSave→down`) — the house style to copy. |
| `lockedAfterSave` (+ sessionStorage), `inputsLocked`, `autoSavedRef` | useEntryLock | Sticky per-window lock substates layered on MaintenanceStage. |
| `locked`, `canOverride`, `override` (one-shot), `editable`/`ro` | the 3 entry grids + roster page | Grace-lock editability: locked cycle, override capability, override engaged-until-next-save. |
| `pending`/`saving`/`busy` (useTransition), `result` (+ math's `unconfirmed`) | all grids/managers | Save lifecycle: idle → saving → saved(n, errors) → (math only) unconfirmed. |
| `dirty` (derived: sel≠baseline / marks≠committed / pending map non-empty), `evidenceManual` | grids | Unsaved-work detection + the manual New-Data override. |
| `ippSel` staged map, `confirmedIpp` session map, `needsConfirm` (derived from ippNeedsConfirmation) | reading/writing grids | The client half of the IPP gate's Unresolved→Confirmed transition. |
| `Mark` = '1'/'0'/'clear'/'ipp' | math grid | Already a 4-state cell enum. |
| `BlockState` = loading/done/error | both roll-up trees | Already a mini fetch FSM. |
| `RowState.status` = idle/uploading/UploadResult | IngestPanel | Upload FSM. |
| `authed`, `capsError`, `ranPostLogin`, retry counters | AppShell/PostLoginRefresh | First-render identity races. |
| UI toggles (expanded, pickerOpen, editMode, picking, schoolsOpen, collapsed sets, addExternal, completeOnly, assessableOnly, blankMode, traitMode, axis, view, summarizeBy, lang, measureMode) | everywhere | Genuine independent booleans/enums of view preference — NOT lifecycle; keep as-is. |

## 2.3 Proposed state model (the valid-states list)

**S1. StaffStatus** (replaces DimStaff.ActiveFlag semantics; the on-leave motivation):
`Active` · `OnLeave` (admin-asserted: absent from export but expected back — sections may tolerate
an OnLeave primary) · `Departed` (absent, no assertion — today's ActiveFlag=0) ·
`PlaceholderIdentity` (the Tech-Services/Maintenance audit-ID rows, today inferable only by
AccessLevel NULL + title text). The merge can only ever derive Active/Departed on its own;
`OnLeave` requires a small admin surface (a Role-Overrides-style list) — that is the price of the
distinction, and the reason the section gate currently can't tell a sub-covered leave from a
departure.

**S2. Row lifecycle state** (per SCD row; replaces the IsCurrent × ActiveFlag × EndDate
combinations): `Current` · `Superseded` (closed by a newer version) · `ClosedMissing` (closed
because absent from import) · `DeactivationMarker` (the current-but-inactive marker) ·
`RevivedSameDay` (transitional, collapses to Current). Making the marker a named state turns the
4c-prime/-prime2 and usp_SetStaffRoleOverride marker algebra from flag archaeology into explicit
transitions, and DQ Rules A–D become per-state invariants.

**S3. EnrollmentState** (replaces FactEnrollment.ActiveFlag + EndDate interplay):
`Open` · `ScheduledExit` (PS DateLeft in the future) · `Exited` (DateLeft past) ·
`ClosedDefensively` (absent from import — today's Step-5 close, the 10-30 cap). The cap bug was
precisely the Exited/ScheduledExit conflation; the membership rebuild's "keep departed students for
paper backfill" rule becomes a readable predicate on state instead of on date arithmetic.

**S4. SectionLifecycle**: `Current` · `Closed` (year-end/absent) · `ExcludedUnresolvedPrimary`
(staged but failed the teacher gate — today this is pure ABSENCE, which is why the long-term-sub
trap was invisible until a user noticed; persisting the exclusion as a state row or log makes the
census query a SELECT instead of a replay).

**S5. GateState** for IPP/Adaptation (rename of the nullable-BIT tri-state):
`Unresolved` · `Confirmed` · `NotApplicable` — plus the existing Detached (closed row) via S2.
Lowest urgency: the tri-state already works; the win is self-documentation.

**S6. WindowState** (already exists conceptually): `Upcoming` · `Open` · `ClosesToday` · `Closed`
(in grace) · `Locked`. The transition here is not inventing the state — it's centralizing the
derivation in ONE SQL object (e.g. an iTVF `tvf_WindowState` the seven current derivation sites
read) so Status and GraceEndsAt can never disagree between the entry gate and the landing card.

**S7. EntryGridMode** (client; collapses locked/override/stage/lockedAfterSave):
`Editable` · `GraceLocked` · `GraceOverridden` (one-shot) · `MaintenanceLockPending` (lock after
next save) · `MaintenanceLocked` · `ReadOnly`. One selector
`gridMode(stage, lockedAfterSave, graceLocked, overrideEngaged)` shared by the three grids replaces
four booleans threaded per-grid.

**S8. SaveState** (client): `Idle` · `Saving` · `Saved{saved, failed[]}` · `Unconfirmed` — adopt
math's honest fourth state for reading/writing too (their transport failures currently collapse
into per-row errors).

Already-state-based and staying: MaintenanceStage, Mark, BlockState, IngestRunLog/audit statuses,
EnrollStatus, writing trait sentinels, capability bits (parallel booleans by nature).

## 2.4 Transition plan (phased; each phase shippable and reversible)

**Phase 0 — centralize derivations (no schema change).**
(a) SQL: create `tvf_WindowState`; re-base the 5 proc sites + tvf_UserAssessmentWindows on it.
(b) App: add `gridMode()` + a shared `SaveState` type; re-base the three grids. This phase removes
the drift risk that makes later phases scary, and is worth doing even if nothing else proceeds.

**Phase 1 — additive state columns, dual-written.** Fabric constraints shape this: `ALTER TABLE
ADD` must be its own batch, no DEFAULTs, so each column is added nullable, backfilled by script,
then dual-written by the merges alongside the existing flags. Order of value:
1. `FactEnrollment.EnrollmentState` (S3) — smallest surface (one proc writes it), immediate
   diagnostic value.
2. `DimStaff.StaffStatus` (S1) + the OnLeave admin list — unlocks the section-merge tolerance
   decision you parked 2026-11-06 (the gate could admit `OnLeave` primaries without admitting
   true data-gap sections).
3. Row lifecycle (S2) as a `CloseReason` column on the SCD tables (Current stays derivable from
   IsCurrent; what's missing today is WHY a row closed) — written by the merges' close steps,
   which already know the reason at write time.
4. Section exclusions (S4) as an `IngestExclusionLog` (run-keyed rows: what was staged, why it was
   dropped) — this also discharges the standing `feedback_ingest_surface_missing_data` obligation
   for sections/staff/enrollments in one mechanism.

**Phase 2 — flip readers.** TVFs/DQ checks/app reads move from flag combinations to state
predicates (e.g. the DQ Consistency category checks become `StaffStatus='Departed' ⇒ no current
assignments`). The flags remain, now derived FROM the state (one direction of truth).

**Phase 3 — retire redundant flags** (optional endpoint): ActiveFlag columns dropped or kept as
computed conveniences; the BIT-NULL gates renamed (S5) only if ever worth the migration churn.

**Costing honestly:** Phase 0 is days and pays for itself; Phase 1 items 1–2 are each a
focused deploy bundle + merge-proc change; Phase 2 touches many TVFs and should ride an existing
TVF-wide change (like the attribution bundle did); Phase 3 may never be worth it. The client-side
S7/S8 are independent of all SQL phases. Every phase needs your scope sign-off per working
agreement — this document proposes; it does not decide.

## 2.5 How transitions get validated (design Q&A, 2026-11-09)

Question raised: should the composite state be stored as a packed number (one digit per
component) and a proposed transition checked against a list of valid overall values?

Recommendation: keep the validate-before-transition idea, drop the packed encoding.
- **Packed digits re-create the flag problem in another base** — the current pain is states
  encoded in combinations that need a decoder (`IsCurrent ∧ ¬ActiveFlag ∧ EndDate=yesterday` =
  "marker"); a digit-positional number needs the same decoder, caps each component at 10 states,
  renumbers on insertion, and turns readable predicates into arithmetic (`Status/100%10=2` vs
  `StaffStatus='OnLeave'`). Fabric's engine also favors small named columns over packed values.
- **A valid-composite-value list explodes**: components are mostly independent, so the legal
  cross-product is enormous and nearly all "valid". The information lives in the few FORBIDDEN
  combinations — a short invariant list (`Departed ⇒ no current assignments`;
  `Current ⇒ EndDate NULL`), which is exactly what the DQ suite's Consistency/Date categories
  already express.
- **Proposed shape**: (1) one named state column per component; (2) per-component
  `(FromState, ToState)` transition sets enforced as guards at the top of each WRITER — every
  state here is changed only by known writers (merges, upserts, admin procs), and the existing
  51xxx gates / marker-handling blocks are these guards, unnamed; (3) cross-component rules as
  the forbidden-combination list, enforced at write time in-proc and after the fact by the DQ
  gate (Fabric has no CHECK constraints, so writers + the gate are the only enforcement points
  anyway); (4) composite states DERIVED read-side, never stored — WindowStatus and the proposed
  `gridMode()` are the pattern; a concatenated label ('Current|OnLeave') in a diagnostic view
  gives the one-comparable-value convenience without making the packed form the truth.

---

<a id="task-3"></a>
# Task 3 — Code review, congruence, streamlining

## 3.1 Web app — per-file review

### Infrastructure layer (`webapp/src/lib`, `src/auth.ts`, `src/middleware.ts`)

**`src/auth.ts`** — Auth.js (NextAuth v5) configuration for Microsoft Entra ID single-tenant sign-in.
CS shape: a configuration object with three callback hooks forming a claims pipeline — `jwt` lifts
the UPN claim from the Entra profile onto the token (`upn ?? preferred_username ?? email`), `session`
copies it onto the session object, `authorized` is the boolean route gate the middleware evaluates.
Variables: `loginClientId`/`loginClientSecret`/`loginTenantId` (from `AUTH_ENTRA_*` env — the
dedicated LOGIN app registration, deliberately distinct from the warehouse SP's `ENTRA_*`); exports
`handlers, auth, signIn, signOut`. The UPN is the linchpin identity value consumed by `lib/auth.ts`.

**`src/middleware.ts`** — re-exports `auth` as Next middleware over a route `matcher` list
(/enter, /reports, /programming, /ipp, /ingest, /cycles, /admin). Pure declarative gate; no logic.

**`lib/auth.ts`** — one function, `getCurrentUpn()`: session → `user.upn ?? user.email`, throws when
unauthenticated. Every server page/action calls this; the UPN it returns is the single
trust root for all data scoping (becomes `@UPN` / `@CallerUPN` in SQL).

**`lib/db.ts`** — the warehouse connection module. CS shape: lazy singleton pool + retry-once
self-healing wrapper + thin promise adapters.
- `getCredential()` — memoized `ClientSecretCredential` (env `ENTRA_TENANT_ID/CLIENT_ID/CLIENT_SECRET`).
- `getPool()` — lazily-built shared `mssql` pool; token minted via `@azure/identity` and injected as
  `azure-active-directory-access-token` (tedious's own SP flow is rejected by Fabric).
- `runOnPool(fn)` — the self-heal: classifies errors via `isStalePoolError` (code/message allow-list:
  ELOGIN/ESOCKET/… or "authentication failed"/"socket hang up"/…), drops the cached pool and retries
  exactly once with a fresh token. All public helpers run through it.
- Public surface: `query(text, params)` (unscoped reads), `queryAsUser(upn, text, params)` (binds
  `@UPN` first — the RLS-parameterized TVF path), `execProc(name, inputs)` (the ONLY write path —
  wrapper stored procs under ownership chaining).
- Observability: `TIMING` (env `SQL_TIMING=1`) gates per-query console timing; `sqlLabel()` extracts
  the first two distinct object names from the SQL text for the log label.
- Config variables: `SQL_SCOPE` (AAD audience), `poolMax()` (env `FABRIC_POOL_MAX`, default 20 —
  deliberate, see capacity memo), `FABRIC_SQL_SERVER/DATABASE`.

**`lib/data.ts`** (1823 lines — by far the largest app file) — the entire read-side data-access layer.
CS shape: ~30 async fetch functions, each the same four-step pattern: (1) optional cache read,
(2) `queryAsUser`/`query` against ONE named TVF/table, (3) a `rows.map()` that renames
PascalCase SQL columns → camelCase TS fields and normalizes types (`String()` for BIGINT keys,
`Number()`, `toBool`, `toYMD`/`toDateStr`), (4) optional cache write. Exports ~25 interfaces
(TeacherWindow, TeacherGroup, RosterStudent, WritingRosterStudent, CohortStudent, ReadingRollupRow,
ReadingGroupRow, WritingRollupRow, WritingGroupRow, MathRosterRow, MathCohortRow, MathRollupRow,
RWMStudent, RWMHistoryRow, HistoryRow, WritingHistoryRow, IPPRow, ProgrammingRosterRow, ShortCycle,
ShortCycleInstance, CallerCapabilities, StaffAccessRow, StaffRoleOverrideRow, MaintenanceWindow,
AchievementBand, ScaleLevel, StudentNavItem, ReportCycle…).
Key recurring variables: `upn` (identity, threaded everywhere), `cycleGroupId` (nullable cycle scope —
null = "Current"/lifetime), `windowId` (one DimAssessmentWindow instance), `groupKeys[]`
(comma-joinable section keys), `AssessmentLanguage` ('English'|'French'|null), the IPP triple
(`ippStatus: boolean|null`, `ippNeedsConfirmation`, `programFamily`), and the achievement quadruple
(`achievementCode/Name/HexColor/HexColorTint`). Notable asymmetry: `getStudentCohortWriting` reuses
the READING-named interface (`ippStatusReading` carries the WRITING status; reading-only fields
nulled) so `CohortView` renders both — a deliberate shape-pun that trades type honesty for one
shared renderer (congruence finding C-4 below).

**`lib/groupCache.ts` / `lib/identityCache.ts` / `lib/refCache.ts`** — three hand-rolled per-process
TTL caches over `Map<string, {at, value}>` with opportunistic sweep-on-write. Identical mechanics,
three TTL/invalid.policies: groups+windows 30s (invalidated per-user on save, globally on ingest);
identity (AccessLevel + capabilities) 1h (invalidated by ingest; `fresh:true` bypass for
authorization); reference data 6h (deploy-restart clears). Congruence finding C-2: three copies of
the same cache algorithm differing only in key shape and TTL — a single generic `ttlCache(ttl)`
factory would collapse them.

**`lib/errors.ts`** — `UserError` class + `toUserMessage(err)`: passes through intentional messages
(UserError, SQL THROW numbers 51000–51999 — the proc validation convention), genericizes everything
else. The 51xxx range IS the app's cross-layer error contract.

**`lib/keys.ts`** — `SurrogateKey` branded string type + `toKey()` validator (1–20 digit string) +
`isSafeAsNumber()`. Exists because Fabric BIGINT IDENTITY (19 digits) exceeds IEEE-754 safe range.
NOTE: barely imported in practice — most call sites re-validate ad hoc with `/^\d{1,20}$/` regexes
(congruence finding C-7).

**`lib/onelake.ts`** — ADLS Gen2 REST client for the ingest upload. CS shape: tiny HTTP wrapper
(`dfs(method,url,body)` + `ok(res, ...acceptable)`) over create→append→flush, with a
clear-folder-first step. Constants `IMPORT_TOPICS` (5 staging folder names — MUST mirror the
`usp_Load*Staging` COPY INTO paths; a cross-layer string coupling), `STORAGE_SCOPE`, `DFS_HOST`,
`API_VERSION`. Reuses the DB module's credential (same SP, storage audience).

**`lib/writingTraits.ts`** — single source of truth for writing-trait display order (COIL/IOLC).
Pure data module: `META` record, `ORDERS` record, `DEFAULT_TRAIT_ORDER`, `WRITING_TRAIT_KEYS` set,
`traitsInOrder(mode)`. Good example of the congruent pattern the rest should follow.

**`lib/patchNotes.ts`** — `PATCH_NOTES` array (data), `APP_VERSION` (env `NEXT_PUBLIC_APP_VERSION`
fallback newest note), `minorKey()`/`recentNotes()` (show current + previous minor line).

### App chrome (`src/components`)

**`AppShell.tsx`** (server) — resolves UPN + capabilities once per render; two nested try/catch so a
caps failure can't flip the user to signed-out (`authed`, `capsError` booleans → `PostLoginRefresh`).
Composes MaintenanceProvider ▸ header (brand/Nav/AuthArea) ▸ main ▸ VersionFooter.

**`Nav.tsx`** (client) — static `ITEMS` table, capability-filtered (`showCycles/Ingest/Maintenance/
StaffAccess` props), `usePathname` prefix-match for the active state.

**`AuthArea.tsx`** (server) — session → sign-in/sign-out forms with inline server actions.

**`PostLoginRefresh.tsx`** (client) — two bounded `router.refresh()` loops guarded by
sessionStorage flags (`postLoginRefreshed`, `capsRetryCount` ≤ 3) fixing the login-race and
cold-pool caps-read transients. Renders nothing.

**`MaintenanceProvider.tsx`** (client, 18KB) — the most state-machine-like code in the app, and the
model Task 2 proposes generalizing. CS shape: a **time-driven finite state machine**: server time
offset measured at poll; `stageFor(secondsRemaining)` maps a continuous countdown onto 6 ordered
states (`none→warn→lockAfterSave→fullLock→autoSave→down`) with thresholds `WARN_LEAD_MAX`,
`T_LOCK_AFTER_SAVE`, `T_FULL_LOCK`, `T_AUTO_SAVE`; a 1 s local ticker drives transitions between
polls; adaptive poll cadence (visible 8 s / hidden 8 min / stopped when hidden+clean / 30 s retry);
dirty-entry registration via ref-counted `registerUnsavedEntry` (a second context so dirty flips
don't re-render state consumers). Variables: `windowRef {atMs, message, offsetMs}`,
`dirtyEntryCountRef`, `rescheduleRef`, `state: MaintenanceState`, LOTO `clearError`. Renders banner +
the down overlay (route-exempting /ingest + /admin/maintenance).

**`useEntryLock.ts`** (client hook) — derives `inputsLocked` from the maintenance stage plus a sticky
`lockedAfterSave` boolean persisted in sessionStorage keyed by the window's T (`maintLockedAfterSave`);
one-shot T-1 auto-save via `autoSavedRef`; beforeunload guard while `dirty`; registers dirty state
with the provider. Consumed identically by all three entry grids.

**`entryDraft.ts`** — localStorage draft persistence for unsaved grid edits: `draftKey(subject,
windowId, groupKey)` namespacing, `readDraft` (TTL 90 min + reconcile against current roster keys +
purge), `writeDraft` (empty map clears), `clearDraft`. Stores only surrogate keys + scores (privacy).
All storage access try/catch-wrapped (private-mode safe).

**`GroupCards.tsx`** (client, 17.7KB) — the shared choose-a-group picker. Taught/Oversight split;
two organizing modes (`lens` = Homeroom/Section/Grade toggle for Programming, `course` = language-
headed course sections for Data Entry); multi-select within one language block (comma-joined keys in
the URL); sessionStorage-persisted oversight filters (`oversightGroupFilters`: lens/grades/schools)
with restore-only-if-still-valid logic; card hrefs carry group metadata (w/label/lang/school) so the
roster page can skip a ~1s TVF re-resolve (the "fast path" — authorization unaffected, TVF re-checks).
Local duplicate: `GRADE_ORDER` map + `gradeLabel` (see C-1).

**`ui.tsx`** — shared primitives: PageHeader, ScaffoldNote (legacy), Placeholder (legacy), EmptyState,
ErrorNote (genericizes + server-logs), Loading, CardLink (prefetch={false} policy + LinkPending).

**`LinkPending.tsx`** — `useLinkStatus()` spinner inside CardLink (buffering-immune click feedback).
**`ToggleLink.tsx`** — `router.push` + `useTransition` anchor for report toggles (same problem class
as LinkPending but a different mechanism, chosen after a useLinkStatus regression; see C-6).
**`TraitOrderToggle.tsx`** — `useTraitOrder()` hook (localStorage `writingTraitOrder`) + segmented
control. **`VersionFooter.tsx`** — version tag + What's-new modal from patchNotes.

### Data-entry flow (`src/app/enter/…`)

**`enter/page.tsx`** (server) — cycle cards: `collapseToCycles()` folds N windows into one card per
(cycleGroupId × subject) — counts SUM (entries not heads), status takes the most-open via
`STATUS_RANK`, grace end takes the latest via `laterISO`; orphan windows (no cycle header) are
counted and explained, never silently dropped. Sections per subject with open-above / past-accordion.

**`[cycleGroupId]/[subject]/page.tsx`** (server) — group picker page; delegates wholly to
`getTeacherGroups` + `GroupCards(mode='course')`.

**`[groupKey]/page.tsx`** (server, 13.7KB) — the roster assembly. Suspense-streamed body; fast path
from card-carried searchParams vs. re-resolve path (authorizes keys, names unresolved ones);
grace-lock derivation (`locked` = any matched window status 'Locked'; `canOverride` from
capabilities per subject); multi-instance handling (one `Slice` per windowId: label from
`instanceLabel`, per-slice roster+levels fetch, empty slices reported in prose); branches to the
three grids on `subject`. Variables: `Slice {windowId,label,roster,writingRoster,mathRoster,levels,
achievementLevels,count}`, `language` (from the course, not a toggle).

**`[groupKey]/actions.ts`** (server actions) — the four save paths: `saveReadingAssessments`,
`saveWritingAssessments`, `saveMathAssessments`, `confirmRosterIPPs`. Shared trust model, stated in
each: UPN resolved server-side; assessment date = MIN(Atlantic-today, window EndDate) (late-entry
dating rule mirroring the proc's 51017 gate); **scope gate** — re-resolve the caller's roster TVF
and refuse any studentNumber not in it; per-row proc calls collecting `{saved, errors[]}` (reading/
writing sequential; math `Promise.all` bounded by the pool — the 1.2.0 timeout fix); `invalidateGroups`
after. Guarded pre-loop so transient failures return per-row errors instead of throwing (the 1.0.1
data-loss fix). Math returns an extra `unconfirmed` channel via thrown transport errors.

**`RosterEntry.tsx` / `WritingRosterEntry.tsx` / `MathRosterEntry.tsx`** (client grids, 22/21/29KB) —
three parallel implementations of the same conceptual machine:
*baseline vs selection state → dirty = diff → staged commit (Save) → optimistic baseline advance →
per-row error report*, each wired to the same four cross-cutting services (useEntryLock, entryDraft,
grace-override one-shot, SmallGroup filter where applicable).
- Reading: `baseline/sel: Record<studentKey, readingScaleId>`; four Map lookups (codeToId/idToCode/
  orderById/orderByCode); client-side delta (`computeDelta` mirrors the proc formula) + band match
  (`matchBand` mirrors DimAchievementLevel operator bounds); staged IPP confirms (`ippSel`,
  `confirmedIpp`); "New Data" checkbox = auto (differs-from-baseline) with manual override
  (`evidenceManual`); grades 7–8 already-Meeting default-hidden.
- Writing: same skeleton over `ScoreSet {ideas,organization,language,conventions}` with 'SCR'
  (Conventions-only) and per-student excluded traits (`excludedByKey` from WritingTraitExclusion);
  `avgOf`/`isComplete`/`eqSet` helpers; **`writingBand()` hardcodes the 1.75/2.75/3.5 cut scores +
  hex colours that reading reads from DimAchievementLevel** (C-3); trait order via useTraitOrder.
- Math: different grain — `marks/committed: Record<studentKey:taskKey, Mark>` where
  `Mark = '1'|'0'|'clear'|'ipp'` (a 4-state cell cycled by click); `buildGrades()` pivots flat TVF
  rows into Grade→Unit→Task→Student structure; derived summaries `taskPct` (class % heat) and
  `unitBand` (Emerging/Developing/Meeting/In-depth with IPP-excluded denominators and the
  partial-IPP ring); task checklist dirty-tracking via `deselected` set; `unconfirmed` save channel.

**`smallGroup.tsx`** — `useSmallGroup(roster, defaultHidden?)` hook + `SmallGroupFilter` UI: grade
chips + collapsible student picker, display-only filtering (hidden students keep staged edits).
Mirrors (but does not share) the math grid's inline filter — the math grid reimplements the same
grade-chips + student-picker UI inline (C-1).

### Reports suite (`src/app/reports/…`)

**`reports/page.tsx`** (server) — the Reading/Writing landing and the suite's routing brain. Derives
`oversight` (AccessLevel ∈ {Administrator, SpecialistTeacher, RegionalAnalyst}) and `regionWide`
(RegionalAnalyst → TCRCE row); URL state = `?subject`/`?cycle`/`?view` (summary|list). Four data
shapes fetched conditionally: flat cohort (+ cycle-independent `trendCohort` copy), roll-up feed
(+ all-cycles copy), per the view — the 2026-10-30 charts fix routes list-view charts through
CohortView's filtered rows while summary keeps the roll-up-fed pair. Remount-by-key on
subject+cycle (the stale-rows fix).

**`rollupModel.ts`** — the subject-agnostic roll-up domain model (the best-factored module in the
reports suite): types (`RollupStudent/Result/School/Child`, `Counts`, `MeasureStat`, `Measure`,
`SummarizeBy`, `LangFilter`), constants (`MEETING_MIN=3`, `GRADE_ORDER`, `gradeLabel`,
`gradeSpanLabel`), and pure functions `tally` (distinct-students vs per-language results, IPP
excluded), `traitMeasure`/`avgMeasure` (writing %/mean stats with EN/FR breakdowns),
`buildSchools`, `childrenOf` (Grade|Homeroom grouping with GRADE:/homeroom groupKeys).

**`RollupTree.tsx`** — generic `RollupTree<T>`: School → Grade/Homeroom → lazy-loaded student
detail. Parameterized by `loadGroup` (server action), `renderDetail`, optional `measures[]`
(writing's per-trait columns replace the single % column and enable the %/Mean toggle),
`showAll` (TCRCE row with grade → per-school drill). State: `openSchools`/`openNodes` sets,
`blocks: Record<groupKey, BlockState>` (loading|done|error — a tiny fetch state machine),
`summarizeBy`, `lang`, `measureMode`. Imports math's `heatClass`/`fmtPct` for cross-subject
consistency.

**`ReadingRollupTree.tsx` / `WritingRollupTree.tsx`** — thin subject wrappers: map TVF rows into
`RollupStudent` (reading keys language off `scaleSystem` EN_/FR_Reading; writing off
`assessmentLanguage` + trait numerics via `traitNum`), then render a per-group `ReadingDetail` /
`WritingDetail` table. Each detail reimplements the same stacked-row machinery CohortView has:
sort-key taxonomy with a PER_RESULT set, merge-vs-split mode, langRank ordering, nulls-last
comparator, rowSpan-merged demographics (C-5).

**`CohortCharts.tsx`** — presentational donut (CSS conic-gradient over achievement codes) +
by-cycle stacked bars (cumulative as-of each cycle's endDate, last 6 cycles). Fed by plain
`{code,date}` rows so both the teacher cohort and oversight roll-up drive it. Donut title follows
`?cycle` via useSearchParams.

**`CycleSelector.tsx`** — "Current" + per-started-cycle ToggleLinks writing `?cycle=<CycleGroupID>`
preserving other params. **`reports/actions.ts`** — `loadReadingGroup`/`loadWritingGroup` server
actions (UPN re-resolved; TVF re-scopes; error → `{rows: [], error}`).

**`CohortView.tsx`** (33KB, the largest client component) — the flat student-list report for both
Reading and Writing. Faceted filtering (grade range, gender, self-ID tris, homeroom[single-school
only], program, school, achievement categories '1'..'4'|'ipp'|'nodata', assessable-grades toggle)
implemented via `matchExcept(s, except)` — each facet's options are computed against all OTHER
active filters (live-trimmed facets); sessionStorage persistence (`cohortFilters`) with
validate-on-restore; multi-key deterministic sort (`DEFAULT_ORDER` tiebreak chain + clicked
primary); dual-language stacked rows (merge mode groups by studentNumber with rowSpan'd
demographics; a per-result sort splits them); chart feeds (donut = filtered+eligible; trend =
all-cycles, follows demographic chips, excludes the achievement chip). Subject branching is
pervasive (`isWriting` gates trait columns vs reading's expected/delta columns and reuses
`mostRecentLevelCode` as the writing average — the shape-pun from data.ts).

**`[studentKey]/page.tsx` + `StudentDetailView.tsx` + `actions.ts`** — student detail: server page
fetches the nav list + initial history; the client view pages prev/next entirely client-side
(`cache: Record<studentKey, AnyHistory>`, neighbour prefetch via `ensureLoaded`, URL kept in sync
with `history.replaceState`); subject toggle re-navigates. Dependency-free SVG `TrendChart`
(reading level over time with Prev-June anchor point and latest-school-year filter; writing avg
1–4). IPP display rule mirrored again (`measured` / `ippConfirmed` from the nav item's ippStatus).

### Reports > Math + RWM

**`math/mathModel.ts`** — math's shared domain model (same role as rollupModel for R/W): `Mark`
('1'|'0'|'ipp'|'blank'), band constants (`BANDS`, `BAND_HEX`, `bandForAvg` 50/75/90 cuts),
`heatClass`/`fmtPct` (also imported by the R/W tree), `BlankMode` ('exclude'|'zero' — the
user-adjustable blanks knob), `unitStat`/`meanOf`/`countUnit` (per-unit average with IPP-excluded
denominators + the <80% incomplete rule), roll-up `Tally` buckets (b1-b4|inc|ipp|none) with
`unitBucket`/`overallBucket`/`pctMeeting`/`tallyTitle`, and the `buildGrades`/`buildMarks` pivots
(flat rows → Grade→Unit→Task→Student + mark map). NOTE: `buildGrades` here and the one inlined in
MathRosterEntry are near-identical twins (entry's adds answerKey; see C-1).

**`math/mathCells.tsx`** — `BandCell` + read-only `TaskCell` (same SVG check/ring as the entry
grid, duplicated drawing — C-1).

**`math/page.tsx`** — math landing: everyone gets the same `MathRollupTree` (teachers = Taught
scope in the TVF); RegionalAnalyst adds the TCRCE row; remount on cycle.

**`math/MathRollupTree.tsx`** (21KB) — math's OWN tree implementation, structurally parallel to the
generic RollupTree but typed to unit-count rows (`TreeStudent.units: Map<unitName, UnitCounts>`;
columns = Overall + one per unit name pooled across grades; `summarize()` → `Summary {n, overall,
units}`). Same open/blocks/lazy-load state machine; expanded nodes render `GroupBlock` →
per-grade `GradeBlock` matrices with collapsible unit→task columns. Predates the generic tree;
not folded into it (C-5).

**`math/[groupKey]/page.tsx` + `MathCohortView.tsx`** (23KB) — one group's read-only matrix: same
buildGrades/buildMarks model, axis flip (tasksDown|studentsDown), blanks toggle, per-student
focus drill (`StudentGrid`), donut + by-unit stacked bars computed from the marks. The
`TasksDown`/`StudentsDown`/`StudentGrid` sub-components take the model functions as props.

**`rwm/page.tsx` + `RWMCohortView.tsx`** — RWM 0–3 roll-up: client recomputes `rwmScore` from
`blankMode` (math pct source flips between mathRollupPct/Zero); faceted grade/program/school/score
filters via the same `matchExcept` pattern as CohortView (fourth reimplementation — C-5); score
donut; `completeOnly` toggle. **`rwm/[studentKey]/…`** — per-student RWM: snapshot cards +
per-cycle score table + dependency-free `ScoreTrend` SVG; prev/next from the sorted cohort
(server-side, unlike the reading detail's client paging — a third paging pattern, C-6).

### Programming, Cycles, Ingest, Admin

**`programming/page.tsx`** — picker over `getProgrammingGroups` (tvf mirrors TeacherGroups shape so
GroupCards renders it; enteredCount slot carries "needs confirmation"); `getProgrammingSummary`
resolved separately so its failure only drops the progress chips; single-group callers skip the
picker via redirect. **`ProgrammingProgress.tsx`** — presentational chips (red/yellow/green by
confirmed/total). **`[groupKey]/page.tsx`** — roster fetch + friendly header from the opaque key.
**`ProgrammingRosterGrid.tsx`** — IPP⟷Adaptations toggle over one row-set; staged
`pending[student|subject|family]` booleans; 2-way Yes/No vs the FI 4-way cell (No/FLA/ELA/Both →
two staged family values); cell/`needsConfirm` logic; pending-aware progress chips; save via
`saveProgramming`. **`[groupKey]/actions.ts`** — scope+existence gate per kind (rows must already
exist — the procs update seeded rows), per-entry proc calls, revalidatePath.

**`cycles/page.tsx` + `ShortCyclesManager.tsx` + `actions.ts`** — cycle admin. Two-form flow:
header draft (name/dates/active/grace composed from days+hours fields → one GraceHours total) then
instance drafts (subject/language/programScope/grade band/benchmarkMonth/active; subject change
re-prefills `SUBJECT_DEFAULT_GRADES`; "remove" = deactivate existing, drop unsaved). Actions gate
on `requireCycleAdmin` (fresh capability check), generate the CycleGroupID GUID client-side-of-SQL
(`randomUUID`), call `usp_UpsertShortCycleHeader` / per-instance `usp_UpsertShortCycle`, omitting
optional params so proc NULL defaults apply.

**`ingest/…`** — `page.tsx` (capability gate, fresh), `constants.ts` (INGEST_NOTICE_MINUTES=15,
documented against the hidden-tab 8-min poll), `IngestPanel.tsx` (5-topic upload table with
per-row `RowState` ('idle'|'uploading'|UploadResult); schedule-maintenance + run buttons
deliberately not cross-gated), `actions.ts` (assertIngestAdmin; 25MB upload cap; upload →
lib/onelake; `scheduleIngestMaintenance` → usp_SetMaintenanceWindow Scope='ingest';
`runIngestCycle` → usp_TriggerIngestCycle, then invalidate identity+group caches, then
clear-window only on a CLEAN finish — a THROW leaves maintenance ON deliberately).

**`admin/maintenance/…`** — `page.tsx` (CanMaintain|sysadmin, redirect otherwise; resilient
getMaintenanceWindow), `MaintenanceControl.tsx` (QUICK picks 10/15/30/60; SHORT_NOTICE_MIN=10
two-step confirm; message field; schedule/clear via actions), `actions.ts` (assertMaintainer;
minutes 1–240; Scope='manual'; LOTO errors surfaced from the proc).

**`admin/staff-access/…`** — SysAdmin-only capability grid over StaffAppAccess: client rows +
`dirty` map + batch `saveAll` with confirm dialogs for new-sysadmin grants and empty-row removals;
self/sole-sysadmin lockout mirrored client-side (server 51051 enforces); add-by-email with the
"not in the system" external checkbox. Actions: `findStaff` (email regex + optional DimStaff
lookup), `setStaffAccess` → usp_SetStaffAppAccess + invalidateAllIdentities.

**`admin/staff-roles/…`** — same manager skeleton as staff-access (add-by-email + external
checkbox + dirty map + batch save with a long explanatory confirm). `constants.ts` holds
OVERRIDE_ROLES (3 data-access tiers + capability-only 'Maintenance'). `setRoleOverride` is the one
action that reads a proc's RESULT SET (`query('EXEC …')` for Message/Removed — migration/held
notes) instead of `execProc` (C-6).

### Root, API, config

**`layout.tsx`** — metadata/icons + force-dynamic + AppShell. **`page.tsx`** (home) — welcome from
UPN local-part (`friendlyName`), three public cards + capability-gated Admin Tools section.
**`login/page.tsx`** — thin auto-`signIn('microsoft-entra-id')` redirect page. **`error.tsx` /
`global-error.tsx`** — route/global boundaries with honest unsaved-work messaging. **api/status**
— the maintenance poll endpoint: module-level 4s cache, fail-OPEN on DB error, serverNow for
clock offsetting, LOG_STATUS_POLLS dev heartbeat. **api/health** — bare liveness. **api/auth** —
NextAuth handlers re-export. Seven `loading.tsx` files — one-line `<Loading/>` wrappers.
**Config/tooling**: `next.config.ts`, `Dockerfile` (multi-stage, pruned proddeps),
`load-secrets.cjs` (podman `*_FILE` secret preload, fail-closed), `compose.yaml`,
`scripts/conn-test.cjs` (standalone connectivity probe), `.env.example`/`.env.live.example`.

## 3.2 Warehouse SQL — per-file review

### Tables (the data model's vocabulary)

**Staging (`sql/staging`)** — 7 `Stg_*` all-VARCHAR landing tables (COPY INTO targets, column order
= the PS export header) + 6 `Wrk_*` typed working tables (translations applied; the merges' staging
→ typed checkpoint). CS shape: the classic two-phase ELT staging pattern — load-as-text, then
validate/translate once into Wrk so every downstream reconciliation step reads clean typed columns.
Key variables: `Stg_Staff.[Group]` (PS role number — reserved word, bracket-quoted),
`Stg_Section.Email_Addr` (primary teacher), `Stg_CoTeacher.Email/Role/SectionID` (only 3 of its 8
columns are used by the merge), `Stg_Enrollment.ID` (PS CC.ID — the enrollment episode match key).

**Dimensions (`sql/dimensions`)** — three SCD-2 entities (`DimStudent`/`DimStaff`/`DimSection`, all
with the lifecycle quadruple `EffectiveStartDate`/`EffectiveEndDate`/`IsCurrent`/`LastUpdated`, every
business attribute a Type-2 trigger; `DimStaff.AccessLevel` the lone Type-1 exception), one SCD-1
(`DimSchool`), the window/cycle pair (`DimAssessmentWindow` = the scoped instance;
`DimShortCycle` = the header with GUID `CycleGroupID` + `GraceHours`), and reference dims
(`DimProgram` incl. `ScopeBucket`, `DimGrade` with `GradeOrder`/`GradeBand`, `DimRole` 50-row PS
Group→RoleCode map, `DimReadingScale`/`DimReadingBenchmark`, `DimAchievementLevel` with
operator-column bounds, `DimMathTask`/`DimMathComprehensionBand`, `DimCourseAssessment`
(CourseCode→Language/Kind — the entry-language oracle), `DimGender`, `DimTerm`, `DimCalendar`,
`WritingTraitExclusion`).

**Facts (`sql/facts`)** — the three assessment facts (grain Student×Window×Date, writing +Language,
math +Task; frozen `StudentKey` + stable `StudentNumber`; as-was context columns stamped at insert:
reading LevelCode/Expected*/Delta, writing `WritingAverage`), `FactEnrollment` (Type-1 episode rows
keyed by PS CC.ID with `ActiveFlag` + key freeze-on-close), `FactSectionTeachers` (business-key
temporal bridge: SectionID×TeacherEmail×TeacherRole), `FactStaffAssignment` (StaffKey×School×Role
temporal bridge, SourceSystemID collision detection), the gate facts `FactStudentIPP`/
`FactStudentAdaptation` (SCD-2 per Student×Subject×ProgramFamily; BIT NULL = unresolved gate),
audit logs (`FactSubmissionAudit`, `FactDataQualityAudit`, `IngestRunLog`), and `PriorYearBaseline`
(denormalized prior-June wide row keyed by StudentNumber×AssessmentLanguage).

**Security/config tables (`sql/security`)** — `StaffSchoolAccess` (materialized derived RLS oracle,
TRUNCATE+rebuild per staff merge), `StaffAppAccess` (manually curated capability allowlist — six BIT
columns), `StaffRoleOverride` (manual role-context, email-keyed), `AppMaintenance` (single-row Id=1
window store), the three materialized membership caches (`SectionRosterMembership`,
`TeacherRosterMembership`, `StudentExpectedAssessment` — TRUNCATE+rebuild each ingest, the roster
TVFs' pre-joined skeleton).

### Procedures

**The five merges + orchestrator.** All five follow one canonical pipeline (documented in the
regional-assessment-platform skill): build Wrk from Stg with translations → close changed-current →
same-day in-place correction (2b/4a-prime) → same-day revival (2c/4c-prime) → insert new versions →
touch unchanged → close missing (± deactivation replacement) → audit row with pipe-delimited
counters and `[WARN: …]` segments.
- `usp_MergeStudent` (37KB) — DimStudent SCD-2 (14 trigger fields, NULL-safe EXCEPT comparison) +
  the IPP/Adaptation gate reconciliation: Step 6-pre repoints resolved gates across re-versions
  (stable StudentNumber), 6a/6c close no-longer-applicable triples against a declarative
  `ExpectedIPP`/`ExpectedAdap` CTE (the assessment-track rules: English, FI-FLA, FI≥3 ELA, Math P–6,
  J020 exception), 6b/6d insert NULL-gate placeholders. The Expected CTE is repeated **four times
  verbatim** (Fabric CTEs don't span statements) — see S-6.
- `usp_MergeStaff` (44KB) — the two-table merge (DimStaff + FactStaffAssignment) + Step 2 WRITE RULE
  (persist only access-role / teaches-this-import / override / CanMaintain), Step 3.5 email-change
  rename-in-place (shared FactStaffAssignment.SourceSystemID, 1:1-guarded), the 4a–4f phase ladder
  with the same-day marker algebra (4c-prime revive / 4c-prime2 return-close), Step 6
  StaffSchoolAccess rebuild (HomeSchool + STRING_SPLIT CanChangeSchool), Step 6b Maintenance-override
  migration.
- `usp_MergeSection` — standard SCD-2 over 8 trigger fields; Step 1's INNER JOIN DimStaff
  (IsCurrent=1 AND ActiveFlag=1) is the primary-teacher gate that excludes unresolvable sections
  (the long-term-sub trap diagnosed 2026-11-04/06); junk-row guards (blank ID, zero enrollment).
- `usp_MergeEnrollment` — Type-1 episode reconciliation keyed on PS CC.ID; ActiveFlag =
  "has DateLeft arrived?"; the freeze/re-resolve CASE on surrogate keys (both-inactive = frozen);
  Step 5 defensive close with the 2026-10-30 EndDate cap.
- `usp_MergeSectionTeachers` — business-key bridge reconciliation from Stg_Section ∪ Stg_CoTeacher
  with role normalization; the two-sided resolve gate (current DimSection AND current+active
  DimStaff) — the co-teacher half of the section trap; close-only anti-join.
- `usp_RunFullIngestCycle` — the orchestrator: 5 loads (each logged to IngestRunLog with row
  counts) → 5 merges in dependency order → DQ gate (`EXEC @rc = usp_RunDataQualityChecks`; non-zero
  → Rejected audit + Failed log + THROW 51000) → `usp_RebuildRosterMembership` → Completed
  markers. No TRY/CATCH by design (Fabric); a run with Started but no terminal row died at a load.
- `usp_TriggerIngestCycle` — thin capability gate (StaffAppAccess, 51033) → orchestrator; gating on
  StaffAppAccess (not DimStaff) is the post-reset bootstrap design.
- `usp_RebuildRosterMembership` — the three membership caches in one pass: section-stable base
  (current section + enrolment matched across ALL section versions by SectionID + current student by
  StudentNumber, date-overlap, no ActiveFlag filter — the paper-backfill decision), teacher
  projection (base ⨝ current FactSectionTeachers), expected-assessment projection (literacy only).

**Write/upsert procs.** `usp_UpsertReadingAssessment` / `usp_UpsertWritingAssessment` /
`usp_UpsertMathAssessment` are three instances of one validation pipeline: 51010 null-guard →
VARCHAR→BIGINT key casts → 51030 caller identity → 51012 window active → 51015 subject match →
window-status derivation (`Upcoming|Open|ClosesToday|Closed`) with 51032 Upcoming block → 51040
grace-lock (GraceHours boundary + per-subject override check, `GRACE-OVERRIDE` audit tag) → 51017
date gate [Start, MIN(today, End)] → 51011 student resolution with the 2026-10-30 **section-school
binding** (TeacherRosterMembership → SectionRosterMembership single-school inference → effective-date
fallback) → subject-specific validation (reading 51013/51014 scale vs instance, 51016 grade band;
writing 51018/51019 trait + language-track rules with WritingTraitExclusion-aware storage and the
allow-list average; math 51013/51018 task grade/month applicability, CLEAR-by-NULL delete) →
UPDATE-same-date / INSERT-new-date upsert → FactSubmissionAudit row. ~70% of the three bodies is
textually identical (C-8).
`usp_UpsertStudentIPP` / `usp_UpsertStudentAdaptation` — exact structural mirrors (allow-lists,
51014 precondition that the merge seeded the row, no-op fast path, close+insert flip, audit).
`usp_DeleteReadingAssessment` — delete wrapper with role-aware 51031 (teachers can't delete on a
Closed window — NOTE: reading/writing have no delete parity; see C-9).
`usp_InsertSubmissionAudit` — the original Power Apps audit wrapper (legacy caller surface).

**Admin/config procs.** `usp_UpsertShortCycleHeader` (header upsert + name/date propagation to
instance windows), `usp_UpsertShortCycle` (one instance row per call; derives ScaleSystem from
language; subject-conditional nulling of language/benchmark), `usp_SetStaffAppAccess`
(sole StaffAppAccess writer; 51050 sysadmin gate, 51051 last-sysadmin guard, empty-row DELETE),
`usp_SetStaffRoleOverride` (the most stateful admin proc: override upsert + per-email in-place
provisioning with deactivation-marker algebra, Maintenance placeholder identities, per-email
StaffSchoolAccess rebuild, migration/held notes returned as a result set), `usp_Set/
ClearMaintenanceWindow` (single-row window store; scope-widened 51040 capability gate; LOTO 51042
naming the owner), `usp_YearEndCloseOut` (bulk close of enrollments/bridge/sections for a school
year), `usp_GenerateMonthlyWindows` (LEGACY — the retired monthly-window generator; superseded by
the /cycles flow), `usp_LoadMathTasks` (parameterized COPY INTO + Type-1 upsert + batch-scoped
retire), and the five `usp_Load*Staging` loaders (TRUNCATE + hardcoded-GUID COPY INTO with the
Workspace-Identity credential workaround).

**`usp_RunDataQualityChecks`** — 49 numbered checks (52 per header) as ONE `INSERT … SELECT … UNION
ALL` into FactDataQualityAudit + PASS sentinel + result set + RETURN count. The check taxonomy IS
the warehouse's integrity contract: Orphan (surrogate FKs), IsCurrent (≤1 current row per business
key), Date (Rules A–D: current⇒EndDate NULL, closed⇒EndDate set, no reversed windows, no
overlapping windows), Reference (business-key lookups), Consistency (state contradictions — e.g.
inactive staff with current assignments, lowercase email rules, EnrollStatus allow-list).

### TVFs and views (the read surface)

All app reads are `@UPN`-parameterized **inline TVFs** granted SELECT to the SP only — the central
dogma: *reads are composable iTVFs; writes are audited procs; the UPN is trusted because only the
SP can call and the app binds it from the Entra session.* Role scoping is expressed either as
OR-across-EXISTS branches (cohort/history TVFs) or section-first with role as a predicate (roster
TVFs, the 2026-09-18 plan-shape rework).
- `tvf_UserAssessmentWindows` — the entry landing feed; contains the **window lifecycle
  derivation** (`Upcoming→Open→ClosesToday→Closed→Locked` from dates + GraceHours — Task 2's core
  DB state machine), per-window applicable/entered/done counts (CycleEntered union over 3 facts,
  Math >80% done), teacher + oversight branches (specialists on the teacher route since 10-13).
- `tvf_TeacherGroups` — the cycle-keyed course-section picker (Taught/Oversight scopes,
  DimCourseAssessment mapping, section-stable + current-teacher resolution, card counts, section's
  own school label).
- Roster TVFs `tvf_TeacherRoster` / `…Writing` / `…Math` + fast-path `tvf_TeacherRosterOwn` —
  section-first membership (reading the materialized caches) + live per-student enrichment (latest
  result by date, benchmark, IPP gate, starting point); `…Own` skips the access checks because
  TeacherRosterMembership's row presence IS the authorization.
- Cohort family — flat lists `tvf_StudentCohort`/`…Writing` (dual-language one-row-per-(student ×
  language) via StudentExpectedAssessment ∪ has-result), oversight roll-up feeds
  `…ReadingAll`/`…WritingAll`/`…MathAll` (counts only, no names), per-group drills
  `…ReadingGroup`/`…WritingGroup`/`…Math`, cross-subject `…RWM` + `tvf_StudentRWMHistory`,
  histories `tvf_StudentAssessmentHistory`/`…Writing`, programming pair
  `tvf_ProgrammingGroups`/`tvf_ProgrammingRoster`, `tvf_StudentIPP`/`tvf_StudentAdaptation`,
  `tvf_MathCohortGroups`. All 2026-10-30 cycle-scoped TVFs carry the frozen-version school
  attribution rule.
- `vw_StudentReadingStartingPoint` — the COALESCE(prior-year facts, PriorYearBaseline) year-flip
  abstraction consumed by the reading TVFs (active).
- LEGACY Power-Apps-era surface: `vw_UserAssessmentWindows`, `vw_TeacherGroups`, `vw_TeacherRoster`,
  `vw_StudentCohort`, `vw_StudentCohortTeachers`, `vw_StudentIPP`, `vw_StudentAssessmentHistory`,
  `vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData`, `vw_DimReadingScale`,
  `bridge_views.sql` — CURRENT_USER-scoped views for the retired canvas app / the abandoned
  SharePoint bridge. Still deployed objects; no active app code path reads them (Task 1 group D).
- `grant_webapp_sp.sql` — the consolidated least-privilege grant script (EXECUTE on procs, SELECT
  on TVFs/tables the SP reads).

## 3.3 Congruence findings

Each finding names the duplication/divergence, where it lives, and what one congruent form would be.

**C-1 — Grade vocabulary is re-declared nine+ times.** `GRADE_ORDER` maps + `gradeLabel()`
functions exist independently in GroupCards.tsx, smallGroup.tsx, MathRosterEntry.tsx,
rollupModel.ts, mathModel.ts, RWMCohortView.tsx, RWMStudentView.tsx, math/[groupKey]/page.tsx,
programming/[groupKey]/page.tsx — with *diverging* label spellings ('Gr 5' vs 'Grade 5';
RG = 'Graduating' vs 'Returning Grad' vs absent) and diverging ranges (math stops at 6). The
warehouse already owns this vocabulary (DimGrade.GradeOrder/GradeName/GradeBand). One
`lib/grades.ts` (or a reference fetch) should be the only source.

**C-2 — Three hand-rolled TTL caches.** groupCache / identityCache / refCache are the same
`Map<string,{at,value}>` + sweep-on-write algorithm with different TTLs, key shapes, and
wrapped-vs-bare miss signalling. One `createTtlCache<T>(ttlMs)` factory collapses ~150 lines to ~30
and makes the miss contract uniform.

**C-3 — The writing achievement bands are hardcoded client-side while reading's come from data.**
`WritingRosterEntry.writingBand()` embeds the 1.75/2.75/3.5 cuts AND hex/tint colours;
RollupTree's `meanHeat` embeds the same cuts; the SQL TVFs embed them too (by design — band-by-code
join). Reading resolves bands from DimAchievementLevel via `getAchievementLevels()` + `matchBand`.
Writing could use the same fetched bands (the dim already stores decimal bounds with operators
precisely to support the writing thresholds, per its header) — one code path, colours changeable
without a release.

**C-4 — The CohortStudent shape-pun.** `getStudentCohortWriting` returns writing data in the
reading-named interface (`ippStatusReading` carries writing status; `mostRecentLevelCode` carries
the average; six reading-only fields nulled). It buys one shared `CohortView` at the cost of
field names that lie. A discriminated union (`subject: 'Reading'|'Writing'` + honest shared core +
per-subject extension) would keep the single renderer without the misdirection.

**C-5 — Four roll-up tree / stacked-table implementations.** The generic `RollupTree<T>` (reading +
writing) and `MathRollupTree` are parallel implementations of the same School→node→lazy-block
machine (same open-sets, same BlockState, same TCRCE row, same no-homeroom note); and the
stacked-row sort-merge-split machinery (PER_RESULT key set, langRank, nulls-last comparator,
rowSpan merge) is written three times (CohortView, ReadingDetail, WritingDetail) with a fourth
variant in RWMCohortView's matchExcept faceting. The math tree predates the generic one; folding it
in (unit columns are just `measures`) and extracting a `useStackedSort` helper + a shared
`matchExcept` facet utility would delete ~1000 lines.

**C-6 — Three navigation-feedback mechanisms and three prev/next paging patterns.** LinkPending
(useLinkStatus) vs ToggleLink (router.push+useTransition) vs plain Links; reading detail pages
client-side with neighbour prefetch + history.replaceState, RWM detail re-navigates server-side,
math drill uses in-component focus state. Each divergence has a recorded reason (buffering, the
useLinkStatus regression), but a single documented "navigate with feedback" component and one
detail-paging pattern would simplify reasoning.

**C-7 — Key validation is ad hoc.** `lib/keys.ts` provides toKey/SurrogateKey but call sites
re-validate with inline `/^\d{1,20}$/` (data.ts getStudentHistory etc.) or not at all; IDs travel
as plain `string`. Either adopt the branded type at the boundaries or delete the module (half-used
abstractions cost more than none).

**C-8 — The three assessment upsert procs duplicate ~70% of their bodies.** The shared pipeline
(caller gate, window gate, status, grace-lock, date gate, section-school binding student
resolution, audit) is copy-maintained across reading/writing/math — the 2026-10-30 binding fix had
to be applied three times, and the grace-lock block twice more per proc family. Fabric's no-helper
constraints (no modules, deferred name resolution) limit options, but a shared
`tvf_ResolveEntryContext(@UPN, @WindowID, @StudentNumber, @Date)` iTVF could centralize the
window/status/lock/student-resolution reads, leaving each proc its subject-specific validation +
write (procs CAN select from iTVFs).

**C-9 — Asymmetric capability edges.** Reading has a delete proc; writing/math have none (a
mis-entered writing row can only be corrected, not removed). Reading/writing save sequentially
while math saves pool-parallel (reading/writing saves of 25+ rows pay the same latency math used
to). The IPP confirm is staged-in-grid for reading/writing but Programming-only for math. None are
bugs; all are places where the three subjects drifted.

**C-10 — Legacy vw_* ↔ tvf_* dual surface.** Eleven CURRENT_USER views mirror the @UPN TVFs
("keep in sync until the Power App is retired" per headers) but have NOT tracked the TVFs' last
year of fixes (section-stable, dual-language, specialist scope). They are a de-facto frozen,
diverged copy of the role logic — a sync burden on paper that nobody actually pays, and a trap if
anything ever binds to them again (Task 1 group D / decommission proposal).

## 3.4 Proposed streamlining plan (sequenced, each step independently shippable)

1. **Extract the shared vocabulary modules (web, pure refactor, no behavior change):**
   `lib/grades.ts` (GRADE_ORDER/gradeLabel/gradeSpanLabel/GradeBand), `lib/ttlCache.ts` (C-2),
   `lib/bands.ts` (band matching for reading AND writing from DimAchievementLevel — C-3's client
   half). Mechanical; typecheck + visual spot-check.
2. **Unify the stacked-table/facet machinery (C-5):** extract `useStackedSort` (sort spec,
   PER_RESULT split/merge, langRank, nulls-last) + `useFacetedFilters` (matchExcept + live-trimmed
   options + sessionStorage persistence) and re-base CohortView, ReadingDetail, WritingDetail,
   RWMCohortView on them.
3. **Fold MathRollupTree into the generic RollupTree** (unit columns as `measures`, Tally as a
   MeasureStat variant). Largest single deletion; needs a careful math-parity test pass.
4. **Honest cohort types (C-4):** split CohortStudent into a discriminated union; CohortView reads
   the shared core + per-subject fields. Touches data.ts + CohortView + reports/page only.
5. **SQL: shared entry-context iTVF (C-8)** + bring writing/math deletes and parallel saves to
   parity (C-9) — each a proposal for your call first, since they change proc surface/behavior.
6. **Decommission decision on the legacy vw_* surface (C-10)** — a deliberate drop-objects +
   delete-files bundle once the Power App retirement is confirmed final (Task 1 group D).

*Non-goals:* the three entry grids should NOT be merged into one generic grid — their grains
genuinely differ (level / trait-set / cell-matrix), and the current parallel-but-aligned structure
is readable. The shared services they already compose (useEntryLock, entryDraft, smallGroup,
TraitOrderToggle) are the right factoring; only the math grid's inline re-implementation of the
smallGroup filter UI should move to the shared component.
