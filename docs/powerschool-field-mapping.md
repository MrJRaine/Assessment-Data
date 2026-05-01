# PowerSchool Field Mapping Worksheet

**Purpose:** Map each warehouse field to its equivalent PowerSchool export field so the PowerSchool admin knows exactly what to include in each CSV export.

**Scope:** MVP pilot — French Immersion programs only. See "Pilot Program Code Filter" section below for the exact list of codes. Request one CSV per export below.

**How to use:** Fill in the rightmost column with the PowerSchool field/column name for each warehouse field. Notes in the right column can include things like "computed from X + Y" or "not available in PowerSchool" if the field can't be directly exported.

---

## Export 1 — Students (→ `DimStudent`)

One row per student enrolled in the French Immersion program. The business key is the provincial **Student Number** (not PowerSchool's DCID) because it survives re-enrollments — if a student leaves and returns they keep the same Student Number but may get a new PowerSchool record.

**SCD policy:** every business attribute below is a **Type 2 trigger** — any change creates a new versioned row. Rationale: reports often cite point-in-time values, and we don't want a later re-query to silently produce different numbers because a student's homeroom, name, or IPP status changed in the meantime. Only `StudentKey`, `StudentNumber`, `EffectiveStartDate`, `EffectiveEndDate`, `IsCurrent`, `SourceSystemID`, and `LastUpdated` are exempt from versioning.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| StudentNumber | BIGINT | **Business key** — provincial 10-digit student number (PowerSchool's "Student Number" field). Stable across re-enrollments and region transfers; follows the student for life | Student_Number |
| FirstName | VARCHAR(100) | | First_Name |
| MiddleName | VARCHAR(100) | Nullable — include where present. Helps distinguish students with identical first + last names in the same school/grade (common locally) | Middle_Name |
| LastName | VARCHAR(100) | | Last_Name |
| DateOfBirth | DATE | Optional but recommended. PS emits `MM/DD/YYYY` format (e.g. `10/13/2014`); ingest parses with `CONVERT(DATE, val, 101)` | DOB |
| CurrentGrade | VARCHAR(10) | Stored values: `'P'` (Primary), `'PP'` (Pre-Primary), `'1'`–`'12'`. PS emits `0` for Primary and `-1` for Pre-Primary as numeric codes; **ingest translates `0`→`'P'` and `-1`→`'PP'`** before storing. Other grade values stored verbatim as their string form | Grade_Level |
| CurrentSchoolID | VARCHAR(10) | 4-digit provincial school number (e.g. `'0167'`). Leading zeros are normalized during ingest | SchoolID |
| ProgramCode | VARCHAR(10) | PowerSchool program code (e.g. 'E005', 'J015', 'S120'). 4-character format: letter (grade band) + 3 digits. See "Pilot Program Code Filter" section below | NS_Program |
| EnrollStatus | INT | PS value stored verbatim. Full PS value list: `0` = Active, `2` = Inactive, `3` = Graduated, `-1` = Pre-Enrolled (registered but not yet started at the school). **Production export filters to `IN (0, -1)`**, so only Active and Pre-Enrolled rows appear in the warehouse — `2` and `3` are excluded upstream. The teacher view date-gates `-1` rows on `FactEnrollment.StartDate <= today`; the admin view shows all `-1` rows for roster planning. | Enroll_Status |
| Homeroom | VARCHAR(50) | Student's current homeroom (nullable) | Home_Room |
| Gender | VARCHAR(10) | Student's gender — only required field of this group. Observed values: `M` (Male), `F` (Female), `X` (Non-binary or another gender identity). Joins to `DimGender` for friendly descriptions | Gender |
| SelfIDAfrican | BIT | Student self-identifies as being of African descent. PS sends `"Yes"`/`"No"`/NULL — ingest translates to `1`/`0`/NULL. NULL means not declared either way (not the same as "No") | NS_AssigndIdentity_African |
| SelfIDIndigenous | BIT | Student self-identifies as being of Indigenous descent. PS sends `"1"` (Yes) / `"2"` (No) / NULL — ingest translates to `1`/`0`/NULL. NULL means not declared either way (not the same as "No") | NS_aboriginal |
| CurrentIPP | BIT | Student currently has at least one IPP. PS sends `"Y"`/`"N"`/NULL — ingest translates to `1`/`0`/NULL | CurrentIPP |
| CurrentAdap | BIT | Student currently has adaptations. PS sends `"Y"`/`"N"`/NULL — ingest translates to `1`/`0`/NULL | CurrentAdap |
| SourceSystemID | VARCHAR(50) | PowerSchool DCID (internal database ID). Stored for reference/debugging only — NOT used for record matching | ID |

---

## Export 2 — Staff (→ `DimStaff` + `FactStaffAssignment`)

**Scope — currently active staff only**: Generated from the PowerSchool report that filters to staff with active status. Includes **teachers, school specialists, and administrators**. Do **not** send inactive staff, former employees, or a full historical roster. The warehouse uses presence in this export to drive `ActiveFlag` — anyone not in the current import automatically transitions to inactive (see note below).

**Grain — expected duplicates**: The PS report emits **one row per staff-school-role combination**. A person who works at two schools appears twice; a vice-principal who also teaches one class appears twice (once as 'Administrator', once as 'Teacher'); an itinerant specialist serving five schools appears five times. **This is expected and required** — the warehouse needs that full grain to preserve multi-school and multi-role detail. Just make sure the `Email_Addr` is identical across rows for the same person.

### How the CSV feeds two tables

The ingest splits each raw row into two destinations:

- **`DimStaff`** — person-level identity, one row per unique email (collapsed). **All business attributes are SCD Type 2 triggers** — any change to FirstName, LastName, Title, HomeSchoolID, CanChangeSchool, IsDistrictLevel, or ActiveFlag creates a new versioned row. Same rationale as `DimStudent`: reports cite point-in-time values and must be reproducible.
- **`FactStaffAssignment`** — the bridge, preserves the full email×school×role grain. Versioned by effective dates; never collapses.

### Fields required in the CSV

| CSV Column | Type | Feeds | Description | PowerSchool Field |
|---|---|---|---|---|
| Email | VARCHAR(255) | `DimStaff.Email` (dedupe key) + `FactStaffAssignment.StaffKey` lookup | **Business key** — Entra ID UPN. Must match exactly what the user signs into Teams with. Will be lowercased during ingest | Email_Addr |
| FirstName | VARCHAR(100) | `DimStaff.FirstName` | | First_Name |
| LastName | VARCHAR(100) | `DimStaff.LastName` | | Last_Name |
| Title | VARCHAR(100) | `DimStaff.Title` | Job title (e.g. "Vice Principal", "Educational Assistant"). Per-person value, same across all rows of a multi-row staff member. Nullable for staff with no title set | Title |
| HomeSchoolID | VARCHAR(10) | `DimStaff.HomeSchoolID` | Per-person primary/home school (4-digit provincial number). Sourced from a joined PS table; same value on every row of a multi-row staff member. PS emits `'0'` for district-level / Dept of Education staff with no single home school — **ingest translates `'0'` to NULL**. Leave blank also for itinerant staff with no single home school | HomeSchoolID |
| CanChangeSchool | VARCHAR(255) | `DimStaff.CanChangeSchool` | Per-person semicolon-separated list of school IDs the user can navigate to in PS (e.g. `0;79;167;1199;999999`). Sourced from a joined PS table; same value on every row of a multi-row staff member. Populated only for staff with multi-school access; leave blank otherwise. Special markers: `0` = district-level tier, `999999` = graduates pseudo-school | CanChangeSchool |
| SchoolID | VARCHAR(10) | `FactStaffAssignment.SchoolID` | 4-digit provincial school number for **this row's** assignment (leading zeros normalized during ingest). Different from HomeSchoolID — this varies per row when staff appear multiple times. PS emits `'0'` for the district-tier aggregate row (Dept of Education staff); ingest translates to `'0000'` | SchoolID |
| RoleCode | VARCHAR(50) | `FactStaffAssignment.RoleCode` | PS emits the numeric `Group` code (1-50). Ingest joins to `DimRole` to translate `RoleNumber` → warehouse `RoleCode`. Six-value taxonomy: `Teacher` (classroom + librarians; section-level RLS), `SpecialistTeacher` (counsellors, registrars, school-based coordinators e.g. IB/O2/Co-op, resource teachers, APSEA itinerants; school-level + section-level RLS), `Administrator` (Principal/VP, admin assistants; school-level RLS), `RegionalAnalyst` (TCRCE board-level — superintendent, board directors, board services, board coordinators/consultants; multi-school RLS), `ProvincialAnalyst` (DoE / Evaluation Services; **not in PowerApp security group — no app access at all**), `SupportStaff` (no student-data access in app — excluded from RLS). NULL for unused PS slots. See [sql/dimensions/DimRole.sql](../sql/dimensions/DimRole.sql) for the full mapping | Group |
| ID | VARCHAR(50) | `FactStaffAssignment.SourceSystemID` | PowerSchool staff record ID for this specific email×school×role row. Used for matching by triple `(StaffKey, SchoolID, RoleCode)`, but a **change in this value for an existing triple triggers a new SCD version** — this catches email-reuse collisions where a retiring staffer's `first.last@tcrce.ca` gets handed to a new hire with the same name. Audit-flag any import where this fires | ID |

### `ActiveFlag` derivation (not a CSV column)

The PS report already filters to active staff, so every row in the export is active by definition. The merge procedure derives `ActiveFlag` on `DimStaff` via reconciliation against what it knew previously:

- Email present in the current import → `DimStaff.ActiveFlag = 1`
- Email already in `DimStaff` but **absent** from the current import → SCD Type 2 transition to `ActiveFlag = 0` (close current version, insert new inactive version)
- Returning staff (inactive → present again) → SCD Type 2 transition back to `ActiveFlag = 1`

Same pattern applies to `FactStaffAssignment` rows at the (email × school × role) grain: a triple that disappears from one import gets `EffectiveEndDate` set and `IsCurrent = 0`; a new triple gets inserted with today as `EffectiveStartDate`.

"Inactive" in the warehouse does **not** mean "no longer employed" — it means "dropped out of the active-staff report this cycle". Possible causes: on leave, sabbatical, retired, role change, left the region. Rows are retained forever so historical fact-table joins on `StaffKey` never break.

Because of this logic, **no `Status` / active-flag column is needed in the CSV** — it's implied by inclusion.

---

## Export 3 — Sections (→ `DimSection` + `FactSectionTeachers`)

One row per instructional section in the pilot schools. The primary teacher's email feeds **both** targets:
- `DimSection.TeacherStaffKey` — canonical teacher-of-record on the section dim
- One `FactSectionTeachers` row per section with `TeacherRole = 'Primary'`

Co-teaching arrangements (if PS tracks them) are handled by Export 4 below — **do not** include co-teachers here.

**SCD policy:** every business attribute below is a **Type 2 trigger** — any change creates a new versioned row. Same rationale as `DimStudent` and `DimStaff`: reports cite point-in-time values and must be reproducible. Note that `EnrollmentCount` will fluctuate as students enroll/withdraw, so DimSection accumulates versions over the school year. Only `SectionKey`, `SectionID`, `EffectiveStartDate`, `EffectiveEndDate`, `IsCurrent`, `SourceSystemID`, and `LastUpdated` are exempt.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | **Business key** — region-unique identifier per section | ID |
| SchoolID | VARCHAR(10) | 4-digit provincial school number the section is in | SchoolID |
| TermID | INT | PS 4-digit TermID (e.g. `3501` = 2025-2026 Semester 1). Format: `YY` = year-1990, `TT` = 00 Year Long / 01 S1 / 02 S2. Joins to `DimTerm` to decode school year + term | TermID |
| CourseCode | VARCHAR(50) | Course identifier (e.g. 'MATH-3-FR') | Course_Number |
| SectionNumber | VARCHAR(20) | School-set section number (e.g. `'01'`, `'02'`). Used in the Power App section picker so teachers can identify their sections quickly | Section_Number |
| CourseName | VARCHAR(200) | Human-readable course name (e.g. 'Math 7 French Immersion'). Display label for the Power App section picker | [2]course_name |
| PrimaryTeacherEmail | VARCHAR(255) | The teacher-of-record's email. Two destinations: (a) `DimSection.TeacherStaffKey` — looked up against `DimStaff.Email` to resolve current `StaffKey` (denormalized snapshot for reporting); (b) `FactSectionTeachers.TeacherEmail` — stored verbatim (lowercased) on a row with `TeacherRole = 'Primary'`. The bridge keys on the email itself, not StaffKey, so DimStaff versioning doesn't churn the bridge | [5]Email_Addr |
| EnrollmentCount | INT | Current number of students enrolled in the section. Stored on the dimension to avoid re-aggregating `FactEnrollment` for every Power BI visual that needs it | No_of_students |
| MaxEnrollment | INT | Section capacity. Lower values flag special-program / capped sections | MaxEnrollment |

### SCD lifecycle (warehouse-derived, NOT pulled from PS)

`EffectiveStartDate` and `EffectiveEndDate` are not columns in this export — the merge procedure derives them at ingest from the import date.

**`DimSection` SCD Type 2:**
- New `SectionID` → INSERT row with `EffectiveStartDate = import_date`, `IsCurrent = 1`
- Existing `SectionID` with **all business fields unchanged** → no-op (touch `LastUpdated`)
- Existing `SectionID` with **any business field different** → close current row (`EffectiveEndDate = import_date - 1`, `IsCurrent = 0`) and INSERT new version (`EffectiveStartDate = import_date`, `IsCurrent = 1`). **Does NOT cascade to FactSectionTeachers** — the bridge keys on `SectionID`, not `SectionKey`, so it survives DimSection versioning untouched.
- `SectionID` no longer in import → close current row (`IsCurrent = 0`); do not insert a replacement

**`FactSectionTeachers` Primary rows** seeded from this export (reconciles independently of DimSection):
- New (`SectionID`, primary `TeacherEmail`, `TeacherRole = 'Primary'`) triple → INSERT with `EffectiveStartDate = import_date`, `IsCurrent = 1`
- Same triple still appears → no-op (touch `LastUpdated`)
- Triple drops out (primary teacher email changed, or section retired) → close current row (`EffectiveEndDate = import_date`, `IsCurrent = 0`)

---

## Export 4 — Co-Teachers (→ `FactSectionTeachers`) — *if PS tracks them*

**Purpose:** capture additional non-primary teachers (co-teachers, support staff, substitutes) per section. **Do NOT include the primary teacher** — they're already covered by Export 3.

If PS doesn't track co-teaching at all, **skip this export entirely**. `FactSectionTeachers` will end up populated with primary-teacher rows from Export 3 alone, and that's the complete picture.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | Must match a `SectionID` from the Sections export | ID |
| TeacherEmail | VARCHAR(255) | The non-primary teacher's email (matches `Email` in the Staff export). Stored verbatim (lowercased) on `FactSectionTeachers.TeacherEmail` | [5]Email_Addr |
| TeacherRole | VARCHAR(50) | Expected values: `CoTeacher`, `Support`, `Substitute`. **NOT `Primary`** — that role is reserved for Export 3. PS's equivalent label goes here; we'll map during ingest | Role |

### SCD lifecycle (warehouse-derived, NOT pulled from PS)

Same pattern as the Primary rows from Export 3 — `EffectiveStartDate` and `EffectiveEndDate` are derived at ingest:
- New (`SectionID`, `TeacherEmail`, `TeacherRole`) triple → INSERT with `EffectiveStartDate = import_date`, `IsCurrent = 1`
- Same triple still appears in this import → no-op (touch `LastUpdated`)
- Triple drops out (co-teacher removed, or assignment ended) → close current row (`EffectiveEndDate = import_date`, `IsCurrent = 0`)

The merge procedure reconciles primary and non-primary rows independently within `FactSectionTeachers` — a co-teacher leaving doesn't affect the primary row, and vice versa.

---

## Export 5 — Enrollments (→ `FactEnrollment`)

**Scope — currently active enrollments only**: Generated from the PowerSchool report that filters to enrollments with no `DateLeft`, **plus** any enrollments closed since the last export (i.e. with a `DateLeft` populated). Do not send a full historical roster — the warehouse uses presence in this export plus the `DateLeft` value to drive `ActiveFlag` and close-out logic.

One row per student-section assignment in the pilot schools.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| StudentNumber | BIGINT | Must match a StudentNumber from the Students export | [1]Student_Number |
| SectionID | VARCHAR(50) | Must match a SectionID from the Sections export | SectionID |
| StartDate | DATE | Enrollment start date. PS emits `MM/DD/YYYY` format | DateEnrolled |
| EndDate | DATE | **PS auto-populates `DateLeft` to the section's term-end-date when the student enrolls** (so PS can auto-exit them when the course ends) — it is NOT a "left early" signal by itself. Year-long courses get end-of-June; one-semester courses get end-of-January (S1) or end-of-June (S2). Both can shift to nearest school day. Ingest must compare against `DimTerm`-derived term end: `DateLeft = term end` → still active; `DateLeft < term end` → left early; `DateLeft` blank → still enrolled, `EndDate = NULL` | DateLeft |
| SourceSystemID | VARCHAR(50) | PowerSchool CC table primary key for this enrollment row. Stored for reference/debugging only — NOT used for record matching | ID |

### `ActiveFlag` derivation (not a CSV column)

Same pattern as the Staff export — `ActiveFlag` is derived at ingest, not exported. The merge procedure reconciles each row against prior state:

- Row in import with `EndDate` populated (`DateLeft` from PS) → `ActiveFlag = 0`, `EndDate` written verbatim
- Row in import with `EndDate` blank → `ActiveFlag = 1`, `EndDate = NULL`
- Existing warehouse row **absent** from the current import → close it out:
  - If today is **after** the section's term end (lookup via `DimSection → DimTerm`) → `EndDate = term end date`, `ActiveFlag = 0`
  - If today is **within** the section's term → `EndDate = ingest date`, `ActiveFlag = 0`

This ensures stale enrollments get a sensible `EndDate` even when PS doesn't supply one (e.g. silent withdrawals, mid-year transfers that weren't formally terminated in PS).

---

## Notes for PowerSchool Admin

- **ID consistency is critical**: the same student must have the same `StudentNumber` across all exports and across all future exports. Same rule for `Email` (staff), `SchoolID`, and `SectionID`.
- **No PII beyond what's listed**: do not include SINs, medical info, home addresses, or anything not shown above. Data minimization is part of PIIDPA compliance.
- **File format**: UTF-8 encoding, first row is header. Delimiter and extension depend on the export source — direct table extracts emit TAB-delimited `.text` files (PS default); sqlReports emit comma-delimited `.csv` files with double-quote text qualifier. The ingest pipeline auto-detects delimiter from the header line, so either form works.
- **Filenames don't matter** — the ingest pipeline routes by folder placement, not filename. Drop each export into its dedicated subfolder (`students/`, `staff/`, `sections/`, `section-teachers/`, `enrollments/`) under the OneLake landing zone. PS exports default to long auto-generated names like `AssessmentDataStudentsExport.text`; that's fine. Schools not exported — seeded from provincial directory.
- **Pilot scope**: students export should be filtered to French Immersion program codes only (see "Pilot Program Code Filter" section below). Staff, schools, and sections should be complete (not filtered) — RLS handles the access control.

---

## Pilot Program Code Filter

PowerSchool tracks programs with 4-character codes (letter + 3 digits). For the MVP pilot, **only include students whose `ProgramCode` is in this list**:

| Code | Program | Grade Band |
|---|---|---|
| E015 | Elementary French Immersion | Elementary |
| J015 | Junior High Early French Immersion | Junior High |
| J020 | Junior High Late French Immersion | Junior High |
| S015 | Senior High Early French Immersion | Senior High |
| S020 | Senior High Late French Immersion | Senior High |
| S115 | Senior High Early French Immersion O2 | Senior High |
| S120 | Senior High Late French Immersion O2 | Senior High |
| S215 | Senior High Early French Immersion IB | Senior High |
| S220 | Senior High Late French Immersion IB | Senior High |

**Explicitly excluded from the pilot** (these are French-related but not French Immersion):
- CSAP programs (P010, E010, J010, S010, S110, S210) — French-first-language board, different audience
- Intensive French (E025)
- Integrated French (J025, S025, S125, S225)
- English programs (P005, E005, J005, S005, S105, S205, S305)
- Specialty non-FI programs (S050, S060, S061)

If the pilot teachers include any students outside this code list, let us know and we can adjust the filter.

---

## Tables NOT Requiring PowerSchool Data

For reference, these warehouse tables get their data from other sources (no PowerSchool export needed):

- `DimSchool` — seeded directly from the Nova Scotia Department of Education 2024-2025 Directory of Public Schools (see [sql/scripts/seed_DimSchool_TCRCE.sql](../sql/scripts/seed_DimSchool_TCRCE.sql)). **PS admin still needs to ensure** the `SchoolID` values used in Students, Staff, and Sections exports are the **4-digit provincial school number** (e.g. `'0079'`, `'0167'`) — leading zeros may be stripped by PS on export (ingest will zero-pad), but the underlying number must be the provincial code, not a PS-internal ID
- `DimAssessmentWindow` — populated manually by admins when a new assessment pull is scheduled
- `DimCalendar` — auto-generated date dimension
- `DimProgram` — static reference data (PowerSchool program code categorization); seeded once from [sql/dimensions/DimProgram.sql](../sql/dimensions/DimProgram.sql)
- `DimReadingScale` — static reference data (reading level benchmarks)
- `FactAssessmentReading` / `FactAssessmentWriting` — populated by teachers via Power Apps
- `FactSubmissionAudit` — populated automatically by ingestion and Power Apps
- `vw_StaffSchoolAccess` — view derived live from `FactStaffAssignment` (no rebuild step, no PS data needed beyond what already feeds the Staff export)
