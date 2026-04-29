# PowerSchool Export Procedures

**Purpose:** Operational record of how each test CSV is being pulled from PowerSchool — which table/report, which filters, when. This is a working document; fill in the blanks for each pull and update notes as quirks come up.

**Scope:** MVP pilot (French Immersion) test data pulled by Jeff using own PS access. Once the schema and ingest are validated end-to-end, the PS admin will reproduce these pulls as scheduled SQL reports.

**Reference:** Field semantics and warehouse rationale are in [powerschool-field-mapping.md](powerschool-field-mapping.md). This doc is the *how* (where the data comes from); that doc is the *why* (what each field means).

---

## Export 1 — Students → `DimStudent`

**Source table / report:** "Students (1)"

**Filters applied:** Enroll_Status = 0 (Indicates an actively enrolled student)

**File format:** TAB-delimited, `.text` extension (PS direct table extract default). Drop in `data/imports/students/`.

| Warehouse Field | PowerSchool Field |
|---|---|
| StudentNumber | Student_Number |
| FirstName | First_Name |
| MiddleName | Middle_Name |
| LastName | Last_Name |
| DateOfBirth | DOB |
| CurrentGrade | Grade_Level |
| CurrentSchoolID | SchoolID |
| ProgramCode | NS_Program |
| EnrollStatus | Enroll_Status |
| Homeroom | Home_Room |
| Gender | Gender |
| SelfIDAfrican | NS_AssigndIdentity_African |
| SelfIDIndigenous | NS_aboriginal |
| CurrentIPP | CurrentIPP |
| CurrentAdap | CurrentAdap |
| SourceSystemID | ID |

**Required filter (pilot scope):** `NS_Program` IN (`E015`, `J015`, `J020`, `S015`, `S020`, `S115`, `S120`, `S215`, `S220`) — French Immersion only.

**Notes:**
- **Grade_Level translation at ingest** — PS emits `0` for Primary and `-1` for Pre-Primary; ingest converts to `'P'` and `'PP'` respectively before writing to `DimStudent.CurrentGrade`. Other grades (`1`–`12`) stored verbatim as their string form.
- **DOB format** — PS emits `MM/DD/YYYY` (e.g. `10/13/2014`). Ingest uses `CONVERT(DATE, val, 101)`.
- **Gender values** — observed: `M`, `F`, `X`. `X` represents "Non-binary or another gender identity" — see `DimGender` reference table.
- **Boolean encodings** — confirmed against test pull 2026-04-29: `SelfIDAfrican` = `Yes`/empty; `SelfIDIndigenous` = `1`/`2`/empty; `CurrentIPP`/`CurrentAdap` = `Y`/`N`.
- **PS field name spelling** — `NS_AssigndIdentity_African` (note the `d` between `Assign` and `Identity`) is the actual PS column name. Verified 2026-04-29 against test export.

---

## Export 2 — Staff → `DimStaff` + `FactStaffAssignment`

**Source table / report:** "Teachers (5)"

**Filters applied:** Status = 1 (Indicates active staff)

**File format:** TAB-delimited, `.text` extension (PS direct table extract default). Drop in `data/imports/staff/`.

**Grain:** one row per (person × school × role). Multi-school or multi-role staff appear multiple times — this is required, do not collapse.

| Warehouse Field | PowerSchool Field |
|---|---|
| Email | Email_Addr |
| FirstName | First_Name |
| LastName | Last_Name |
| Title | Title |
| HomeSchoolID | HomeSchoolID |
| CanChangeSchool | CanChangeSchool |
| SchoolID | SchoolID |
| RoleCode | Group |
| ID | ID |

**Required filter (scope):** active staff only (teachers, school specialists, administrators). Inactive/former staff must NOT be in the export — the warehouse uses absence to drive `ActiveFlag` close-out.

**Notes:**
- **Field set verified** against test pull 2026-04-29 (revised) — all 9 columns present including per-row `SchoolID`. Column order: `Email_Addr`, `First_Name`, `Last_Name`, `Title`, `HomeSchoolID`, `SchoolID`, `CanChangeSchool`, `Group`, `ID`.
- **Multi-row grain confirmed** — same email can appear on multiple rows with different `SchoolID` and different `ID` values. Test pull included a 3-row Dept of Education staff member (Group `9`, schools `0`/`167`/`255`). Per-person fields (Title, HomeSchoolID, CanChangeSchool, Group) are consistent across all rows for the same email; the per-row fields (SchoolID, ID) vary.
- **`HomeSchoolID = '0'` sentinel** — Dept of Education / district-level staff emit `'0'` here. Ingest translates to `NULL` (matches the warehouse convention that staff with no single home school have NULL). The district-level fact is captured separately via `IsDistrictLevel`, derived from `'0'` in `CanChangeSchool`.
- **`SchoolID = '0'`** on a per-row assignment — represents the district-tier aggregate row. Ingest translates to `'0000'` to match the `vw_StaffSchoolAccess` parsing rule.
- **`Title` values observed**: `TA`, `Teacher`, `Dept of Education`. Stored verbatim — not the same as `RoleCode`.
- **`Group` codes** are the PS RoleNumbers (1-50). Full mapping to warehouse `RoleCode` (`Teacher` / `SpecialistTeacher` / `Administrator` / `RegionalAnalyst` / `ProvincialAnalyst` / `SupportStaff`) lives in [`DimRole`](../sql/dimensions/DimRole.sql) — 50 rows seeded 2026-04-29 from PS admin's role list. Codes seen in the test export: `9` (DoE PS Admin → ProvincialAnalyst), `48` (Teacher additional responsibilities → Teacher), `50` (NA - 50 → SupportStaff; legacy code with a few non-teaching accounts still active).
- **`CanChangeSchool` parsing** — semicolon-separated list. Example: `'716'` (single school), `'0;79;167;...;999999'` (district-level + multi-school + graduates pseudo-school). Special markers: `0` = district tier (emit as `'0000'` aggregate marker downstream), `999999` = graduates pseudo-school (strip).
- **Edge case — conflicting person-level fields for same email**: the test pull labels three rows for the same email with different First_Name values (`Province1`/`Province2`/`Province3`). In production this should never happen — same email = same person. Merge proc handling: pick the row with the lowest `ID` deterministically as the canonical person record and log a warning to `FactSubmissionAudit` if any per-person field differs across same-email rows.

---

## Export 3 — Sections → `DimSection` + `FactSectionTeachers` (Primary)

**Source table / report:** "Sections (3)"

**Filters applied:** TermID >= 3500 ; TermID < 3600 (Limits to sections from the 2025-2026 School year, filter value will change each year.)

**File format:** TAB-delimited, `.text` extension (PS direct table extract default). Drop in `data/imports/sections/`.

| Warehouse Field | PowerSchool Field |
|---|---|
| SectionID | ID |
| SchoolID | SchoolID |
| TermID | TermID |
| CourseCode | Course_Number |
| SectionNumber | Section_Number |
| CourseName | [2]course_name |
| PrimaryTeacherEmail | [5]Email_Addr |
| EnrollmentCount | No_of_students |
| MaxEnrollment | MaxEnrollment |

**Notes:**
- **Field set verified** against test pull 2026-04-29 — all 9 columns present, named exactly as documented (including the `[2]course_name` and `[5]Email_Addr` cross-table prefixes).
- **`SchoolID` left-padding at ingest** — PS strips leading zeros (e.g. emits `981` for school `0981`, `79` for `0079`). Ingest must zero-pad to 4 digits to match `DimSchool.SchoolID`.

---

## Export 4 — Co-Teachers → `FactSectionTeachers` (non-Primary)

**Source table / report:** Reports --> sqlReports --> Teacher --> "Find Co-Teachers"

**Filters applied:** Automatically searches only current school year.

**File format:** comma-delimited, `.csv` extension, double-quote text qualifier (sqlReport default — different from the table-extract exports above). Drop in `data/imports/section-teachers/`.

**Skip this export entirely if PS does not track co-teaching.** Do NOT include the primary teacher here — they come from Export 3.

| Warehouse Field | PowerSchool Field | Report Header |
|---|---|---|
| SectionID | ID | SectionID |
| TeacherEmail | [5]Email_Addr | Email |
| TeacherRole | Role | Role |

**Notes:**
- Report includes additional fields (`School`, `TermID`, `Course`, `Section`, `Teacher`) that could be used for debugging but not necessary to ingest as part of normal course of business. Ingest should select by header name, not column position.
- **Quote handling** — comma-containing values like `"Teacher, Test"` are wrapped in double quotes per CSV standard. Parser must respect the quote qualifier.

---

## Export 5 — Enrollments → `FactEnrollment`

**Source table / report:** "CC (4)"

**Filters applied:** TermID >= 3500 ; TermID < 3600 (Limits to sections from the 2025-2026 School year, filter value will change each year.)

**File format:** TAB-delimited, `.text` extension (PS direct table extract default). Drop in `data/imports/enrollments/`.

**Scope:** include currently-active enrollments AND any enrollments closed since last pull (i.e. with `DateLeft` populated). Do NOT send a full historical roster.

| Warehouse Field | PowerSchool Field |
|---|---|
| StudentNumber | [1]Student_Number |
| SectionID | SectionID |
| StartDate | DateEnrolled |
| EndDate | DateLeft |
| SourceSystemID | ID |

**Notes:**
- **`DateLeft` is auto-populated by PS for active enrollments** — not a "left early" signal. PS sets it to the section's term-end-date when the student enrolls, so the system can auto-exit them when the course ends. Year-long courses get end-of-June; one-semester courses get end-of-January (S1) or end-of-June (S2). Both can shift to the nearest school day depending on the calendar.
- **Ingest must compare `DateLeft` against the section's term-end-date** (lookup via `DimSection → DimTerm`):
  - `DateLeft = term end (± school-day adjustment)` → student is **still enrolled**, treat as active. Store `EndDate = DateLeft` but `ActiveFlag = 1`.
  - `DateLeft < term end` → student **left early**, treat as closed. `ActiveFlag = 0`.
  - `DateLeft` blank → still enrolled. `EndDate = NULL`, `ActiveFlag = 1`.
- **Date format** — `MM/DD/YYYY`, same as Students DOB. Use `CONVERT(DATE, val, 101)`.

---

## Schools — *not exported from PowerSchool*

`DimSchool` is seeded from the Nova Scotia Department of Education 2024-2025 Directory of Public Schools (see [seed_DimSchool_TCRCE.sql](../sql/scripts/seed_DimSchool_TCRCE.sql)). PowerSchool's `SchoolID` values must match the 4-digit provincial school numbers used in that seed.

---

## General Conventions

- **Encoding:** UTF-8
- **Delimiter:** depends on PowerSchool source.
  - **Direct table extracts** (Exports 1, 2, 3, 5) → TAB-delimited, `.text` extension, no text qualifier (PS default).
  - **sqlReports** (Export 4) → comma-delimited, `.csv` extension, double-quote text qualifier.
  - The ingest pipeline auto-detects the delimiter from the header line (count tabs vs commas) so it stays robust against PS export-tool changes. Each export's section above documents its expected form.
- **Line endings (verified 2026-04-29 against actual PS production export):** PS direct table extracts use **CR-only line endings** (`0x0D`, no LF — old-Mac-style), not CRLF. Fabric `COPY INTO` default `ROWTERMINATOR` doesn't catch this and silently loads zero rows. Every staging COPY INTO for direct extracts must specify `ROWTERMINATOR = '0x0D'`. The local anonymized dummies in `data/imports/` have CRLF endings (Windows tooling normalized on save) — the production exports do NOT. Step 29 Power Automate flow should normalize CR → CRLF/LF on file arrival.
- **Header row:** required
- **Filename:** does NOT need to match a specific name. The ingest pipeline routes by **folder placement**, not filename — each export topic has its own subfolder under the OneLake landing zone (and locally under [data/imports/](../data/imports/)). PS exports default to long auto-generated names like `AssessmentDataStudentsExport.text`; just drop the file in the correct folder. This protects against naming-convention drift while different people are pulling test exports.
- **Folder layout** (under `data/imports/` locally; mirror in OneLake):
  - `students/` — Export 1
  - `staff/` — Export 2
  - `sections/` — Export 3
  - `section-teachers/` — Export 4
  - `enrollments/` — Export 5
- **Number padding:** ingest will zero-pad `SchoolID` to 4 digits, so leading-zero stripping in PS is fine
- **Email casing:** ingest will lowercase, so original casing doesn't matter
- **Source table notation:** entries in "Source table / report" are written as `"TableName (N)"` where `N` is the PowerSchool internal table number (e.g. `"Students (1)"`, `"Teachers (5)"`). The same `N` is used in field references like `[5]Email_Addr` to indicate the field is pulled from a related table — table 5 (Teachers) in that example. This makes the export reproducible by the PS admin without ambiguity about which table a field came from.
- **Saved sqlReports as a source:** when an export is sourced from a saved PS sqlReport rather than a direct table extract, the source-table cell records the PS UI navigation path (e.g. `Reports --> sqlReports --> Teacher --> "Find Co-Teachers"`) instead of the `"TableName (N)"` form. Reports often alias columns for readability, so those exports add a third "Report Header" column to the field-mapping table — that header is what actually appears in the CSV (and therefore what the ingest reads), while the PS Field column remains the canonical reference for what underlying data the column represents.

---

## Pull History

| Date | Export(s) | Notes |
|---|---|---|
| 2026-04-29 | All 5 | Anonymized test pull (10/2/4/3/6 rows + headers) for format validation. Confirmed: TAB-delimited for direct extracts, comma+quote for sqlReports. Field-name fix: `NS_AssigndIdentity_African` (with `d`). Found: Staff export missing `SchoolID` column. Decisions made: Grade_Level translation `0`→`'P'`, `-1`→`'PP'`; `DateLeft` auto-fill semantics; folder-based ingest routing. |
| 2026-04-29 | Staff (revised) | Re-pull with `SchoolID` column added (5 rows). Multi-row grain confirmed via 3-row Dept of Education test row. New observations: `HomeSchoolID = '0'` and `SchoolID = '0'` sentinels for district-tier staff (translate to NULL and `'0000'` respectively at ingest); `Group = 9` for Dept of Education added to running code list; same-email-different-First_Name edge case noted. |
| 2026-04-29 | (reference) | DimRole table received from PS admin — 50-row mapping of PS RoleNumber → RoleName. Mapped to warehouse RoleCode and seeded into `DimRole`. 40 active roles, 10 unused/placeholder slots. Two judgment-call mappings flagged for confirmation: 29 (Report Creator) and 30 (Evaluation Services - 30). |
| | | |
| | | |
