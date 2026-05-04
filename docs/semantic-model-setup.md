# Semantic Model Setup — `Assessment_Analytics`

**Status:** Step 11 (manual) of the implementation plan.

**Goal:** Create a custom Power BI semantic model in the `Regional_Data_Portal` Fabric workspace, sourced from the `Assessment_Warehouse`, with the table set, relationships, and DAX RLS roles needed for analyst-tier reporting.

This document is a click-through. The DAX role expressions live in [`power-bi/dax_rls_roles.dax`](../power-bi/dax_rls_roles.dax).

---

## 1. Create the model

1. Open the `Regional_Data_Portal` workspace in the Fabric portal.
2. Open `Assessment_Warehouse` → top-right **... menu** → **New semantic model**.
3. **Name:** `Assessment_Analytics`.
4. **Storage mode:** **Direct Lake on OneLake**. Reads the warehouse's underlying Delta files directly — full DAX surface for RLS expressions (notably `[Column] IN tablevar`, which the SQL-fallback path of "Direct Lake on SQL" blocks via the DirectQuery DAX subset). The model contains zero views (`vw_StaffSchoolAccess` was materialized as the `StaffSchoolAccess` table on 2026-05-04 specifically to enable this mode), so OneLake mode imposes no constraint here.

---

## 2. Add tables

Select these tables/views to include in the model. The "Why" column is for reviewer context — not part of the click-through.

| Type | Name | Why |
|---|---|---|
| Dim | DimAssessmentWindow | Slicing assessments by window |
| Dim | DimCalendar | Standard time dimension |
| Dim | DimGender | Friendly labels for `DimStudent.Gender` codes |
| Dim | DimProgram | Program-band slicers (E/J/S, Immersion flag) |
| Dim | DimReadingScale | Reading-level lookups |
| Dim | DimSchool | Slicing reports by school |
| Dim | DimSection | Required for Teachers RLS cascade |
| Dim | DimStaff | Reporting (e.g. teacher counts), and DAX-side identity lookups |
| Dim | DimStudent | Primary RLS target |
| Dim | DimTerm | Slicing by school year / Year-Long / S1 / S2 |
| Fact | FactAssessmentReading | Primary fact for reports |
| Fact | FactEnrollment | Student-section grain; required for Teachers RLS cascade |
| Fact | FactSectionTeachers | Required for Teachers RLS oracle |
| Fact | FactStaffAssignment | Required for staff-RLS school-overlap check (correctly handles itinerant / multi-school staff that DimStaff.HomeSchoolID alone misses) |
| Table | StaffSchoolAccess | RLS oracle — materialized union of HomeSchoolID + parsed CanChangeSchool, rebuilt on every staff merge |

**Skip for now (not needed at MVP):**
- `DimRole` — operational lookup, not analytical (RoleCode strings are already on `FactStaffAssignment`)
- `FactAssessmentWriting` — deferred to September rollout (Step 31)
- `FactSubmissionAudit` — operational telemetry, not analytical
- `vw_TeacherStudents` / `vw_SchoolStudents` / `vw_RegionalData` — these are the SQL-layer security views consumed by Power Apps. The semantic model has its own DAX RLS so doesn't need these.

---

## 3. Verify relationships

Fabric will auto-detect some relationships based on column-name matches. Verify each one and add any that are missing. Cardinality and cross-filter direction matter.

| ✓ | From | To | On | Cardinality | Cross-filter |
|---|---|---|---|---|---|
| X | DimStudent | FactEnrollment | StudentKey | 1:* | Single (default) |
| X | DimSection | FactEnrollment | SectionKey | 1:* | Single |
| X | DimStudent | FactAssessmentReading | StudentKey | 1:* | Single |
| X | DimAssessmentWindow | FactAssessmentReading | AssessmentWindowID | 1:* | Single |
| X | DimReadingScale | FactAssessmentReading | ReadingScaleID | 1:* | Single |
| X | DimSchool | DimStudent | SchoolID | 1:* | Single |
| X | DimSchool | DimSection | SchoolID | 1:* | **Inactive** (see ambiguity note below) |
| X | DimProgram | DimStudent | ProgramCode | 1:* | Single |
| X | DimTerm | DimSection | TermID | 1:* | Single |
| X | DimGender | DimStudent | GenderCode = Gender | 1:* | Single |
| X | DimCalendar | FactAssessmentReading | Date = AssessmentDate | 1:* | Single |
| X | DimStaff | FactStaffAssignment | StaffKey | 1:* | Single |
| X | DimSchool | FactStaffAssignment | SchoolID | 1:* | Single |

**Relationships involving FactSectionTeachers and DimStaff:**
- `FactSectionTeachers` keys on `SectionID` (business key) and `TeacherEmail` (business key) — neither column is unique on the DimSection or DimStaff side (Type 2 versioning). Power BI may warn or refuse to create a 1:* relationship.
- **Recommended:** leave `FactSectionTeachers` as an unrelated table for RLS-oracle purposes only. The DAX expression in the Teachers role traverses it via `CALCULATETABLE` + `IN`, not via relationships.
- **`DimStaff` ↔ FactSectionTeachers**: similarly leave unrelated. Reports that need to show "which teacher teaches a section" should join via DAX expressions referencing `LOOKUPVALUE`, not via a relationship.

`StaffSchoolAccess` is also kept unrelated — it's an RLS oracle accessed only by the SchoolAdmins and RegionalAnalysts DAX role expressions.

**Ambiguity note: `DimSchool` → `FactEnrollment` has two paths.** Power BI throws an ambiguity error when both `DimSchool → DimStudent` and `DimSchool → DimSection` are active, because a `DimSchool` filter could reach `FactEnrollment` either via `DimStudent.SchoolID` or via `DimSection.SchoolID`. Resolve by **marking `DimSchool → DimSection` (on `SchoolID`) inactive** — right-click the line in the diagram view → **Mark as inactive**, or in the manage-relationships dialog uncheck **"Make this relationship active"**. The line goes dotted; the relationship still exists for explicit `USERELATIONSHIP()` use in measures, but no longer auto-filters.

Why deactivate that one and not the other:
- The SchoolAdmins DAX RLS filters on `DimStudent[SchoolID]` — keeping `DimSchool → DimStudent` active means the school slicer naturally cascades through students to facts, which matches the RLS mental model.
- `FactAssessmentReading` only relates to `DimStudent` (no path through `DimSection`), so the student-path is the only viable one for assessment slicing anyway.
- "Filter sections by school" is rarely the *primary* analytical question — it's mostly display, and a DAX measure can override with `USERELATIONSHIP()` if a specific section-grain school analysis is needed later.

---

## 4. Define RLS roles

In the model editor (Power BI in the browser, or Power BI Desktop): **Modeling tab → Manage roles**. Create three roles:

Each role gets row-filter expressions on **two** tables: `DimStudent` (student visibility) and `DimStaff` (staff visibility). The DAX for each is in [`power-bi/dax_rls_roles.dax`](../power-bi/dax_rls_roles.dax).

### 4a. Role: `Teachers`

- Click **Create role** → name it `Teachers`.
- Select table **DimStudent** → paste the multi-line DAX block under `// Table filter on: DimStudent` in the "ROLE: Teachers" section.
- Select table **DimStaff** → paste the short DAX block under `// Table filter on: DimStaff` in the same section. Teachers see only themselves in DimStaff.
- Save.

### 4b. Role: `SchoolAdmins`

- Create role → `SchoolAdmins`.
- Select table **DimStudent** → paste the DAX from `// Table filter on: DimStudent` under "ROLE: SchoolAdmins".
- Select table **DimStaff** → paste the DAX from `// Table filter on: DimStaff` in the same section. Both Administrators and SpecialistTeachers see staff at their accessible schools (per the 2026-05-01 reclassification of teaching-specialist groups 22 and 32 to Teacher RoleCode, the remaining SpecialistTeacher list is admin-tier and shares the same staff-visibility rule as Administrator).
- Save.

### 4c. Role: `RegionalAnalysts`

- Create role → `RegionalAnalysts`.
- **DimStudent:** leave blank — no filter. Role membership is the access gate.
- **DimStaff:** leave blank — no filter. Same rationale.
- Save.

---

## 5. Test roles in the portal

The semantic model editor has a **View as → Other user** option that lets you simulate any UPN as the report viewer.

1. **View as → Other user:** enter `classroom.teacher1@tcrce.ca`.
2. Apply role: **Teachers**.
3. Open or create a quick visual that lists DimStudent rows.
4. Confirm: the visual shows the 4 students at school 0716 (Alpha, Lambda, Mu, Sigma) and excludes Beta (pre-enrolled with future StartDate) and all other-school students.
5. Repeat for the other test users from the SQL impersonation tests (see [`docs/implementation-plan.md`](implementation-plan.md) Left Off note for the test matrix).

This mirrors the SQL-side validation we ran on 2026-05-01 against the views — same expected outcomes per user, since the DAX RLS implements the same filter logic at a different layer.

---

## 6. Assign users to roles

**MVP pilot (Steps 21+):** assign individual users from the Power BI workspace's **Manage permissions** view. Add each pilot user to the appropriate role by Entra UPN.

**Full rollout (Step 27):** replace individual assignments with the three Entra security groups:
- `SG-Assessment-Teachers` → Teachers role
- `SG-Assessment-SchoolAdmins` → SchoolAdmins role
- `SG-Assessment-Regional` → RegionalAnalysts role

Users not in any of the three roles have **no semantic-model access** (Power BI RLS is opt-in: zero roles = zero rows). `ProvincialAnalyst` and `SupportStaff` accounts are intentionally excluded from all three security groups; they should never see Power BI report data.

---

## 7. Known caveats

- **Time-zone skew on `TODAY()` vs `GETDATE()`.** DAX `TODAY()` evaluates in the report viewer's local time zone; the SQL views use UTC. At the day boundary a pre-enrolled student may transiently appear in one layer and not the other. Acceptable at MVP; revisit if it causes user-facing confusion.
- **Role membership is the access gate.** A user not in any RLS role sees nothing. There's no implicit "everyone gets some default access." Provision role membership during user onboarding.
- **`ALL()` in RLS expressions** — the SchoolAdmins and RegionalAnalysts DimStaff filters use `ALL(FactStaffAssignment)` to look up other rows during per-row RLS evaluation. Power BI applies role filters per-table independently, so `ALL()` within an RLS expression bypasses the *target* table's RLS context, not other tables' RLS. This works correctly here because the lookups don't recurse into the role's own table filter. If a future role rewrites this pattern, double-check no recursion is introduced.
- **Itinerant / multi-school staff visibility from the admin perspective** — Staff with `HomeSchoolID = NULL` and multiple `FactStaffAssignment` rows (e.g. APSEA itinerants) are correctly visible to admins of any school they're assigned to, because the staff-RLS check uses `FactStaffAssignment.SchoolID` directly rather than `DimStaff.HomeSchoolID`. This is unchanged by the 2026-05-01 RoleCode reclassification — the admin's view of the itinerant doesn't depend on the itinerant's RoleCode.
- **APSEA itinerants don't authenticate** — APSEA itinerant teachers (RoleNumber 32, now `Teacher` RoleCode) are external contractors without TCRCE Entra accounts. They never log into Power BI, so their own role assignment is moot. They DO appear in DimStaff and FactStaffAssignment (for admin reports), and admins can see them at any school they're assigned to.
