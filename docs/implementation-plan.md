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
- [ ] **6. Request first PowerSchool CSV exports** — French program students, staff, schools, enrollments *(Manual — PowerSchool admin)*
- [ ] **7. Upload CSVs to OneLake** landing zone *(Manual — Fabric portal)*
- [ ] **8. Run merge procedures** to load pilot data into warehouse *(Claude can generate — `sql/procedures/`)*

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

- [ ] **27. Create Entra ID security groups**: `SG-Assessment-Teachers`, `SG-Assessment-SchoolAdmins`, `SG-Assessment-Regional` — populate from staff export *(Manual — Entra admin portal)*
- [ ] **28. Full PowerSchool export** — all programs, all schools *(Manual)*
- [ ] **29. Build Power Automate flow** for automated CSV ingestion *(Claude can generate flow JSON structure — `power-automate/`)*
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
| Phase 1: Foundation | 8 | 5 |
| Phase 2: Security & Views | 6 | 0 |
| Phase 3: Power Apps | 7 | 0 |
| Phase 4: Pilot Testing | 5 | 0 |
| Phase 5: Full Rollout | 10 | 0 |
| **Total** | **36** | **5** |

---

## Notes

- **Highest risk item**: Step 16 (Power Apps → Fabric SQL connection) — test this as early as possible
- **Hard deadline**: Steps 1–21 must be complete by June 2025 for pilot launch
- **Deferred to September**: Writing assessments, Power BI reports, automated ingestion, full SCD Type 2, security groups
- **RLS approach**: Data-level filtering uses `USERPRINCIPALNAME()` matched against the teacher-of-record email in the PowerSchool section export — no security groups required for this. Groups are only needed at full rollout for managing app access across ~200 teachers.
- **Fabric Warehouse T-SQL limitations**: No `DEFAULT` constraints, no `PRIMARY KEY`/`FOREIGN KEY` in `CREATE TABLE`, no `NVARCHAR` (use `VARCHAR`), no `DATETIME` (use `DATETIME2(0)`), `DATETIME2` requires explicit precision 0–6, `IDENTITY` columns must be `BIGINT` not `INT`, `IDENTITY` takes no seed/increment parameters, `CREATE INDEX` not supported (columnstore is automatic). Data integrity is enforced through ETL procedures, not database constraints. FK relationships must be defined manually in the Power BI semantic model. Full reference in `/fabric-warehouse-sql` skill.
- **DimCalendar**: Original WHILE loop version is slow (~5+ min for 5844 rows). Rewritten as a single bulk INSERT using cross-join CTE — use the current file version.
- **Year-end close-out (deferred)**: Build a scheduled procedure that closes out sections, FactSectionTeachers triples, and FactEnrollment rows when a school year ends — independent of the regular ingest. The regular merge anti-join handles this *eventually* (when next year's data lands), but that leaves Jun–Aug with stale rosters surfacing in Power Apps. Driven by `DimTerm.SchoolYearEnd`. Tackle during/after Step 8 (merge procedures), before September rollout.

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
