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
- **DimCalendar**: Original WHILE loop version is slow (~5+ min for 5,844 rows). Rewritten as a single bulk INSERT using cross-join CTE — use the current file version.

### Left Off — 2026-04-24
- **Last completed step**: Step 5. DimSchool seeded with 22 TCRCE schools (SchoolID as VARCHAR(10), Abbreviation column populated).
- **Step 6 in progress**: Field mapping doc ready ([docs/powerschool-field-mapping.md](powerschool-field-mapping.md)). User is filling in PowerSchool field names and will send to admin. Schools export dropped from request (seeded from provincial directory instead).
- **CRITICAL before continuing**: The updated [migrate_SchoolID_to_VARCHAR.sql](../sql/scripts/migrate_SchoolID_to_VARCHAR.sql) still needs to run against the warehouse. It now preserves DimSchool and rebuilds only the 4 empty tables (DimStudent, DimStaff, DimSection, StaffSchoolAccess) with the final schema: StudentNumber as BIGINT business key, Email as DimStaff business key, VARCHAR(10) SchoolID, nullable HomeSchoolID.
- **Key session decisions**:
  - `DimProgram` reference table added (20 codes categorized by grade band, program family, IB/O2 specialty)
  - `DimStudent.StudentNumber BIGINT` (provincial 10-digit) replaces StudentID; more stable across re-enrollments
  - `DimStaff.Email` replaces StaffID as business key (PowerSchool creates one row per staff-school combo, so email is the only consistent key); `HomeSchoolID` nullable for itinerant staff
  - `DimSchool.SchoolID VARCHAR(10)` preserves 4-digit provincial number leading zeros; 22 schools seeded with `Abbreviation` column from directory email prefixes
  - `LRHS` abbreviation confirmed correct (directory had typo showing `LHS`)
- **Next action**: Run the migration, then start Step 8 (merge procedures) while waiting for PowerSchool exports.
- **Blockers**: User restarting computer for software troubleshooting; pick back up after restart.
