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
- [ ] **18. Build screens via VS Code YAML authoring (pac canvas pack/unpack)** — Approach pivoted 2026-05-13 from the original Copilot-hybrid plan after Power Apps Copilot proved unreliable. Current workflow: Claude edits `powerapps/sources/Src/*.pa.yaml` directly; Claude packs via `pac canvas pack` after each change; Studio is used only for the initial bootstrap and final visual polish. Full reference: [`.claude/skills/power-apps-canvas-build.md`](../.claude/skills/power-apps-canvas-build.md). Memories: [`project_powerapps_build_approach`](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/project_powerapps_build_approach.md), [`feedback_powerfx_identifier_column_args`](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/feedback_powerfx_identifier_column_args.md), [`project_powerapps_bigint_precision`](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/project_powerapps_bigint_precision.md), and the other `*_powerapps_*` memories in the index.
  - **Status (2026-06-08)**: 8 screens built — scrLanding, scrWindowSelect, scrGroupSelect, scrRosterGrid (Save + Delete shipped), scrIPP, scrIngest (regional-analyst manual-trigger stub), scrStudentData (cohort: clickable hyperlink name cue + Grade min/max **range** filter + persistent filters + gallery + Pie/clustered-Bar charts), scrStudentDetail (**v1 complete** — info strip with IPP status, chronological most-recent-first assessment timeline, prev/next cohort nav, and a `LineChart@2.3.0` of **reading level (`LevelOrder`) over time** with the chart and table sharing the vertical space 50/50 and the Y-axis pinned `YAxisMin=0`/`YAxisMax=31`). Remaining within Step 18: add scrIPP entry button to scrLanding; admin/analyst-only filters on scrStudentData (likely a SQL view extension); visual polish across all screens.
  - **Status (2026-06-10)**: Direction B restyle ported & validated for **6 of 7 screens** (scrLanding, scrIPP, scrWindowSelect, scrGroupSelect, scrStudentDetail, scrStudentData); **only scrRosterGrid remains**. `HexColorTint` tint SQL **deployed**. scrStudentData cohort filters built: centralized `colCohortFiltered`; multi-select Homeroom/Program/School(analyst-only)/Achievement; collapsible filter bar (header-mounted count + Reset + toggle). **Pending**: Teacher cohort filter (needs a `vw_StudentCohort` teacher-exposure SQL change, gated to `gblIsAdminOrAnalyst`) + optional Assessment-Window as-of-window recompute. Still also open: scrIPP entry button on scrLanding; cross-screen polish.
  - **Status (2026-06-12)**: restyle **COMPLETE (7/7 validated)**; Pack B Teacher filter **built** (`vw_StudentCohortTeachers` deployed; combo gated to `gblIsAdminOrAnalyst`); scrIPP entry button confirmed already present (restyled scrLanding card). **⚠ LICENSING PIVOT supersedes remaining Step 18 scope**: the SQL Server connector is premium (A3/A5 don't cover it) → end-user apps rebind to **SharePoint lists** per [`docs/sharepoint-entry-pivot.md`](sharepoint-entry-pivot.md); the SQL-bound app becomes maker-only reference; the app **splits** (Teacher Entry, lists-only / admin screens ported to school-scoped lists). Binding constraint: **$0 per-user licensing — no PAYG, no premium**. Full record: `.claude/memory/project_licensing_pivot_2026_06.md`.
- [x] **19. Write audit logging logic** to `FactSubmissionAudit` on each submission *(Claude can write formula/flow)*. **Done 2026-05-11.** `usp_InsertSubmissionAudit` deployed with three-layer validation (NULL guard 51010 + 3 enum allow-lists 51011-51013 + email-format 51014 + LOWER normalization). Power Apps writes invoke it via the dot-stripped form `Assessment_Warehouse.dbouspInsertSubmissionAudit({...})`. Audit rows also written by `usp_UpsertReadingAssessment`, `usp_DeleteReadingAssessment`, `usp_UpsertStudentIPP`, and `usp_TriggerIngestCycle` on every state change.
- [ ] **20. Share Power Apps** directly with 5–10 pilot teachers *(Manual — Power Apps share dialog)*. Pilot uses direct sharing only — the Teams app catalog embed is deferred to full rollout (Step 27). **Status (2026-06-12)**: gated on the SharePoint entry pivot (share the lists-bound apps, NOT the SQL-bound app — sharing it would demand premium licenses per user). **Pilot includes school admins** (confirmed 2026-06-12) → both the Teacher Entry app and the admin port ship before sharing. Pilot timing ~mid-July (pivot ~4-7 wks from 2026-06-12); critical path = IT Entra app registration ([`docs/it-request-entra-bridge.md`](it-request-entra-bridge.md)).

---

## Phase 4: Pilot Testing (Weeks 7–8)
*Goal: 5–10 teachers successfully submit assessments, data is clean*

- [ ] **21. Deliver training session** for pilot teachers *(Manual)*
- [ ] **22. Monitor `FactSubmissionAudit`** for errors during UAT *(Claude can write monitoring queries)*
- [ ] **23. Fix blocking bugs** — data issues, connection errors, RLS gaps *(Claude can assist with SQL/formula fixes)*
- [ ] **24. Write post-pilot data quality report queries** *(Claude can generate)*
- [ ] **25. Document pilot feedback** and delta list for September *(Manual — with your input)*

---

## Phase 5: Full Rollout (July–September 2026)
*Goal: All schools, programs, and teachers on the platform*

- [ ] **26. Create Entra ID security groups**: `SG-Assessment-Teachers`, `SG-Assessment-SchoolAdmins`, `SG-Assessment-Regional` — populate from staff export *(Manual — Entra admin portal)*. Membership rules by warehouse `RoleCode` (translated from PS Group via `DimRole`):
  - `SG-Assessment-Teachers` → `Teacher`
  - `SG-Assessment-SchoolAdmins` → `Administrator` + `SpecialistTeacher` (both get school-level RLS via `vw_StaffSchoolAccess`; SpecialistTeacher additionally gets section-level via `FactSectionTeachers` if assigned)
  - `SG-Assessment-Regional` → `RegionalAnalyst`
  - **Excluded from all groups** (no PowerApp access at all): `ProvincialAnalyst` (DoE / Evaluation Services — confirmed 2026-04-29 they never authenticate to the app), `SupportStaff` (no student-data access by design). Rows still exist in `DimStaff` and `FactStaffAssignment` for audit, but these accounts must not appear in any of the three security groups above.
- [ ] **27. Embed app in Microsoft Teams** via Teams app catalog — full-rollout deployment to all staff, gated by the security groups from Step 26 *(Manual — Teams admin portal)*. Deferred out of the pilot, which uses direct Power Apps sharing (Step 20).
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
| Phase 3: Power Apps | 6 | 4 |
| Phase 4: Pilot Testing | 5 | 0 |
| Phase 5: Full Rollout | 11 | 0 |
| **Total** | **36** | **18** |

---

## Notes

- **Highest risk item**: Step 16 (Power Apps → Fabric SQL connection) — test this as early as possible
- **Hard deadline**: Steps 1–20 must be complete by June 2026 for pilot launch
- **Deferred to September**: Writing assessments, Power BI reports, automated ingestion, full SCD Type 2, security groups, Teams app catalog embed (pilot uses direct Power Apps sharing)
- **RLS approach**: Data-level filtering uses `USERPRINCIPALNAME()` matched against the teacher-of-record email in the PowerSchool section export — no security groups required for this. Groups are only needed at full rollout for managing app access across ~200 teachers.
- **Fabric Warehouse T-SQL limitations**: No `DEFAULT` constraints, no `PRIMARY KEY`/`FOREIGN KEY` in `CREATE TABLE`, no `NVARCHAR` (use `VARCHAR`), no `DATETIME` (use `DATETIME2(0)`), `DATETIME2` requires explicit precision 0–6, `IDENTITY` columns must be `BIGINT` not `INT`, `IDENTITY` takes no seed/increment parameters, `CREATE INDEX` not supported (columnstore is automatic). Data integrity is enforced through ETL procedures, not database constraints. FK relationships must be defined manually in the Power BI semantic model. Full reference in `/fabric-warehouse-sql` skill.
- **DimCalendar**: Original WHILE loop version is slow (~5+ min for 5844 rows). Rewritten as a single bulk INSERT using cross-join CTE — use the current file version.
- **Year-end close-out (deferred)**: Build a scheduled procedure that closes out sections, FactSectionTeachers triples, and FactEnrollment rows when a school year ends — independent of the regular ingest. The regular merge anti-join handles this *eventually* (when next year's data lands), but that leaves Jun–Aug with stale rosters surfacing in Power Apps. Driven by `DimTerm.SchoolYearEnd`. Tackle during/after Step 8 (merge procedures), before September rollout.
- **Ingest strategy A→B migration (pre-launch)**: MVP uses Strategy A — manual Lakehouse upload + `COPY INTO` in merge procs. Strategy B (Fabric Data Pipeline + Power Automate trigger) replaces this before September rollout — see Step 29. **Step 8 merge proc design must support both**: keep the CSV-loading step (`COPY INTO Stg_X FROM '...'`) decoupled from the merge logic itself so the Pipeline replacement is a layer-swap, not a rewrite. Decision recorded 2026-04-29.

### Left Off — 2026-06-12 (restyle DONE 7/7 + Pack B + LICENSING CRISIS → SharePoint-list pivot; $0-license constraint; session-infra overhaul)
- **Last completed step**: Step 18 build items — Direction B restyle validated on all 7 screens (waypoint kept: `powerapps/waypoints/`); Pack B Teacher filter built (`vw_StudentCohortTeachers` DEPLOYED); fixes: `ItemDisplayText` Coalesce restriction (precompute display columns), `FirstN(col, 0)` warning silencer, edit-mode z-order under pie padding.
- **In progress**: **ENTRY-LAYER PIVOT** ([`docs/sharepoint-entry-pivot.md`](sharepoint-entry-pivot.md)) — SQL connector is premium; teacher entry + admin screens rebind to SharePoint lists; app splits; **binding constraint: $0 per-user licensing**. Done this session: pivot spec, IT request draft ([`docs/it-request-entra-bridge.md`](it-request-entra-bridge.md)), site setup guide ([`docs/sharepoint-site-setup.md`](sharepoint-site-setup.md)), bridge views authored ([`sql/security/bridge_views.sql`](../sql/security/bridge_views.sql) — **NOT deployed**). Pinned for capacity review: Supabase migration analysis (`.claude/memory/project_licensing_pivot_2026_06.md`). Session infra: lean session-start, memory moved into repo (`.claude/memory/` + junction), machine-setup skill, waypoints convention.
- **Next action**: USER — create the SharePoint site per the setup guide and send me the URL; send the IT request (Entra app, `Sites.Selected`) — **critical path**; deploy `bridge_views.sql`; verify the Power Apps premium-trial expiry on your account. CLAUDE — bridge notebook (placeholder credentials), then app split + screen rebinding once the lists exist.
- **Blockers**: IT Entra app registration gates the bridge, which gates everything downstream. Pilot timing ~mid-July; pilot includes school admins.

### Left Off — 2026-06-10 (Direction B restyle: 4 more screens ported + tint SQL DEPLOYED + scrStudentData cohort filters; only scrRosterGrid left)
- **Landed this session**: scrIPP polish (pointer overlays, sort CTA, editable-after-confirm IPP toggle); **scrWindowSelect** + **scrGroupSelect** (full rewrites, per-row pointer overlays, divide-by-zero fix via `Max(Coalesce(...),1)` denominator); **scrStudentDetail** (verbatim tint column); **scrStudentData** donut rebuild + the new filter system.
- **SQL deployed (2026-06-10)**: `migrate_DimAchievementLevel_add_tint.sql` → `seed_DimAchievementLevel.sql` → `vw_StudentCohort` (+`MostRecentAchievementHexColorTint`) → `vw_StudentAssessmentHistory` (+`AchievementHexColorTint`), 4 separate executions. Row tints now live.
- **scrStudentData cohort filters**: centralized `colCohortFiltered` (gallery + charts + count read it); multi-select Homeroom / Program / School (regional-analyst-only) / Achievement (all); collapsible filter bar (`gblFiltersExpanded`, default collapsed) with count + "Reset filters" + Show/Hide toggle in the blue header; pie tracks the gallery band (half-offset) on collapse. Patterns saved to `/power-apps-canvas-build` §7g.
- **Donut insight**: native `PieChart@2.3.0` renders the pie at ~58% of its box → oversize the box, overlap later-z-order neighbours, fake the hole with a white `Circle@2.3.0`, custom legend gallery for percent+count.
- **In progress**: nothing half-built — scrStudentData packs clean and is locked per user ("good enough for government work").
- **Next action**: **port scrRosterGrid** (last + most complex — roster grid, per-row reading-level combo, inline IPP gating, dirty tracking, Save + per-row Delete, unsaved/delete modals); pre-scrub Bugs A/B/C; visual-only except approved changes. Then **Pack B** (Teacher filter: `vw_StudentCohort` teacher-exposure SQL + gated multi-select) and optional **Pack C** (Assessment-Window as-of-window recompute).
- **Housekeeping**: a stray `powerapps/from-claude-design/GitHubDesktopSetup-x64.exe` is untracked — gitignore or delete it; do NOT commit.
- **Blockers**: None.

### Left Off — 2026-06-09 (Direction B visual restyle port IN PROGRESS — scrLanding done+locked, scrIPP audited & next; SQL restyle staged not deployed; NO commit yet by user directive)
- **Session goal**: port the **"Direction B — Edge-to-Edge" visual restyle** (brand cyan `#0092C9`, white edge-to-edge content panel under a 52px header band) into the live `powerapps/sources/Src/` tree, **screen by screen, simple→complex**, squashing bugs on the simple screens and pre-auditing the complex ones for the known bug signatures BEFORE packing them (so we don't chase many bugs at once on a big screen). Visual-only restyle — data model, navigation, all Power Fx/proc calls unchanged.
- **Where the restyle source lives**: [`powerapps/from-claude-design/handoff/`](../powerapps/from-claude-design/handoff/) — produced by Claude Design. `handoff/powerapps_yaml/` is the **authoritative "what ships" set** (App, _EditorState + 7 restyled screens + `_tokens-and-notes.md` token map); `handoff/README.md` = per-screen spec; `handoff/prototype/` = HTML/CSS fidelity reference (do NOT port HTML). The loose `powerapps/from-claude-design/*.pa.yaml` are an EARLIER extract — superseded by the handoff set. `scrIngest` is intentionally NOT restyled (orphaned — Power Automate ingest path is dead; kept as the original stub).
- **POC already done**: Design's raw scrLanding packed cleanly into a throwaway `cd-test.msapp` (temp source folder, since deleted) → proved Claude Design emits valid `pa.yaml`. The only fallout was the text-clip bug below.
- **THREE recurring bug signatures — pre-check EVERY screen for these before packing** (the Design handoff has all three throughout):
  - **Bug A (text clip)**: labels with multi-line text + a fixed/too-small `Height` clip the overflow. This app has NO `AutoHeight` anywhere (build-skill §7b convention = explicit heights). Fix = give the label an explicit `Height` sized to fit / derived from its container.
  - **Bug B (load ghosting)**: chrome/overlay controls with no `Visible` gate render over the "Loading…" label before the screen's `gbl*Loaded` flag flips. Fix = gate ALL non-header content controls on the screen's loaded flag (keep only the cyan header band's back-icon + title always-on).
  - **Bug C (PA2108 — `Fill` on `ModernButton@1.0.0`)**: the handoff brands modern buttons with `Fill`/`HoverFill`/`PressedFill`, which modern buttons DON'T support (they take bg from theme) → "Unknown property 'Fill'" at Studio open (pack still succeeds — `pac pack` does NOT validate this; only Studio open does). Fix = convert branded buttons to `Classic/Button@2.2.0` (supports Fill/HoverFill/PressedFill/HoverColor/PressedColor; drop `Radius*` — invalid on classic, so buttons go square, matching scrLanding). `Color` and `Radius*` ARE valid on ModernButton; only `Fill` is the trap.
- **scrLanding — DONE & LOCKED** ([scrLanding.pa.yaml](../powerapps/sources/Src/scrLanding.pa.yaml)). Ported the 3-card layout (Student Data → scrStudentData / Data Entry → scrWindowSelect / **Student IPPs → scrIPP**; the old regional-analyst "PS Data Ingest" card was removed — ingest orphaned). **Resize fix (your spec: grow to fit text, cap ~½ height for a future 2nd row)**: card `Height: =Max(230, (Parent.Height - 160) / 2)`; description labels `Height: =<card>.Height - 160`. **Ghosting fix**: all 15 card sub-controls gated `Visible: =gblLandingLoaded`. Verified in Studio via cd-test — both bugs gone.
- **scrIPP — PORTED, pending final visual lock** (awaiting Studio confirm of filter+sort). Applied: Bug B gating (pill/subtitle/6 headers/both save buttons on `=gblIPPLoaded`); Bug C (all 6 buttons → `Classic/Button@2.2.0`); **responsive grid** (fixed-min + proportional-growth, ~756px template floor, action cluster right-anchored, headers track cells); **Writing filtered out** (`Filter(vw_StudentIPP, Subject = "Reading")` at load + post-save reload — app-side, reversible for full rollout); **click-to-sort headers** (`gblIPPSortCol`/`gblIPPSortAsc`, `SortByColumns` switch in gallery `Items`; indicator = a separate always-present arrow label per header, grey `↕` inactive / blue `↑`/`↓` active, neutral title — avoids the 2-line wrap that an inline-only-when-active arrow caused; Grade widened 52→68, Homeroom 88→104, arrows inline-after-title). Logic parity vs live confirmed identical (OnVisible, `dbouspUpsertStudentIPP`, `colDirtyIPP`/`colRawIPP`, `vw_StudentIPP`).
- **FIRST ACTION NEXT SESSION**: user verifies scrIPP in Studio tomorrow AM (Writing gone; sort works both directions; arrow spacing/active-color clean; responsive grid holds wide+narrow; save/modal intact — nudge any off arrow offset). Then port **scrWindowSelect** (pre-scrub Bugs A/B/C). Then continue the port order; deploy staged `HexColorTint` SQL only after the YAML is validated.
- **Remaining port order (simple→complex)**: scrIPP (next) → scrWindowSelect (handoff calls it the cleanest pure-restyle ref) → scrGroupSelect → scrStudentDetail → scrStudentData → **scrRosterGrid** (most complex, last). App.pa.yaml + _EditorState copied unchanged.
- **SQL restyle — STAGED IN SOURCE, NOT DEPLOYED** (deploy only after the YAML is validated): [`migrate_DimAchievementLevel_add_tint.sql`](../sql/scripts/migrate_DimAchievementLevel_add_tint.sql) (adds nullable `HexColorTint`) → re-run [`seed_DimAchievementLevel.sql`](../sql/scripts/seed_DimAchievementLevel.sql) (new solid+tint palette) → redeploy [`vw_StudentCohort.sql`](../sql/security/vw_StudentCohort.sql) (+`MostRecentAchievementHexColorTint`) → [`vw_StudentAssessmentHistory.sql`](../sql/security/vw_StudentAssessmentHistory.sql) (+`AchievementHexColorTint`). Run as 4 SEPARATE executions (Fabric batch-parses; same-batch ref to new column = "Invalid column name"). Hex values match the handoff token map exactly.
- **Also uncommitted**: date-typo fix (2025→2026) across CLAUDE.md, implementation-plan.md, and the 6 `.claude`/`.github` skill files.
- **Workflow**: `pac canvas pack --sources powerapps\sources --msapp "powerapps\Student Data Staff Portal.cd-test.msapp" --overwrite` (pac at `C:\Users\jeffrey.raine\AppData\Local\Microsoft\PowerAppsCli\Microsoft.PowerApps.CLI.2.7.4\tools\pac.exe`). The `.cd-test.msapp` is gitignored; canonical `Student Data Staff Portal.msapp` + sources baseline stay untouched until validated. **NO git commit until session wrap** (user directive 2026-06-09).
- **Followups queued (revisit AFTER all screens are running)**:
  1. **Add `GradeOrder` to `vw_StudentIPP`** so the scrIPP Grade-column sort orders correctly (`P, 1, 2, …` instead of lexicographic `1, 2, 3, …, P`). SQL view change — batch it with the other staged SQL once the YAML port is fully validated. Currently Grade sort is lexicographic.
  2. **Pilot question — clickable column headers discoverability**: scrIPP (and other gallery screens) use ▲/▼ + active-color to signal sortable headers, but Power Apps labels show no hand cursor. ASK pilot teachers during UAT whether the headers read as clickable; if not, add transparent `Classic/Button` overlays (the cohort name-link pointer pattern) for a hand cursor. Revisit at pilot, not now.
- **Blockers**: None.

### Left Off — 2026-06-08 (scrStudentDetail v1 complete; PowerSchool report-spec doc delivered; loaders staged for CSV but NOT deployed; Teams embed renumbered to Step 27)
- **scrStudentDetail v1 complete**: line chart now plots **reading level (`LevelOrder`)** not delta, title "Reading level over time", Y-axis pinned `YAxisMin=0`/`YAxisMax=31` (user-set in Studio, lifted into source). Timeline gallery + chart share vertical space 50/50 (`(Parent.Height - 252) / 2` each). Removed the redundant "most recent reading" subheading (folded IPP status into the meta line); timeline sorts most-recent-first while the chart runs oldest→newest. Verified present in Studio.
- **PowerSchool report specifications doc delivered** — new [`docs/powerschool-report-specifications.md`](powerschool-report-specifications.md): admin-facing spec for the 5 user-run SQL reports (full-rollout scope, current-school-year filters). Authored from `export-procedures.md` + `powerschool-field-mapping.md` + the `Stg_*.sql` column orders (COPY INTO is positional). A conversion prompt was given to the user for Word/PDF via general Claude.
- **Loaders staged for sqlReport CSV but NOT deployed**: the 5 `usp_Load*Staging` procs were updated in source (comma/quote/CRLF, `'*'` wildcard) but are **not applied to the live warehouse** — the pilot keeps running on the deployed TAB ingest. Deploy only at cutover, together with the new SQL reports. Headers say so.
- **Teams embed renumbered**: moved Step 20 (Phase 3) → **Step 27 (Phase 5)**; pilot is **direct Power Apps sharing only** (Step 20). Phase 4 → 21-25; security groups → 26; Steps 28-36 unchanged.
- **First action next session**: build the **scrIPP entry button on scrLanding** (gated on the caller having IPP rows in scope). Then admin/analyst-only cohort filters (likely a SQL view extension), then visual polish.
- **Do NOT deploy the CSV loaders** or regenerate test data as CSV until the PS SQL reports are authored and a cutover is explicitly scheduled.
- **Blockers**: None.

### Left Off — 2026-06-05 (scrStudentDetail v1 built incl. line chart; line chart NOT yet verified in Studio)
- **Last completed**: scrStudentDetail v1 — header with prev/next cohort nav ("Student n of m") over the *filtered* cohort, info strip (grade/program/school/homeroom + most-recent reading + IPP status), chronological assessment timeline gallery (Window · Date · Level · Difference · Achievement, achievement-tinted rows), and a `LineChart@2.3.0` bottom band plotting `ReadingDelta` over time (single series, reactive `Items` so it follows prev/next). scrStudentData: student names now a blue/underlined hyperlink cue + hint label + transparent `Classic/Button@2.2.0` overlay (`btnNameLink`) for the hand cursor; single grade dropdown replaced by Grade min/max **range** filter on `GradeOrder`; filter globals now `Coalesce`-seeded so selections persist across navigation (also fixed a latent Gender/Self-ID display-vs-filter desync). Skill `power-apps-canvas-build.md` updated (§3g pointer-cursor overlay, §3h Coalesce filter persistence, `Classic/Button@2.2.0` + `LineChart@2.3.0` in §4, §5 registry refreshed) and mirrored to `.github/skills/`.
- **In progress**: scrStudentDetail packed to dev.msapp but **the line chart is not yet verified in Studio** — everything else on the screen is logically wired but unconfirmed end-to-end this session.
- **First action next session**:
  1. Open `dev.msapp` in Studio, open a student from scrStudentData, and confirm the bottom-band line chart renders `ReadingDelta` over time (single point for single-assessment students, a real line for any student with >1 assessment, hidden for 0-assessment students). Re-verify the timeline table, prev/next cohort nav, pointer-cursor overlay, grade-range filter, and filter persistence while there.
  2. Optionally enter a 2nd-window reading assessment for one student via scrRosterGrid to see a multi-point line.
- **Then next priorities (in order)**: scrIPP entry button on scrLanding (gated on IPP rows in scope); admin/analyst-only cohort filters (teacher/course/section/homeroom for admin, school for analyst — likely a SQL view extension); visual polish across all screens; Step 20 (Teams embed) + Step 21 (share with pilot teachers).
- **Housekeeping note**: `sql/security/vw_StudentCohort.sql` was found truncated to 1 byte in the working tree (uncommitted) and restored from HEAD; deployed view unaffected. Watch for any recurrence of file truncation.
- **Blockers**: None.

### Left Off — 2026-05-28 (scrStudentData cohort polished; charts rendering correctly; scrStudentDetail still next)
- **Last completed**: scrStudentData cohort UX rebuilt end-to-end. Half-width gallery (4 columns, school-abbreviation cell, 28px row), pie chart right (slice = %, legend = category names), 6-month clustered bar chart bottom with 4 series (pink/yellow/light green/bright green). Reactive filters via hidden `btnRefreshCharts` — Grade/Gender/Self-ID changes now drive both pie + bar. Stale-data hardening across all 5 SQL-backed screens: `Clear()` before `ClearCollect`, `Gallery.Visible = gblXxxLoaded` so no stale ghost on screen-revisit. New `power-apps-canvas-build.md` skill consolidates all Power Apps gotchas + working patterns.
- **In progress**: cohort screen feature-complete. scrStudentDetail still a stub.
- **First action next session**:
  1. Open dev.msapp, verify cohort screen still renders correctly after any latest cohort data changes.
  2. **Build scrStudentDetail v1** — biggest remaining piece. Three timelines (reading level / achievement / difference) over time for one student, with left/right arrow navigation through the filtered cohort. Data already available via `vw_StudentAssessmentHistory` + `gblSelectedStudent` (set on cohort gallery tap).
- **Then next priorities (in order)**:
  1. scrIPP entry button on scrLanding (small build, gated on IPP rows in user's scope)
  2. Admin/analyst-only cohort filters (teacher/course/section/homeroom for admin; school for analyst) — likely needs SQL view extension
  3. Visual polish across all screens
  4. Step 20: Teams embed
  5. Step 21: Share with pilot teachers
- **Memory adds/updates this session**:
  - NEW: `feedback_percent_decimal_precision` — 1 dec on charts, 2 dec on tables. Standing convention.
  - UPDATED: `feedback_powerfx_identifier_column_args` — GroupBy aggregation name is ALSO an identifier, no exception.
  - UPDATED: `feedback_powerapps_data_source_refresh` — change-type-specific (additive doesn't need refresh; renames/type-changes do).
  - UPDATED: `project_powerapps_loading_state_pattern` — Clear() + Gallery.Visible added to canonical pattern.
- **Skill adds/updates**:
  - NEW: `power-apps-canvas-build.md` — full Power Apps reference for this project.
  - UPDATED: `session-wrap.md` — added power-apps-canvas-build to skill review table; added Step 3 substeps for description-staleness check + Progress Summary update.
- **Major learning**: `NumberOfSeries: =N` is MANDATORY on multi-series Bar/Line/Column charts. Without it, only Series1 renders. Documented in skill.
- **Test data state at EOD**: 17 chart-eligible students in cohort, 9 with reading assessments entered (1 NotYetMeeting, 1 Approaching, 4 Meeting, 3 Exceeding). Pie + clustered bar render correctly matching this distribution.
- **Followups queued**:
  - True carry-forward bar chart semantics (multi-assessment students) — current formula uses MostRecent which works for single-assessment test data; needs multi-assessment test data to verify the deeper formula.
  - Stacked bar chart variant — `Stacked: =true` rejected (PA2108); need to find right property if user wants stacked over clustered.
- **Blockers**: None.

### Left Off — 2026-05-27 (scrStudentData cohort scaffold + 2 new SQL views shipped; scrStudentDetail next)
- **Last completed**: `vw_StudentCohort` + `vw_StudentAssessmentHistory` deployed and smoke-tested. scrStudentData cohort screen built end-to-end (functional in Studio): header, OnVisible computes 8 collections incl. `colPieData` + `colBarData`, 5 filter ModernComboboxes (school year/grade/gender/self-ID African/self-ID Indigenous + reset), student gallery with color-tinted rows + 7 column headers + ChevronRight drill, PieChart bound to `colPieData`, ColumnChart bound to `colBarData` (single series). scrStudentDetail stub created so the gallery's Navigate resolves at pack time.
- **In progress**: scrStudentData scaffold is functional but unverified end-to-end with real assessment data (FactAssessmentReading is empty after the earlier test reset). Charts will render empty until reading assessments are entered via scrRosterGrid.
- **First action next session**:
  1. Open `dev.msapp` in Studio. Verify scrStudentData renders: 5 dropdowns populated, gallery shows 10 students with row-tinting, charts present but empty.
  2. Enter test reading assessments via scrRosterGrid so the cohort charts have data to display.
  3. Re-open scrStudentData; verify PieChart shows non-zero achievement distribution and ColumnChart shows per-window counts.
  4. Begin building **scrStudentDetail v1**: timelines for reading level / achievement / difference + left/right student-navigation arrows. Use `gblSelectedStudent` (already set on cohort gallery tap) + filter `colStudentHistory` by StudentKey.
- **Then next priorities (in order)**:
  1. scrStudentDetail v1 (timelines + arrows) — biggest remaining build
  2. Convert ColumnChart1 from single-series to clustered (4 series, one per achievement level)
  3. Add scrIPP button to scrLanding (gated on caller having any IPP rows in scope)
  4. Admin-only filters (teacher/course/section/homeroom) + analyst-only filter (school) on cohort
  5. Visual polish across all screens
  6. Step 20: embed in Teams; Step 21: share with pilot teachers
- **Design decisions locked in today**:
  - scrGroupSelect red alert DROPPED — IPP enforcement happens at scrRosterGrid; duplicate alert would be noise.
  - IPP students in cohort gallery: **show plain** (no filter, no badge). Excluded only from chart aggregations via `IsChartEligibleReading`.
  - "Most recent" semantics for pie chart = lifetime-latest per student, NOT bounded by selected school year.
- **Memory adds this session**: `feedback_powerfx_identifier_column_args` — `ShowColumns / RenameColumns / GroupBy` take bare identifiers (NOT quoted strings) for column-name args in this app's Power Fx version, including the new aggregation column name in GroupBy. User corrected me twice this session — flagged as a mandatory pre-flight before yielding code that touches these functions.
- **Test data state at EOD**: DimStudent 21 (unchanged), FactStudentIPP 26 NULL placeholders, FactAssessmentReading 0, vw_StudentCohort returns 10 rows for caller. Charts will be empty until assessments are entered.
- **Blockers**: None.

### Left Off — 2026-05-26 (scrIPP shipped + app branded + automated ingest deferred to post-MVP)
- **Last completed**: scrIPP screen built end-to-end with batched save pattern. App-wide branding applied (org #0092C9 + Lato + white content panels). Responsive sizing philosophy established. FactStudentIPP + DimAchievementLevel + usp_UpsertStudentIPP + vw_StudentIPP all deployed and verified clean. usp_MergeStudent updated with Step 6 IPP reconciliation (26 NULL placeholder rows generated for test students).
- **In progress (NOT YET TESTED)**: scrIPP packed to dev.msapp but not yet validated end-to-end in Studio. The Power Fx formula tree has been pivoted from a wide-format GroupBy/AddColumns design (which produced cascading red squigglies in Studio for unknown reasons) to a long-format direct-iteration design (one gallery row per IPP cell, 26 rows for the test data).
- **First action next session**:
  1. Open `dev.msapp` in Studio. Play from scrIPP directly.
  2. Verify 26 IPP cells render with vertical centering, Yes/No buttons visible on NULL rows, colors correct
  3. Flip a few Yes/No values, watch dirty counter + blue pending labels
  4. Save, verify FactStudentIPP rows transition with `ChangedBy = jeffrey.raine@tcrce.ca`
  5. Back arrow with dirty changes triggers unsaved-changes modal
- **Then next build priorities (in order)**:
  1. Add scrIPP button to scrLanding (so users don't need Studio-Play to reach it)
  2. scrRosterGrid additions: expected level beside dropdown, color-code current selection vs DimAchievementLevel, inline IPP gating control when NULL, "IPP" display when IsIPP=1
  3. scrGroupSelect red alert for unresolved IPP in any section
  4. scrStudentData v1 — biggest remaining piece. Per-student roster (6 pulls), deltas, color coding, demographic slicers for ALL roles, admin/analyst filters, role-based data scoping
- **Scope reframe (locked in this session)**: MVP must demonstrate ALL THREE roles (teacher / admin / regional analyst) functioning, not just teacher-focused. Demographic slicers + admin/analyst filters are IN MVP scope (user explicitly corrected me when I tried to defer them).
- **Major architectural pivot (post-MVP)**: Automated ingest is fully deferred to post-MVP. Pilot will use manual Lakehouse uploads + manual `usp_RunFullIngestCycle`. Decision tree captured in 2026-05-26 memory section. Future architecture is Dataflow Gen 2 (verified working with private channel SharePoint) writing direct to Stg_ tables, with a refactored orchestrator (split into `usp_RunFullIngestCycle` for manual file path + new `usp_RunMergesOnly` for Dataflow path).
- **Capacity right-sizing tracking begins now**: F8 currently at 0.36% avg / 0.97% peak utilization. F2 (~$8700/yr savings) is the post-grant target. April-May 2026 review will make the SKU decision. Memory: `project_capacity_rightsizing_intent`.
- **Behavioral feedback memories added this session**: `feedback_no_unilateral_scope_decisions` and `feedback_no_agency_between_turns`. Read both at next session-start.
- **Blockers**: None. SQL backbone solid, scrIPP packed, just needs in-Studio verification.

### Left Off — 2026-05-22 (scrRosterGrid Save+Delete shipped; scrIngest scaffolded; architecture pivoted to SharePoint-triggered ingest; blocked on IT for Entra app)
- **First action next session: check IT response on the Entra app registration.** Request was sent today for `sp-assessment-onelake-writer` Entra app + workspace Contributor grant on `Regional_Data_Portal`. When IT returns Client ID + secret, build the file-arrival Power Automate flow per the architecture in Session 2026-05-22 memory section (project_assessment_platform). Until then, useful parallel work:
  - Build real scrIngest screen UI (status panel with 5 topic last-upload timestamps from SharePoint; "Run ingest manually" button calling `usp_TriggerIngestCycle` directly; recent FactSubmissionAudit panel)
  - Pseudo-code the WDL expressions for the file-arrival flow steps
- **Today's work**:
  - **scrRosterGrid Save 51012 RESOLVED** — root cause was stale connector schema cache (yesterday's BIGINT→VARCHAR(20) param migration); fix was data-source remove+re-add in Studio. Validates `feedback_powerapps_data_source_refresh` from yesterday.
  - **Reading assessment DELETE capability deployed** — new [sql/procedures/usp_DeleteReadingAssessment.sql](../sql/procedures/usp_DeleteReadingAssessment.sql) (hard DELETE + audit-row capture of prior values, 5 THROW codes incl. new 51018), per-row trash icon + screen-level delete confirmation modal in scrRosterGrid. End-to-end audit-trail reconciliation verified across 4 inserts + 3 deletes.
  - **scrRosterGrid UX polish** — cmbNewLevel DefaultSelectedItems=Blank, Reset on existing-value selection, InputTextPlaceholder, post-save Refresh+Reset+ClearCollect cascade, same Refresh on OnVisible for fresh data on revisit.
  - **scrIngest scaffolding (Regional Analyst self-service ingest path)** — [sql/procedures/usp_TriggerIngestCycle.sql](../sql/procedures/usp_TriggerIngestCycle.sql) wraps the orchestrator behind a `RegionalAnalyst` AccessLevel gate (new THROW 51033); `gblIsRegionalAnalyst` global in App.OnStart; "PS Data Ingest" button on scrLanding visible only to regional analysts; scrIngest stub screen.
  - **Loading-state pattern on scrLanding** — `gblLandingLoaded` bookends App.OnStart; all buttons gated on flag; loading label appears while async role lookups resolve. Eliminates the button-flash race on app start.
  - **Architecture pivot — Power Automate connector limitations discovered.** Microsoft's "HTTP With Microsoft Entra ID (preauthorized)" connector base64-encodes all request bodies (documented as "by design — only text-based payloads supported"). Incompatible with OneLake ADLS Gen2 raw binary requirement. Burned significant time iterating through connector options before finding the documented limitation. New feedback memory captures this.
  - **Architecture pivot — chosen design.** Analysts upload to private Teams channel SharePoint library (`Leadership Team` → `-Data System Admin` → `Documents/file-upload/{topic}/`); Power Automate flow detects new files, copies to OneLake via service principal, gates ingest behind all-5-fresh + 8h-window + newer-than-last-ingest checks, then fires `usp_TriggerIngestCycle`.
  - **Configuration locked in**: SharePoint host `tcrcens.sharepoint.com`; freshness window 8 hours; both gates active; service principal name `sp-assessment-onelake-writer`.
  - **Self-test override in DimStaff** — reverted principal.test impersonation; added jeffrey.raine@tcrce.ca as RegionalAnalyst row (StaffKey 4989988387126509569). Replaced automatically on real-PS ingest (user's PS Group 40 → RoleCode='RegionalAnalyst').
  - **IT request sent**: comprehensive package covering Entra app registration steps, security scope clarifications, PIIDPA posture, and rationale for SP-vs-delegated-user (with Microsoft docs reference).
  - **Mid-session checkpoint commit landed**: `bd363c6` "Checkpoint: scrRosterGrid Save + Delete working end-to-end (Step 18 functional)".
- **Memory adds this session** (1 new):
  - `feedback_webcontents_no_binary` — Power Automate's webcontents connector doesn't support binary uploads (Microsoft documented limitation). Don't use it for OneLake writes.
- **Test data state at EOD**:
  - DimStaff: principal.test@tcrce.ca restored (Forest Walnut, Administrator at school 0167); jeffrey.raine@tcrce.ca added as RegionalAnalyst override (will get replaced on real ingest)
  - FactAssessmentReading: 1 row (Tau Test 9100000019, FR window, level 13, delta -11) from prior reconciliation testing
  - FactSubmissionAudit: today's PowerApps action rows (3 deletes + 4 upserts during audit-trail verification)
- **Blockers**: IT ticket open for Entra app `sp-assessment-onelake-writer` + workspace Contributor grant. Can't build the file-arrival flow until SP credentials are in hand.

### Left Off — 2026-05-21 (All 5 screens built; scrRosterGrid Save blocked by THROW 51012)
- **First action next session: debug the scrRosterGrid Save error.** Proc throws `51012 @AssessmentWindowID does not resolve to an active DimAssessmentWindow row` even though the row exists with ActiveFlag=1 and Power Apps Label.Text shows the exact 19-digit value. Two diagnostic paths in order:
  1. **Power Apps Monitor** — open Monitor, trigger Save, inspect the literal payload sent to the connector for `AssessmentWindowID`. Determines whether Power Apps lost precision en route to the connector.
  2. **Proc-side logging fallback** — add a debug INSERT to FactSubmissionAudit at the top of usp_UpsertReadingAssessment logging received params, redeploy, trigger Save, query audit table.
- **Today's work**:
  - **scrWindowSelect verified** with FR window for impersonated 0167 principal. Initial empty was due to bootstrap missing vw_UserAssessmentWindows (only the DimAssessmentWindow table was added); fixed by adding the view.
  - **scrGroupSelect built** (Path-B chunks 03a-d) — 3 group rows show for FR window.
  - **scrRosterGrid built** (Path-B chunks 04a-g) — gallery, ComboBox, dirty tracking, modal — all working except Save (the 51012 error).
  - **Loading state pattern** ([project_powerapps_loading_state_pattern](../../../Users/jeffrey.raine/.claude/projects/c--Git-Repos-Assessment-Data/memory/project_powerapps_loading_state_pattern.md)) applied to scrWindowSelect, scrGroupSelect, scrRosterGrid.
  - **BIGINT precision cast migration** — 3 views' BIGINT IDENTITY surrogate keys cast to VARCHAR(20) for Power Fx safe range. [sql/scripts/migrate_views_AssessmentWindowID_VARCHAR.sql](../sql/scripts/migrate_views_AssessmentWindowID_VARCHAR.sql).
  - **vw_DimReadingScale wrapper view** created (table-level cast not possible; wrapper view exposes ReadingScaleID as VARCHAR(20)). [sql/security/vw_DimReadingScale.sql](../sql/security/vw_DimReadingScale.sql).
  - **usp_UpsertReadingAssessment params flipped to VARCHAR(20)** — `@AssessmentWindowID` + `@ReadingScaleID`. Internal CAST to BIGINT locals. [sql/scripts/migrate_scrRosterGrid_prereqs.sql](../sql/scripts/migrate_scrRosterGrid_prereqs.sql).
  - **usp_UpsertReadingAssessment smoke-tested end-to-end** — Gamma (StudentNumber 9100000003) got FR level 15 entry, ReadingDelta computed correctly as +6, audit row Accepted, INSERT path proven.
  - **ScaleSystem column added to vw_UserAssessmentWindows** — original view never exposed it; cmbNewLevel filter needed it. [sql/scripts/migrate_vw_UserAssessmentWindows_add_ScaleSystem.sql](../sql/scripts/migrate_vw_UserAssessmentWindows_add_ScaleSystem.sql).
- **Memory adds this session** (5 new):
  - `feedback_powerapps_unique_control_names` — control names must be unique app-wide.
  - `project_powerapps_bigint_precision` — Power Fx 16-digit limit vs BIGINT IDENTITY 19-digit values.
  - `project_powerapps_loading_state_pattern` — ClearCollect + loaded flag pattern.
  - `feedback_powerapps_forall_no_set` — `Set()` blocked inside ForAll, use Collect; also covers scope ambiguity inside nested calls.
  - `feedback_powerapps_data_source_refresh` — after SQL schema changes, remove + re-add the data source is REQUIRED, not optional.
- **Memory updates this session** (4 existing):
  - `feedback_no_wrap_prompts` — added "break / pause / stop" coverage.
  - `feedback_file_links_in_instructions` — N+1 rule for line ranges.
  - `feedback_powerapps_formula_contexts` — `|` block scalar for formulas containing `{...}` or `: `.
  - `project_powerapps_yaml_templates` — Modern control property gotchas + **proc invocation form CORRECTED to dot-stripped** (`Assessment_Warehouse.dbouspXY`).
- **Test data state at EOD**: same as 2026-05-13 + 1 FactAssessmentReading row from smoke test (Gamma's FR level 15) + scratch `usp_TestVarcharBigint` cleaned up. Impersonation may still be active in DimStaff — revert when convenient.
- **Pending stray artifacts in powerapps/**: `Student Data Staff Portal.UpdatedConnections.msapp`, `Student Data Staff Portal.vw_DimReadingScale Added.msapp` — both were one-time refresh files from the user, can be deleted; sources/ tree has the final connection blob already.
- **Blockers**: scrRosterGrid Save error (above). Once resolved, MVP is feature-complete and ready for visual polish + Teams embedding + pilot UAT.

### Left Off — 2026-05-20 (VS Code YAML workflow proven; scrLanding + scrWindowSelect functional)
- **First action next session: verify scrWindowSelect gallery binds real data.** Quick test:
  1. Impersonate school 0167 principal: `UPDATE DimStaff SET Email = 'jeffrey.raine@tcrce.ca' WHERE LOWER(Email) = LOWER('principal.test@tcrce.ca') AND IsCurrent = 1;`
  2. Pack sources if stale: `pac canvas pack --sources "powerapps\sources" --msapp "powerapps\Student Data Staff Portal.dev.msapp" --overwrite`
  3. Open [powerapps/Student Data Staff Portal.dev.msapp](../powerapps/Student Data Staff Portal.dev.msapp) in Studio.
  4. Run app: scrLanding → Data Entry → scrWindowSelect. Confirm French Reading window appears with the composed subtitle.
  5. Tap row → should set `gblSelectedWindow` and navigate to scrGroupSelect (still has leftover placeholder).
  6. Revert impersonation.
- **Today's work**:
  - **Roundtrip sanity test PASSED** — `pac canvas pack` followed by Studio open succeeded.
  - **App.OnStart deployed** via YAML edit. Final formula: `Set(gblIsAdminOrAnalyst, !IsBlank(LookUp(DimStaff, Email = Lower(User().Email) And IsCurrent = true And AccessLevel <> Blank())))` — delegation-clean.
  - **scrLanding functional**: btnStudentData + btnDataEntry, both navigate correctly.
  - **scrStudentData stub**: btnBackToLanding only.
  - **Tooling-test round-trip** with user-added Label/Gallery/ComboBox/Icon controls → learned all control templates. Captured in new memory `project_powerapps_yaml_templates.md`.
  - **scrWindowSelect functional**: icoBack + lblTitle + galWindows (bound to vw_UserAssessmentWindows) + lblEmpty. Gallery has Title1 bound to WindowName, Subtitle1 to composed AssessmentType/Grades/Status string. OnSelect sets gblSelectedWindow and navigates.
  - **Workspace hygiene**: powerapps/.gitignore added (excludes dev/roundtrip/tooling test .msapp files).
- **Mistakes I made today** (now captured as feedback memories):
  - Used `'[dbo].[DimStaff]'` for the OnStart LookUp; the Data panel actually shows DimStaff bare. Fixed.
  - Provided `=Set(...)` formula for the user to paste into Studio's formula bar; the `=` belongs only in YAML files. Fixed; saved feedback memory.
  - Dictated old desktop-Studio menu paths (File → Open, View → Variables). Modern web Studio is different; I shouldn't be navigating the UI for the user. Saved feedback memory.
- **Pending next session**:
  - Verify scrWindowSelect (above) — confirms data binding works.
  - Build scrGroupSelect (chunks/03 workbook, Path-B only).
  - Build scrRosterGrid (chunks/04, biggest screen — ~7 chunks of formulas).
  - After functions work, visual polish in Studio.
  - Pilot teacher training.
- **Blockers**: None. Architecture settled; remaining work is implementation.

### Left Off — 2026-05-13 (Step 18 SQL prereqs DONE end-to-end; Power Apps build path pivoted to VS Code YAML)
- **🚨 First thing next session: roundtrip sanity test.** Pack the current `powerapps/sources/` back to a `.msapp` with no edits, re-import into Studio, confirm the 5 screens + 6 data sources all load. This catches any unpack-side issues BEFORE I start adding controls and formulas. Command:
  ```powershell
  & "C:\Users\jeffrey.raine\AppData\Local\Microsoft\PowerAppsCli\Microsoft.PowerApps.CLI.2.7.4\tools\pac.exe" canvas pack `
    --sources "c:\Git-Repos\Assessment-Data\powerapps\sources" `
    --msapp "c:\Git-Repos\Assessment-Data\powerapps\Student Data Staff Portal.roundtrip.msapp"
  ```
  Then in Studio: File → Open → Browse → pick the `.roundtrip.msapp`. If it opens with the 5 named screens, each with a ModernButton, and the 6 data sources still wired, the workflow is proven. Only then start editing YAML.
- **Last completed steps**: Step 18 prereqs #1-#7 all DONE end-to-end:
  1. ✅ `usp_MergeStudent` translation: PS `grade_level=13` → `'RG'` (Returning Graduate). Phi synthetic student added to test dummies as `9100000021`; full ingest cycle re-ran clean.
  2. ✅ `DimAssessmentWindow` v2 migration (drop `AppliesTo` + `IsCurrentWindow`, rename `ProgramCode` → `ProgramFamily`, add `ScaleSystem`, tighten `MinGrade`/`MaxGrade` to NOT NULL).
  3. ✅ `vw_UserAssessmentWindows` deployed — role-branched + historical-roster reconciliation per `project_historical_roster_reconciliation` memory.
  4. ✅ `vw_TeacherGroups` deployed — homeroom for PP-9 students, section for 10-12 + RG.
  5. ✅ `vw_TeacherRoster` deployed — one row per (window, group, student) with existing assessment.
  6. ✅ `usp_UpsertReadingAssessment` deployed — 3-layer validation per `project_submission_validation_strategy` memory (12 THROW codes: 51001 safety net, 51010-51017 input validation, 51030-51032 permission). ReadingDelta computation via DimReadingBenchmark + dominant-month rule. No OUTPUT clause. StudentKey/AssessmentDate frozen on UPDATE.
  7. ✅ `DimAssessmentWindow` seeded with MVP pilot windows: one English Elementary P-6 + one French Immersion Elementary P-6, both currently Open (2026-05-01 to 2026-06-30).
- **Bonus: usp_InsertSubmissionAudit retrofitted with Layer 2 validation** (NULL guard 51010 + 3 enum allow-lists 51011-51013 + email-format 51014 + LOWER normalization). Smoke tests confirm both throw paths and positive case (with email lowercasing) work.
- **End-to-end SQL backbone smoke-tested clean** via principal-at-school-0167 impersonation: vw_UserAssessmentWindows returns 1 row (FR window, 4 applicable), vw_TeacherGroups returns 3 group rows (HR:1A × 2 students, HR:5A × 1, HR:4D × 1), vw_TeacherRoster returns 4 student rows (Gamma, Omicron, Delta, Tau). All shapes match expectations. Impersonation reverted, baseline restored.
- **Power Apps build path PIVOTED** mid-session:
  - Started with C+B Copilot hybrid approach (chunked workbooks, Plan tool primer, schema reference doc — all produced and saved to `docs/powerapps-build/`).
  - **Power Apps Copilot proved unreliable** — couldn't even reliably write App.OnStart per the user. The C+B path is dead.
  - **New approach: VS Code YAML authoring + Studio for visual tweaks.** User did a thin Studio bootstrap (5 named screens, 1 ModernButton each, 6 data sources, app named "Student Data Staff Portal"), exported the `.msapp` to `powerapps/`.
  - **pac CLI installed** (Microsoft.PowerAppsCLI v2.7.4) at `C:\Users\jeffrey.raine\AppData\Local\Microsoft\PowerAppsCli\Microsoft.PowerApps.CLI.2.7.4\tools\pac.exe`. winget added a parent dir to PATH but the actual binary is in a versioned subfolder — use full path until PATH is rectified.
  - **Unpack succeeded** (`--layout SourceCode`) → 5 screen YAMLs + App.pa.yaml + _EditorState.pa.yaml + binary `.msapr` blob (holds data sources / connections). Format is clean: `Screens:` map with `Properties:` (Power Fx via `=Formula`) and `Children:` (control trees).
- **Memory adds this session**:
  - `project_assessment_types.md` — Reading / Writing / Math; single-type per window; concurrent multi-type efforts = multiple overlapping windows.
  - `feedback_file_links_in_instructions.md` — always wrap file references in clickable markdown links.
  - `feedback_project_email.md` — use `jeffrey.raine@tcrce.ca` (the M365 / Entra UPN), NOT `jeff.raine@gnspes.ca` from auto-memory (personal Google Workspace account, unrelated).
  - `feedback_no_wrap_prompts.md` — never suggest wrapping the session; user wraps on their own time schedule, not at project milestones.
- **Pending Step 18 work**:
  - The roundtrip sanity test (above).
  - Then start editing YAML — `App.pa.yaml` (OnStart with `gblIsAdminOrAnalyst`), then `scrLanding.pa.yaml` (rename Button1, add lblGreeting / lblUserUPN / btnStudentData / btnDataEntry per Path-B of `docs/powerapps-build/chunks/01b-scrLanding.md`).
  - Continue through scrWindowSelect, scrGroupSelect, scrRosterGrid using the Path-B sections of the per-screen chunked workbooks (Path-C / Copilot prompts are deprecated — ignore them).
  - Pack and re-import periodically to test in Studio.
  - Studio gets used only for visual tweaks (positioning, fonts, colours) after functions work.
- **Blockers**: None. SQL backbone is fully working; Power Apps workflow is bootstrapped and ready.

### Left Off — 2026-05-12 (Step 18 SQL prereqs partial — reading scale + DimGrade done)
- **Last completed**: DimGrade, DimReadingScale refactor, DimReadingBenchmark new, EN + FR seeds (59 levels + 160 benchmark rows). All deployed and verified. Architectural decisions for Step 18 nailed down.
- **What landed today**:
  - **Architectural decision: `vw_UserAssessmentWindows` role-branched + historical-roster reconciliation** (Option 3 from yesterday's question). For closed windows, teachers see the roster they HAD at the time — not their current roster. Admin-side intentionally NOT historically reconciled (StaffSchoolAccess is current-only). New memory: `project_historical_roster_reconciliation.md`. Design doc updated with role-branched SQL.
  - **`DimReadingScale` refactored** from single-table to two-table model. `DimReadingScale` becomes the valid-levels list (dropdown source); new `DimReadingBenchmark` holds the Grade × Month × Min/Max expectation matrix.
  - **F&P references removed everywhere** per user request (political reasons). ScaleSystem naming: `'EN_Reading'` / `'FR_Reading'` — vendor-neutral, language-prefixed.
  - **English scale seeded**: 27 levels (DT + A-Z), 80 benchmark rows (Grades P-7, Sept-Jun, ProgramFamily = English). Grade 7 = Grade-6-June Z-Z carry-over for students who didn't reach grade level.
  - **French scale seeded**: 32 levels (TD + 1-30 + 30+), 80 benchmark rows (Grades P-7, ProgramFamily = French Immersion only — FSL not in scope). Same Grade 7 carry-over (30 to 30+).
  - **30+ chosen as a submittable level** (LevelOrder = 31) — symmetric with the no-upper-bound semantic. Teachers can pick 30+ from the dropdown; benchmark Max = 30+ means "no positive delta possible."
  - **ReadingDelta formula refined** with explicit pre-CASE NULL validation (THROW 51001) and AND-explicit in-range condition. No silent wrong answers on lookup failures.
  - **Submission validation strategy memorialized** — three layers: Power Apps client → proc input validation → compute safety nets. Error code allocation 51001-51009 (safety nets) / 51010-51029 (user-fixable) / 51030-51049 (permission). New memory: `project_submission_validation_strategy.md`. Strongest version of Layer 1: constrain `Items` via data filters so invalid choices are impossible to make.
  - **`DimGrade` deployed**: 15-row lookup (PP=-1, P=0, 1-12, RG=13, with GradeName + GradeBand). Solves grade-range BETWEEN comparisons in window-applicability views.
  - **`cmbNewLevel` dropdown configuration locked**: `Items` filters DimReadingScale by `gblSelectedWindow.ScaleSystem`, sorted by `LevelOrder`. `DisplayFields = ["LevelCode"]` so teachers see "DT", "A", "1", "30+" etc. without internal columns leaking.
  - **`DimAssessmentWindow.ScaleSystem` column** added to the planned migration spec. Each window declares which scale applies; ScaleSystem in DimReadingScale must match for the dropdown filter to work.
- **Test data state at session end**: DimGrade 15, DimReadingScale 59 (27 EN + 32 FR), DimReadingBenchmark 160 (80 EN + 80 FR). No other table changes today.
- **Pending Step 18 work** (in suggested order):
  1. `usp_MergeStudent` Wrk_Student translation update for PS `grade_level=13` → `'RG'`
  2. `DimAssessmentWindow` migration (drop `AppliesTo` + `IsCurrentWindow`, rename `ProgramCode` → `ProgramFamily`, add `ScaleSystem`)
  3. `vw_UserAssessmentWindows` (SQL drafted in design doc — ready to deploy as-is)
  4. `vw_TeacherGroups` revised (same historical-reconciliation pattern; SQL not yet drafted)
  5. `vw_TeacherRoster` revised (same pattern; SQL not yet drafted)
  6. `usp_UpsertReadingAssessment` (3-layer validation + ReadingDelta formula)
  7. Seed pilot windows in `DimAssessmentWindow` (at least one English + one French Immersion)
  8. Power Apps screen build (4 screens via C+B hybrid + grounded Copilot prompts)
- **Open architectural questions**:
  - Grade 8+ carry-over pattern — does retention extend past Grade 7 for EN or FR?
  - FSL reading assessment — is FSL ever assessed for reading? Currently not in MVP scope.
  - `usp_InsertSubmissionAudit` retrofit to 3-layer validation pattern — deferred unless audit table becomes consequential downstream.
- **Blockers**: None. All design decisions for Step 18 are made; remaining work is straightforward implementation.

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
