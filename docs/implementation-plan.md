# Implementation Plan

Regional Student Assessment Data Platform — step-by-step delivery plan.
Check off each item as it's completed. Manual steps require portal/admin access; assisted steps can be generated or written by Claude.

---

## Phase 1: Foundation (Weeks 1–2)
*Goal: Fabric workspace live, schema deployed, first data loaded*

- [x] **1. Provision Fabric F8 capacity** in Azure portal — confirm Canada East region *(Manual)*
- [x] **2. Create Fabric workspace**, assign F8 capacity, confirm OneLake storage is Canada East *(Manual)*
- [x] **3. Upgrade 10 users to M365 A5** in Microsoft 365 admin center *(Manual)*
- [x] **4. Write and run SQL** to create all dimension and fact tables *(Claude can generate — `sql/dimensions/` and `sql/facts/`)*
- [x] **5. Write and run SQL** to create RLS security tables and seed with pilot users *(Claude can generate — `sql/security/`)*
- [x] **6. Request first PowerSchool CSV exports** — French program students, staff, schools, enrollments *(Manual — PowerSchool admin)*. **Done 2026-04-29**: full PS exports received, format quirks discovered (TAB-delimited / CR-only line endings / UTF-8 / no quote qualifier / `.text` extension / `NS_AssigndIdentity_African` spelling), Staff export revised to include per-row `SchoolID` column, `DimRole` mapping received from PS admin. Cross-export referential integrity confirmed via full export sample.
- [x] **7. Upload CSVs to OneLake landing zone** — **Done 2026-04-29**: created Lakehouse `Assessment_Landing` in `Regional_Data_Portal`, folder structure `Files/imports/{students|staff|sections|section-teachers|enrollments}/` in place, sample file uploaded, `COPY INTO` validated end-to-end on synthetic data (20 rows from `AssessmentDataStudentsExport.txt`). Standard config locked in: `FILE_TYPE='CSV'`, `FIELDTERMINATOR='\t'`, `ROWTERMINATOR='0x0D'`, `FIRSTROW=2`. Per-call GUID-based path required (name-based path failed with auth error). MVP strategy A; Strategy B (Pipeline + Power Automate) deferred to Step 29 before September rollout.
- [x] **8. Run merge procedures** to load pilot data into warehouse *(Claude can generate — `sql/procedures/`)*. **Done 2026-05-01:** all 5 merge procs deployed and validated end-to-end (`usp_MergeStudent`, `usp_MergeStaff`, `usp_MergeSection`, `usp_MergeEnrollment`, `usp_MergeSectionTeachers`). Plus orchestrator `usp_RunFullIngestCycle` (production entry point + dev rebuild command) and year-end close-out `usp_YearEndCloseOut` (scheduled in `Pipeline_YearEndCloseOut`, fires every 12 months on July 1 Atlantic time).

---

## Phase 2: Security & Views (Weeks 3–4)
*Goal: RLS enforced, data accessible only to correct users*

- [x] **9. Write secured SQL views**: `vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData` *(Claude can generate — `sql/security/`)*. **Done 2026-05-01.** All three views deployed; pre-enrolled student support added (PS export filter broadened to `Enroll_Status IN (0, -1)`, teacher view date-gates pre-enrolled visibility, admin view shows all pre-enrolled).
- [x] **10. Test views** by querying as pilot teacher Entra accounts *(Manual — requires real Entra identities)*. **Done 2026-05-01 via 5-test impersonation matrix** (Teacher with future pre-enrolled, Teacher with past pre-enrolled, SpecialistTeacher cross-school co-teacher, Administrator, RegionalAnalyst). Real Entra account validation pending Step 16 / Phase 4 pilot UAT but the RLS contract is fully proven.
- [x] **11. Create Fabric semantic model** pointing to warehouse views *(Manual — Power BI portal)*. **Done 2026-05-04.** `Assessment_Analytics` model deployed in **Direct Lake on OneLake** mode (switched from "Direct Lake on SQL" mid-build to enable full DAX RLS surface — see semantic-model-setup.md for rationale). 15 tables loaded, 13 relationships wired (DimSchool→DimSection inactive to break the diamond; DimCalendar.Date↔FactAssessmentReading.AssessmentDate joining on the natural DATE columns).
- [x] **12. Configure DAX RLS roles** in semantic model *(Claude can write DAX)*. **Done 2026-05-04.** Three roles (Teachers, SchoolAdmins, RegionalAnalysts) deployed via Manage Roles. RLS expressions iterated through several DAX gotchas in the process — all captured in [`power-bi/dax_rls_roles.dax`](../power-bi/dax_rls_roles.dax) header for future readers (CALCULATETABLE shortcut filters can't wrap columns in LOWER, BIT columns import as Boolean True/False not Integer, IsCurrent/EnrollStatus filters dropped on analyst roles to support historical reporting). Filter design varies per role: Teachers operational-current; SchoolAdmins per-row SchoolID gate (sees historical staff via "ever at my school" check); RegionalAnalysts unrestricted.
- [x] **13. Validate RLS** with test accounts — confirm teacher sees only their students *(Manual — requires login testing)*. **Structurally validated 2026-05-04; empirical end-user validation deferred to Phase 4 pilot UAT.** Hit a wall: Direct Lake on OneLake's SSO identity passthrough is incompatible with all three standard impersonation-testing surfaces — Fabric web report editor doesn't expose **View as**, Power BI Desktop's **View as** doesn't work for live-connected SaaS models, and Power BI Service's **Test as role** explicitly errors with "does not work with Single Sign-On." Mitigation: the SQL-side RLS already validated end-to-end via the 5-test impersonation matrix (Step 10, 2026-05-01) and the DAX rules implement identical logical filters. DAX parses and saves cleanly. Real-account validation lands at Step 21+ / Phase 4 pilot UAT — same accommodation as Step 10's "real Entra accounts" portion.
- [x] **14. Write data quality validation queries** — orphan checks, duplicate IsCurrent, date logic *(Claude can generate — `sql/scripts/`)*. **Done 2026-05-11.** [`sql/scripts/data_quality_checks.sql`](../sql/scripts/data_quality_checks.sql) — 49 checks across 5 categories (Orphan / IsCurrent / Date / Reference / Consistency) unioned into a single result set; empty result = all pass. First run against current MVP test state (DimStudent 20, DimStaff 11, DimSection 10, FactStaffAssignment 14, FactSectionTeachers 14, FactEnrollment 40, StaffSchoolAccess 7) returned zero violations. **Phase 2 closed.**

---

## Phase 3: Power Apps Entry Form (Weeks 5–6)
*Goal: Teachers can submit reading assessments from Teams*

- [x] **15. Create canvas app** in Power Apps maker portal *(Manual — maker portal)*. **Done 2026-05-11.** Single-screen test app created in TCRCE default environment with a smoke-test button.
- [x] **16. Connect app to Fabric SQL endpoint** — test connection early, may need custom connector *(Manual — connector setup in portal)*. **Done 2026-05-11.** SQL Server connector + Microsoft Entra ID Integrated auth confirmed working for reads against `Assessment_Warehouse`. **MAJOR ARCHITECTURAL FINDING**: Power Apps `Patch()` and `SubmitForm()` do NOT work against Fabric Warehouse tables (`Defaults(<FabricTable>)` returns `{}`). Established workaround pattern (memorialized in `project_powerapps_write_pattern.md` memory + fabric-warehouse-sql skill items 15-16): wrapper stored procs called from Power Apps formulas via the same SQL connector. First proc `usp_InsertSubmissionAudit` deployed; end-to-end smoke test confirmed (Power Apps button → row in `FactSubmissionAudit` with calling user's UPN). Reference: [Shabnam Watson blog](https://shabnamwatson.com/2024/10/26/updating-microsoft-fabric-warehouse-with-power-apps-visual-in-power-bi/).
- [x] **17. Design screen layout** — `scrStudentSelect`, `scrAssessmentEntry`, `scrConfirmation` *(Claude can provide full screen logic and formulas)*. **Done 2026-05-11.** Original 3-screen single-student-at-a-time design rejected after stakeholder feedback in favor of group-then-roster batch entry. New 4-screen design lives at [`docs/powerapps-screen-design.md`](powerapps-screen-design.md): `scrLanding` → `scrWindowSelect` → `scrGroupSelect` → `scrRosterGrid` (with `scrStudentData` placeholder for Phase 5+). Supports multiple concurrent windows (e.g. P-6 Reading + 7-12 Writing simultaneously), role-based filtering, edit-during-window for teachers + edit-anytime for admins/analysts, school year dropdown for admins. Includes prerequisite SQL build list for Step 18.
- [ ] **18. Build screens (Copilot scaffold) + write precision formulas (manual paste)** — Hybrid C+B build approach decided 2026-05-11 (see [`project_powerapps_build_approach`](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/project_powerapps_build_approach.md) memory). Lead with Power Apps Copilot meta-prompts for scaffolding (galleries, navigation skeletons, repeating UI patterns from the [screen design spec](powerapps-screen-design.md)); use formula-bar paste for precision pieces (OnSelect formulas, the `colDirty` dirty-tracking pattern, back-arrow confirm dialog, `usp_*` stored-proc invocations). *(Claude drafts both the Copilot prompts and the precision formulas; user pastes Copilot prompts into Studio's Copilot pane and pastes precision formulas into individual control properties)*
- [ ] **19. Write audit logging logic** to `FactSubmissionAudit` on each submission *(Claude can write formula/flow)*
- [ ] **20. Embed app in Microsoft Teams** via Teams app catalog *(Manual — Teams admin portal)*
- [ ] **21. Share Power Apps** directly with 5–10 pilot teachers *(Manual — Power Apps share dialog)*

---

## Phase 4: Pilot Testing (Weeks 7–8)
*Goal: 5–10 teachers successfully submit assessments, data is clean*

- [ ] **22. Deliver training session** for pilot teachers *(Manual)*
- [ ] **23. Monitor `FactSubmissionAudit`** for errors during UAT *(Claude can write monitoring queries)*
- [ ] **24. Fix blocking bugs** — data issues, connection errors, RLS gaps *(Claude can assist with SQL/formula fixes)*
- [ ] **25. Write post-pilot data quality report queries** *(Claude can generate)*
- [ ] **26. Document pilot feedback** and delta list for September *(Manual — with your input)*

---

## Phase 5: Full Rollout (July–September 2025)
*Goal: All schools, programs, and teachers on the platform*

- [ ] **27. Create Entra ID security groups**: `SG-Assessment-Teachers`, `SG-Assessment-SchoolAdmins`, `SG-Assessment-Regional` — populate from staff export *(Manual — Entra admin portal)*. Membership rules by warehouse `RoleCode` (translated from PS Group via `DimRole`):
  - `SG-Assessment-Teachers` → `Teacher`
  - `SG-Assessment-SchoolAdmins` → `Administrator` + `SpecialistTeacher` (both get school-level RLS via `vw_StaffSchoolAccess`; SpecialistTeacher additionally gets section-level via `FactSectionTeachers` if assigned)
  - `SG-Assessment-Regional` → `RegionalAnalyst`
  - **Excluded from all groups** (no PowerApp access at all): `ProvincialAnalyst` (DoE / Evaluation Services — confirmed 2026-04-29 they never authenticate to the app), `SupportStaff` (no student-data access by design). Rows still exist in `DimStaff` and `FactStaffAssignment` for audit, but these accounts must not appear in any of the three security groups above.
- [ ] **28. Full PowerSchool export** — all programs, all schools *(Manual)*
- [ ] **29. Build automated CSV ingestion (Strategy B)** — replaces manual Step 7 uploads. Components: (a) Fabric Data Pipeline with Copy activities reading from `Files/imports/{topic}/` into staging tables, (b) Power Automate flow that watches the OneLake folder and triggers the Pipeline on new file arrival, (c) Pipeline calls the existing Step 8 merge procs after staging is loaded. Required before September rollout. *(Claude can generate Pipeline JSON + flow structure — `power-automate/`, `pipelines/`)*
  - **Extension-rename step required**: PS exports default to `.text` extension, which blocks Fabric Lakehouse UI preview (only `.txt` / `.csv` / `.json` etc. are previewable). The Power Automate flow (or whatever drops files into the Lakehouse) must check the incoming filename and rename `.text` → `.txt` (or `.csv`) before the file lands in the watched folder. Required for operational debuggability — when something goes wrong, an admin needs to be able to open the file in the Lakehouse UI without downloading it first. The COPY INTO logic itself doesn't care (FILE_TYPE='CSV' is explicit), so the rename is purely for human-facing tooling. Captured 2026-04-29 after hitting this during Step 7 manual testing.
  - **Line-ending normalization step required**: PS direct table extracts use CR-only line endings (`0x0D`, old-Mac-style), not CRLF. Without normalization the staging COPY INTO needs `ROWTERMINATOR = '0x0D'` to load anything (default expects CRLF and silently returns 0 rows). The Power Automate flow should convert CR → CRLF (or LF) on file arrival so the merge procs and any future tooling see standard line endings. Captured 2026-04-29 during Step 7 manual testing.
- [ ] **30. Implement full SCD Type 2 merge procedures** for all dimensions *(Claude can generate — `sql/procedures/`)*
- [ ] **31. Add `FactAssessmentWriting`** and configure writing rubric entry in Power Apps *(Claude can generate SQL + formulas)*
- [ ] **32. Build school admin monitoring dashboard** in Power Apps *(Claude can provide logic and formulas)*
- [ ] **33. Build Power BI reports** for 10 regional analysts *(Claude can write DAX measures and model config — `power-bi/`)*
- [ ] **34. Configure incremental refresh** on fact tables in semantic model *(Manual — Power BI portal)*
- [ ] **35. Historical data backfill** if required *(Claude can generate backfill scripts)*
- [ ] **36. Final security audit** against PIIDPA checklist *(Manual — Claude can provide checklist)*

---

## Progress Summary

| Phase | Total Steps | Completed |
|-------|-------------|-----------|
| Phase 1: Foundation | 8 | 8 |
| Phase 2: Security & Views | 6 | 6 |
| Phase 3: Power Apps | 7 | 3 |
| Phase 4: Pilot Testing | 5 | 0 |
| Phase 5: Full Rollout | 10 | 0 |
| **Total** | **36** | **17** |

---

## Notes

- **Highest risk item**: Step 16 (Power Apps → Fabric SQL connection) — test this as early as possible
- **Hard deadline**: Steps 1–21 must be complete by June 2025 for pilot launch
- **Deferred to September**: Writing assessments, Power BI reports, automated ingestion, full SCD Type 2, security groups
- **RLS approach**: Data-level filtering uses `USERPRINCIPALNAME()` matched against the teacher-of-record email in the PowerSchool section export — no security groups required for this. Groups are only needed at full rollout for managing app access across ~200 teachers.
- **Fabric Warehouse T-SQL limitations**: No `DEFAULT` constraints, no `PRIMARY KEY`/`FOREIGN KEY` in `CREATE TABLE`, no `NVARCHAR` (use `VARCHAR`), no `DATETIME` (use `DATETIME2(0)`), `DATETIME2` requires explicit precision 0–6, `IDENTITY` columns must be `BIGINT` not `INT`, `IDENTITY` takes no seed/increment parameters, `CREATE INDEX` not supported (columnstore is automatic). Data integrity is enforced through ETL procedures, not database constraints. FK relationships must be defined manually in the Power BI semantic model. Full reference in `/fabric-warehouse-sql` skill.
- **DimCalendar**: Original WHILE loop version is slow (~5+ min for 5844 rows). Rewritten as a single bulk INSERT using cross-join CTE — use the current file version.
- **Year-end close-out (deferred)**: Build a scheduled procedure that closes out sections, FactSectionTeachers triples, and FactEnrollment rows when a school year ends — independent of the regular ingest. The regular merge anti-join handles this *eventually* (when next year's data lands), but that leaves Jun–Aug with stale rosters surfacing in Power Apps. Driven by `DimTerm.SchoolYearEnd`. Tackle during/after Step 8 (merge procedures), before September rollout.
- **Ingest strategy A→B migration (pre-launch)**: MVP uses Strategy A — manual Lakehouse upload + `COPY INTO` in merge procs. Strategy B (Fabric Data Pipeline + Power Automate trigger) replaces this before September rollout — see Step 29. **Step 8 merge proc design must support both**: keep the CSV-loading step (`COPY INTO Stg_X FROM '...'`) decoupled from the merge logic itself so the Pipeline replacement is a layer-swap, not a rewrite. Decision recorded 2026-04-29.

### Left Off — 2026-05-11 (long session, multiple architectural findings)
- **Last completed steps**: 14 (data quality), 15 (canvas app shell), 16 (Power Apps → Fabric SQL connection), 17 (screen design spec). **17 of 36 steps complete overall.** Phase 3 at 3/7.
- **What landed today**:
  - **Step 14 verified**: `sql/scripts/data_quality_checks.sql` ran against `Assessment_Warehouse`, all 49 checks returned empty result. Code was committed in prior session but never executed.
  - **Reserved-words discovery**: `Current` is reserved in Fabric Warehouse T-SQL — can't be used as a bare column alias. Captured alongside `Group` and `RowCount` in fabric-warehouse-sql skill's new "Reserved Words" section.
  - **PR opened + merged for all Phase 1+2 work** — branch `step-14-data-quality-checks` (which actually held Steps 8-14 + all Phase 2 deliverables) merged to main. Created fresh `phase-3-power-apps` branch for ongoing Phase 3 work.
  - **Step 15 closed**: canvas app shell created in TCRCE Power Platform default environment with single test button.
  - **Step 16 closed — MAJOR ARCHITECTURAL FINDING**: Power Apps `Patch()` and `SubmitForm()` do NOT work against Fabric Warehouse tables. `Defaults(<FabricTable>)` returns `{}` because the SQL connector can't introspect the PK-less / no-DEFAULT schema. Validated independently by [Shabnam Watson blog](https://shabnamwatson.com/2024/10/26/updating-microsoft-fabric-warehouse-with-power-apps-visual-in-power-bi/). Workaround pattern established: wrapper stored procs called from Power Apps formulas via the same SQL connector. First proc `usp_InsertSubmissionAudit` deployed; smoke test passed end-to-end (Power Apps button → row in `FactSubmissionAudit` with `SubmittedBy = jeffrey.raine@tcrce.ca`).
  - **PIIDPA correction in CLAUDE.md**: Earlier wording said "data must remain in Canada East" — that's stricter than PIIDPA actually requires. PIIDPA requires Canadian residency (any region); Canada East is the project's deliberate Fabric implementation choice, not the regulatory floor. Both spots in CLAUDE.md softened to reflect this. Memory: `feedback_piidpa_canada_not_canada_east.md`.
  - **Time zone convention established and applied**: Fabric Warehouse server clocks are UTC unconditionally. Project convention is "store UTC, display/compare in Atlantic with DST" via `AT TIME ZONE 'Atlantic Standard Time'` (Windows TZ ID handles DST automatically — returns ADT in DST window, AST otherwise). Audit found 7 spots needing Atlantic conversion (vw_TeacherStudents pre-enrolled date gate + all 5 merge proc `@EffectiveDate` fallbacks + usp_YearEndCloseOut year-of-closing computation + EffectiveDate fallback). All 7 source files updated; `sql/scripts/deploy_timezone_audit.sql` created and executed clean against the warehouse. Data quality re-check after deploy: PASS. Memory: `project_timezone_convention.md`. Skill update in fabric-warehouse-sql.
  - **Step 17 design spec drafted**: [`docs/powerapps-screen-design.md`](powerapps-screen-design.md). Substantial design pivots during the session: (1) original 3-screen single-student-at-a-time design rejected for group-then-roster grid; (2) ProgramFamily on `DimAssessmentWindow` retained after initial proposal to drop (windows CAN scope by program); (3) `scrLanding` added to separate Student Data viewing from Data Entry. Final design: 4 screens (`scrLanding` → `scrWindowSelect` → `scrGroupSelect` → `scrRosterGrid`), supporting multiple concurrent windows, role-based filtering, edit-during-window for teachers + edit-anytime for admins, school year dropdown for admins/analysts.
  - **3 new memory files**: PIIDPA correction, Power Apps write pattern, time zone convention.
  - **fabric-warehouse-sql skill updated 3 times**: Reserved Words section (Group/RowCount/Current), items 15-16 (Power Apps write limitations + workaround pattern), Time Zone Convention section.
  - **gh CLI installed** locally via winget (was previously absent — captured in session-wrap skill fallback). Not yet authenticated (no `gh auth login` run); next session can either set up auth or continue using the GitHub Pull Requests VS Code extension.
- **Test data state at session end**: Same as 2026-05-04 EOD (DimStudent 20, DimStaff 11, FactStaffAssignment 14, DimSection 10, FactEnrollment 40, FactSectionTeachers 14, StaffSchoolAccess 7) PLUS:
  - 1 row in FactSubmissionAudit from the Power Apps smoke test (`Source = 'PowerApps'`, `SubmittedBy = jeffrey.raine@tcrce.ca`)
  - Multiple rows in FactDataQualityAudit (PASS sentinels from each EXEC of `usp_RunDataQualityChecks` — at least 3 today: deploy verification + post-Step14-deploy + post-timezone-audit)
- **Pending issues — Step 18 prerequisite SQL build list (in order):**
  1. New `DimGrade` table + 15-row seed (PP=−1, P=0, 1-12, RG=13)
  2. `usp_MergeStudent` Wrk_Student translation update: PS `grade_level=13` → `'RG'` alongside existing `0`→`'P'` and `-1`→`'PP'`
  3. `DimAssessmentWindow` schema migration: drop `AppliesTo`, drop `IsCurrentWindow`, rename `ProgramCode` → `ProgramFamily`. Migration script + redeploy.
  4. New view `vw_UserAssessmentWindows` (full SQL drafted in design doc)
  5. Revised view `vw_TeacherGroups` (window-parameterized; full SQL drafted)
  6. Revised view `vw_TeacherRoster` (window-parameterized; full SQL drafted)
  7. New proc `usp_UpsertReadingAssessment` (with server-side role + window-state enforcement; no OUTPUT clause; computes ReadingDelta)
  8. Seed `DimAssessmentWindow` with MVP pilot windows (likely 2: English Reading all-grades + French Reading FI-only)
  9. Verify `DimReadingScale` is populated for relevant program/grade combos (probably needs sourcing from assessment team — open question)
- **Pending issues — Power Apps app build (Step 18 + parallel)**:
  - Build all 4 screens (currently only the 1-button test screen exists)
  - Wire all data sources for the new SQL objects above
  - Implement state vars (`gblIsAdminOrAnalyst`, `gblSelectedWindow`, `gblSelectedGroup`, `gblCanEdit`, `colDirty`)
  - Implement save behavior (ForAll + proc call + Notify toast)
  - Implement back-arrow unsaved-changes confirm dialog
  - Validate Power Apps keyboard navigation approximation works for typical roster sizes (25-30 students)
- **Pending issues — verifications / longer-term**:
  - Real Entra-account RLS validation (Phase 4 pilot UAT, deferred per Step 13 closure)
  - Concurrent-edit race feedback to losing party (deferred — acceptable for MVP per spec)
  - Synthetic Returning Graduate student data for testing the new ingest translation
  - Full-cycle test with multiple concurrent windows in `DimAssessmentWindow` once seeded
- **Open architectural questions for next session**:
  - `vw_UserAssessmentWindows` UNION-across-3-RLS-views vs explicit role-branching (current design uses UNION; works but worth user confirmation when implementing)
  - `DimReadingScale` content sourcing — is there an assessment team contact?
  - gh CLI authentication setup (optional — only if user wants me to drive PRs end-to-end without leaving the terminal)
- **Pending issues — housekeeping**:
  - `origin/step-14-data-quality-checks` still on GitHub (no auto-delete-on-merge); local copy gone. Safe to delete from GitHub Branches page.
  - `origin/session-2026-04-29` and `origin/session-2026-04-30` stale branches still on GitHub (also safe to delete).
- **Blockers**: None. Step 18 SQL prereqs can begin immediately; Power Apps screen build can run in parallel.

### Left Off — 2026-05-04
- **Last completed steps**: Steps 11, 12, 13 closed (Step 13 with empirical-validation deferral to Phase 4 pilot UAT — same accommodation as Step 10's "real Entra accounts" portion). Phase 2 now 5 of 6.
- **What landed today** (substantial session, lots of architectural pivots):
  - **Step 11 — semantic model deployed** in **Direct Lake on OneLake** mode. Started in Direct Lake on SQL; ran into CONTAINSROW being blocked in DirectQuery RLS subset; pivoted. 15 tables loaded, 13 relationships wired (DimSchool→DimSection inactive to break the diamond; DimCalendar.Date↔FactAssessmentReading.AssessmentDate joining on natural DATE columns instead of DateKey).
  - **Step 12 — three DAX RLS roles deployed**: Teachers (operational current-only), SchoolAdmins (per-row SchoolID gate, allows historical reporting), RegionalAnalysts (unrestricted). Iterated through several DAX gotchas: LOWER inside CALCULATETABLE filter shortcut blocked, BIT comparison `= 1` fails (use `= TRUE`), CONTAINSROW blocked. Per-role filter strategy refined to drop redundant defensive filters (EnrollStatus, IsCurrent on analyst roles, AccessLevel on StaffSchoolAccess gate).
  - **Step 13 — RLS validation deferred**. Hit hard wall: SSO identity passthrough is incompatible with all three impersonation-testing surfaces (Fabric web View as absent; Desktop View as doesn't work for live SaaS; Service Test as role errors with "doesn't work with SSO"). SQL-side RLS already validated 2026-05-01 with same logic; DAX parses + saves cleanly. Deferred to Phase 4 with real Entra accounts.
  - **MAJOR refactor: vw_StaffSchoolAccess materialized as StaffSchoolAccess table**. Required to unblock Direct Lake on OneLake mode (which doesn't permit views). Rebuild logic added as Step 6 to `usp_MergeStaff`. Same staleness as the prior view, no manual entries — just materialized. Migration: `sql/scripts/migrate_StaffSchoolAccess_materialize.sql`. Deleted old view file, updated vw_SchoolStudents to reference the table.
  - **DimStudent column rename**: stripped misleading "Current" prefix from 4 columns. `CurrentGrade → Grade`, `CurrentSchoolID → SchoolID`, `CurrentIPP → IPP`, `CurrentAdap → Adap`. Reason: on a Type 2 dim every row is a point-in-time snapshot, "Current" prefix was inaccurate. PS source columns in `Stg_Student` keep their PS-side names. Migration: `sql/scripts/migrate_DimStudent_strip_current_prefix.sql`. Touched 19 files.
  - **DimRole 22/32 migration applied + cascaded**. APSEA itinerant + IB/O2/Co-op coordinators moved from `SpecialistTeacher` to `Teacher`. Verified: apsea.itinerant now `RoleCode='Teacher'`, `AccessLevel=NULL`, dropped out of StaffSchoolAccess.
  - **`reset_and_run_full_ingest.sql` script** committed. Canonical truncate-6 + orchestrator pattern from feedback memory, now in source control.
  - **FactEnrollment Step 2 refinement (deployed and verified end-of-session)**: surrogate keys CASE-gated to freeze on already-inactive rows (point-in-time correctness for closed enrollments). Active rows continue to re-resolve normally. Header docstring + in-line comment explain the case table. Proc dropped + recreated; reset+ingest cycle ran cleanly.
  - **SchoolAdmins DimStudent DAX cleanup (deployed)**: redundant `StaffSchoolAccess[AccessLevel] IN { ... }` filter dropped from the role's DimStudent rule (StaffSchoolAccess only contains school-tier rows by construction). User pasted the simplified block in Power BI's Manage Roles and saved.
  - **DAX file restructured** with heavy `████` role separators and `╭─╮` block headers for visual scanning in environments without DAX syntax highlighting (the user works in VS Code which doesn't parse DAX).
  - **New memory: `project_assessment_fact_scd_policy.md`** — per-fact SCD linking policy. Documents FactEnrollment refinement and the planned Type 2 frozen policy for FactAssessmentReading / FactAssessmentWriting (Step 31).
- **Test data state at session end**: DimStudent 20 / 18+2pre. DimStaff 11. FactStaffAssignment 14. DimSection 10. FactEnrollment 40 / 39 active. FactSectionTeachers 14. StaffSchoolAccess 7 / 3 unique school-tier staff.
- **Next-session TODO**:
  1. **Step 14 — write data quality validation queries** (`sql/scripts/`): orphan checks, duplicate-IsCurrent on Type 2 dims, date-window logic. Closes Phase 2.
  2. Then **Phase 3 — Step 15+ Power Apps work**. Step 16 (Power Apps → Fabric SQL connection) is the highest-risk item per implementation plan; tackle that early.
- **Blockers**: None.

### Left Off — 2026-05-01
- **Last completed steps**: Steps 8, 9, and 10 fully closed (with Step 10's "real Entra accounts" portion deferred to Step 16 / Phase 4 — RLS contract is proven via impersonation, the open piece is just pilot account UAT).
- **What landed today** (substantial session):
  - **Step 8 closed**: 3 more merge procs deployed and validated end-to-end (`usp_MergeSection`, `usp_MergeEnrollment`, `usp_MergeSectionTeachers`). Plus `usp_RunFullIngestCycle` orchestrator and `usp_YearEndCloseOut` (scheduled in `Pipeline_YearEndCloseOut` — fires every 12 months on July 1 Atlantic, dynamic-expression year derivation).
  - **Step 9 closed**: `vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData` deployed. Pre-enrolled student support added — PS Students export filter broadened from `Enroll_Status = 0` to `Enroll_Status IN (0, -1)`; teacher view date-gates pre-enrolled visibility (`StartDate <= today`), admin view shows all pre-enrolled regardless of date.
  - **Step 10 closed**: 5-test impersonation matrix executed against the views (swap email in DimStaff/FactSectionTeachers, run views, revert). Every result matched expected counts and student names — pre-enrolled date gate works in both directions, cross-school co-teaching works, multi-school CanChangeSchool unpacking works.
  - **Steps 11-12 deliverables ready**: [`docs/semantic-model-setup.md`](semantic-model-setup.md) (full click-through for `Assessment_Analytics` model in DirectLake mode) and [`power-bi/dax_rls_roles.dax`](../power-bi/dax_rls_roles.dax) (three RLS roles with symmetric DimStudent + DimStaff filters). Manual Fabric portal setup pending Monday.
  - **DimRole reclassification (code-only, migration pending)**: groups 22 (IB/O2/Co-op Coordinators) and 32 (APSEA Itinerant Teachers) moved from `SpecialistTeacher` to `Teacher`. Rationale: both are teaching roles; APSEA contractors don't even have TCRCE Entra accounts. Side benefit: removed the only AccessLevel-branching case in the SchoolAdmins DAX RLS. Migration script `migrate_DimRole_22_32_to_Teacher.sql` written but NOT yet applied to the warehouse.
  - **`fabric-warehouse-sql` skill update**: item #14 added — `USERPRINCIPALNAME()` is not supported in Fabric Warehouse T-SQL; use `CURRENT_USER` for SQL view RLS. (DAX RLS roles still use `USERPRINCIPALNAME()` — different code path, works fine in DAX context.)
  - **Memory adds**: feedback rule for "always truncate all 6 tables before `usp_RunFullIngestCycle`" so future Claude sessions don't selectively truncate and hit stale-key issues.
- **Monday TODO (in order)**:
  1. Apply `sql/scripts/migrate_DimRole_22_32_to_Teacher.sql` then run the canonical 6-table truncate + `EXEC usp_RunFullIngestCycle` to cascade the RoleCode change through `FactStaffAssignment` and `DimStaff.AccessLevel`.
  2. Build the `Assessment_Analytics` semantic model in the Fabric portal per [`docs/semantic-model-setup.md`](semantic-model-setup.md).
  3. Configure the three DAX RLS roles per [`power-bi/dax_rls_roles.dax`](../power-bi/dax_rls_roles.dax).
  4. Validate via "View as → Other user" using the same 5 impersonation users from Step 10's SQL tests.
- **Blockers**: None.

### Left Off — 2026-04-30
- **Last completed step**: Substantial Step 8 progress — first two merge procs deployed, validated end-to-end against synthetic data.
- **What landed today**:
  - **DimStudent ingest**: 4 SQL files committed (`Stg_Student`, `Wrk_Student`, `usp_LoadStudentsStaging`, `usp_MergeStudent`). Validated against the regenerated 18-row synthetic file: first run inserted 18, idempotent re-run inserted 0, SCD test (Alpha homeroom edit + Iota deletion) produced 1 versioned + 1 deactivated as expected. All translations verified (Grade `0`→`'P'` / `-1`→`'PP'`, MM/DD/YYYY DOB parse, three boolean encodings, SchoolID padding, MiddleName empty→NULL).
  - **DimStaff + FactStaffAssignment ingest**: 5 SQL files committed (`Stg_Staff`, `Wrk_StaffPersons`, `Wrk_StaffAssignment`, `usp_LoadStaffStaging`, `usp_MergeStaff`). Validated against the synthetic 14-row staff file: produces 11 unique persons (APSEA itinerant 4-row collapse worked) + 14 bridge rows. All sentinels translated (HomeSchoolID `0`→NULL for ProvincialAnalyst, SchoolID `0`→`0000` on bridge). AccessLevel priority logic verified (`RegionalAnalyst > Administrator > SpecialistTeacher`; Teacher / ProvincialAnalyst / SupportStaff → NULL).
  - **Test-data tweak**: `_generate_test_dummies.ps1` updated to strip non-Active EnrollStatus rows (Beta `-1`, Omicron `3`) and convert Xi to Active — production PS export filter is `Enroll_Status = 0`, synthetic data should match. Students 20→18, Enrollments 37→36.
  - **Anti-join semantics decision**: `DimStudent` uses close-only no-replacement (multi-valued absent state); `DimStaff` uses close + insert ActiveFlag=0 replacement (binary absent state). Documented in project memory.
  - **SessionStart hook**: `.claude/settings.json` (committed) injects an instruction to run `session-start` skill on every new session — workaround for project skills not auto-discovered by harness. CLAUDE.md got a project-skills table for the same reason.
  - **Memory adds**: `feedback_fabric_stale_preview.md` (data-preview pane is cached, never trust it for verification), and project-memory updates capturing the merge-proc patterns + AccessLevel migration ordering gotcha.
- **In progress**: nothing — both merges fully validated.
- **Next action**: continue Step 8 with `usp_MergeSection` (DimSection). Same 4-file pattern as `usp_MergeStudent`. Then `usp_MergeEnrollment` (FactEnrollment, depends on DimStudent + DimSection), then `usp_MergeSectionTeachers`. After all four, build the deferred year-end close-out procedure.
- **Operational note**: `Files/imports/students/` in OneLake currently holds the SCD-test version (Alpha edited, Iota removed). To restore the baseline 18-row file, re-run `pwsh -File data/imports/_generate_test_dummies.ps1` and re-upload. Other folders unchanged. `Stg_StudentTest` (legacy from Step 7) still exists in the warehouse — `DROP TABLE Stg_StudentTest;` when convenient.
- **Blockers**: None.

### Left Off — 2026-04-29
- **Last completed step**: Steps 6 + 7 fully closed. End-to-end Step 7 ingest pipeline validated against synthetic test data: 20 rows in `Stg_StudentTest` from `AssessmentDataStudentsExport.txt` in OneLake.
- **Schema additions this session**:
  - `DimRole` (50 rows, 6-value RoleCode taxonomy after PS admin clarified roles): `Teacher`, `SpecialistTeacher` (NEW), `Administrator`, `RegionalAnalyst`, `ProvincialAnalyst` (NEW), `SupportStaff` (NEW). ProvincialAnalyst/SupportStaff excluded from `vw_StaffSchoolAccess`.
  - `DimGender` (3 rows: F/M/X) static reference.
  - `DimStaff.AccessLevel` column (Type 1 — only Type 1 column on DimStaff). Computed at ingest from highest-priority school-tier RoleCode. Replaces per-query MAX(CASE) in `vw_StaffSchoolAccess`. Migration: [migrate_DimStaff_add_AccessLevel.sql](../sql/scripts/migrate_DimStaff_add_AccessLevel.sql).
  - `vw_StaffSchoolAccess` simplified to pure DimStaff unpacking — no joins, no aggregation.
- **Fabric Warehouse quirks discovered (added to fabric-warehouse-sql skill items 12–13)**:
  - `COPY INTO` does NOT support `ENCODING` parameter (UTF-8 only).
  - `COPY INTO` default `ROWTERMINATOR` doesn't catch CR-only line endings — silent 0-row load. PS direct extracts use CR-only; specify `ROWTERMINATOR = '0x0D'` always.
  - GUID-based OneLake path required (name-based `abfss://...` failed auth in this environment).
  - `RowCount` is reserved — use `RowsLoaded` or `[RowCount]`.
- **PS export reality (vs. earlier assumptions)**:
  - Direct extracts: TAB-delimited, `.text` extension (not previewable in Lakehouse — rename to `.txt`/`.csv` on upload), CR-only line endings, UTF-8 no BOM, no quote qualifier (header at minimum; data may show quotes in preview as a render artifact, but FIELDQUOTE not needed).
  - Field-name correction: `NS_AssigndIdentity_African` (with the extra `d`).
  - Staff export per-row `SchoolID` column required and confirmed present after PS admin re-export.
  - Sentinels: HomeSchoolID `'0'` → ingest translates to NULL; per-row SchoolID `'0'` → translates to `'0000'` (district-tier aggregate marker).
- **Ingest architecture**: Strategy A (Lakehouse + manual upload + `COPY INTO`) for MVP. Strategy B (Fabric Data Pipeline + Power Automate trigger) deferred to Step 29 before launch. Step 29 must include extension-rename (`.text` → `.txt`) and line-ending normalization (CR → CRLF/LF).
- **Synthetic test data generated** for Step 8 dev: [data/imports/_generate_test_dummies.ps1](../data/imports/_generate_test_dummies.ps1) creates 5 cross-linked files exercising every translation rule (all grades incl. `0`/`-1`, all genders, all 4 EnrollStatus, all boolean encodings, multi-school staff, district sentinel, every active RoleCode bucket, term mix, early-exit + empty-DateLeft enrollments).
- **Folder structure**: `data/imports/{students|staff|sections|section-teachers|enrollments}/` (mirrored in OneLake `Files/imports/...`).
- **Compliance lesson saved** ([feedback_no_live_ps_connection.md](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/feedback_no_live_ps_connection.md), [feedback_compliance_flagging.md](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/feedback_compliance_flagging.md)): no live PS connection means freshness arguments are invalid; default to materialization on ingest. Don't ask user to download production OneLake files for me to inspect — use synthetic dummies + metadata-only diagnostics.
- **Next action**: Step 8 — write `usp_LoadStudentsStaging` + `usp_MergeStudent` for DimStudent, exercising boolean translations + Grade `0`→`'P'` / `-1`→`'PP'` + `MM/DD/YYYY` date parsing + all-Type-2 SCD logic. 20 synthetic rows already loaded in `Stg_StudentTest` ready for validation.
- **Blockers**: None.

### Left Off — 2026-04-28
- **Last completed step**: Step 5. Step 6 in progress — both field-mapping and export-procedures docs are complete with sources/filters filled in for all 5 exports; awaiting first test CSV to validate format.
- **Schema work this session** (significant — schema is now stable for MVP):
  - `LastUpdated` added to 7 tables that lacked it. `FactEnrollment` also got `SourceSystemID`. Migration: [migrate_add_LastUpdated_step1_schema.sql](../sql/scripts/migrate_add_LastUpdated_step1_schema.sql) + step2 (split because of Fabric parser issue — see fabric-warehouse-sql skill item 11).
  - DimStudent: 6 demographic fields added (Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous, CurrentIPP, CurrentAdap). EnrollStatus value list corrected (0/2/3/-1, was wrongly documented).
  - DimStaff: Title field added.
  - DimSection: 4 fields added (SectionNumber, CourseName, EnrollmentCount, MaxEnrollment).
  - FactSectionTeachers: schema changed to use business keys (SectionID, TeacherEmail) instead of surrogates — decoupled from DimSection / DimStaff versioning.
- **SCD policy decisions this session**:
  - **All-Type-2 policy** applied to DimStudent, DimStaff, DimSection. Every business attribute triggers a new version. Rationale: report reproducibility ("Better to flag it than putting toothpaste back in the tube" — same logic for stale rosters in old reports).
  - **FactStaffAssignment.SourceSystemID** promoted to Type 2 trigger — detects email-reuse collisions where TCRCE's `first.last@tcrce.ca` pattern could let a new hire silently inherit a retired teacher's history.
  - **FactSectionTeachers decoupled** — no longer cascades from DimSection. Reconciles independently by (SectionID, TeacherEmail, TeacherRole) triple. Side benefit: vw_TeacherStudents matches USERPRINCIPALNAME() against TeacherEmail directly with no DimStaff join.
  - **Boolean field translation rules** for DimStudent (documented in field-mapping doc): PS sends Yes/No, 1/2, or Y/N depending on the field; ingest normalizes all to BIT (1/0/NULL).
- **Operational changes**:
  - New [export-procedures.md](export-procedures.md) doc — operational record of how each test CSV is being pulled. Companion to field-mapping doc. Source/Filters filled in for all 5 exports. Pull History table at the bottom.
  - New [data/imports/](../data/imports/) drop folder, gitignored, for test CSVs.
  - Exports renumbered 1-2-3-4-5 (dropped Schools as Export 3 → folded into "Tables NOT Requiring PowerSchool Data").
  - PS table-number fix: teacher email is `[5]` (Teachers), not `[39]`.
- **Year-end close-out procedure** added as deferred work (see Notes section above) — needed before September rollout.
- **Next action**: Drop a test CSV in `data/imports/` for me to validate format, OR start Step 8 (merge procedures). Project memory has full design notes for Step 8.
- **Blockers**: None.
