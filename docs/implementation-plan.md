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
- [ ] **8. Run merge procedures** to load pilot data into warehouse *(Claude can generate — `sql/procedures/`)*. **In progress 2026-04-30:** `usp_MergeStudent` (DimStudent) and `usp_MergeStaff` (DimStaff + FactStaffAssignment) deployed and validated end-to-end against synthetic data. Decoupled load + merge pattern established. Still TODO under Step 8: `usp_MergeSection` (DimSection), `usp_MergeEnrollment` (FactEnrollment), `usp_MergeSectionTeachers` (FactSectionTeachers), and the deferred year-end close-out procedure.

---

## Phase 2: Security & Views (Weeks 3–4)
*Goal: RLS enforced, data accessible only to correct users*

- [ ] **9. Write secured SQL views**: `vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData` *(Claude can generate — `sql/views/`)*
- [ ] **10. Test views** by querying as pilot teacher Entra accounts *(Manual — requires real Entra identities)*
- [ ] **11. Create Fabric semantic model** pointing to warehouse views *(Manual — Power BI portal)*
- [ ] **12. Configure DAX RLS roles** in semantic model (`[TeacherEmail] = USERPRINCIPALNAME()`) *(Claude can write DAX)*
- [ ] **13. Validate RLS** with test accounts — confirm teacher sees only their students *(Manual — requires login testing)*
- [ ] **14. Write data quality validation queries** — orphan checks, duplicate IsCurrent, date logic *(Claude can generate — `sql/scripts/`)*

---

## Phase 3: Power Apps Entry Form (Weeks 5–6)
*Goal: Teachers can submit reading assessments from Teams*

- [ ] **15. Create canvas app** in Power Apps maker portal *(Manual — maker portal)*
- [ ] **16. Connect app to Fabric SQL endpoint** — test connection early, may need custom connector *(Manual — connector setup in portal)*
- [ ] **17. Design screen layout** — `scrStudentSelect`, `scrAssessmentEntry`, `scrConfirmation` *(Claude can provide full screen logic and formulas)*
- [ ] **18. Write Power Apps formulas** — student filter, active window filter, submit action *(Claude can write all formulas)*
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
| Phase 1: Foundation | 8 | 7 |
| Phase 2: Security & Views | 6 | 0 |
| Phase 3: Power Apps | 7 | 0 |
| Phase 4: Pilot Testing | 5 | 0 |
| Phase 5: Full Rollout | 10 | 0 |
| **Total** | **36** | **7** |

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
