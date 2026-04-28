# PowerSchool Field Mapping Worksheet

**Purpose:** Map each warehouse field to its equivalent PowerSchool export field so the PowerSchool admin knows exactly what to include in each CSV export.

**Scope:** MVP pilot — French Immersion programs only. See "Pilot Program Code Filter" section below for the exact list of codes. Request one CSV per export below.

**How to use:** Fill in the rightmost column with the PowerSchool field/column name for each warehouse field. Notes in the right column can include things like "computed from X + Y" or "not available in PowerSchool" if the field can't be directly exported.

---

## Export 1 — Students (→ `DimStudent`)

One row per student enrolled in the French Immersion program. The business key is the provincial **Student Number** (not PowerSchool's DCID) because it survives re-enrollments — if a student leaves and returns they keep the same Student Number but may get a new PowerSchool record.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| StudentNumber | BIGINT | **Business key** — provincial 10-digit student number (PowerSchool's "Student Number" field). Stable across re-enrollments and region transfers; follows the student for life | Student_Number |
| FirstName | VARCHAR(100) | | First_Name |
| MiddleName | VARCHAR(100) | Nullable — include where present. Helps distinguish students with identical first + last names in the same school/grade (common locally) | Middle_Name |
| LastName | VARCHAR(100) | | Last_Name |
| DateOfBirth | DATE | Optional but recommended | DOB |
| CurrentGrade | VARCHAR(10) | **SCD Type 2 trigger** — values like 'P', '1', '2', ... '12' | Grade_Level |
| CurrentSchoolID | VARCHAR(10) | **SCD Type 2 trigger** — 4-digit provincial school number (e.g. `'0167'`). Leading zeros are normalized during ingest | SchoolID |
| ProgramCode | VARCHAR(10) | **SCD Type 2 trigger** — PowerSchool program code (e.g. 'E005', 'J015', 'S120'). 4-character format: letter (grade band) + 3 digits. See "Pilot Program Code Filter" section below | NS_Program |
| EnrollStatus | INT | PS tri-state value stored verbatim: `1` = currently enrolled, `0` = inactive, `-1` = pre-registered (registered but not yet started at the school) | Enroll_Status |
| SourceSystemID | VARCHAR(50) | PowerSchool DCID (internal database ID). Stored for reference/debugging only — NOT used for record matching | ID |

---

## Export 2 — Staff (→ `DimStaff` + `FactStaffAssignment`)

**Scope — currently active staff only**: Generated from the PowerSchool report that filters to staff with active status. Includes **teachers, school specialists, and administrators**. Do **not** send inactive staff, former employees, or a full historical roster. The warehouse uses presence in this export to drive `ActiveFlag` — anyone not in the current import automatically transitions to inactive (see note below).

**Grain — expected duplicates**: The PS report emits **one row per staff-school-role combination**. A person who works at two schools appears twice; a vice-principal who also teaches one class appears twice (once as 'Administrator', once as 'Teacher'); an itinerant specialist serving five schools appears five times. **This is expected and required** — the warehouse needs that full grain to preserve multi-school and multi-role detail. Just make sure the `Email_Addr` is identical across rows for the same person.

### How the CSV feeds two tables

The ingest splits each raw row into two destinations:

- **`DimStaff`** — person-level identity, one row per unique email (collapsed). Versioned by SCD Type 2 only when a person goes active↔inactive.
- **`FactStaffAssignment`** — the bridge, preserves the full email×school×role grain. Versioned by effective dates; never collapses.

### Fields required in the CSV

| CSV Column | Type | Feeds | Description | PowerSchool Field |
|---|---|---|---|---|
| Email | VARCHAR(255) | `DimStaff.Email` (dedupe key) + `FactStaffAssignment.StaffKey` lookup | **Business key** — Entra ID UPN. Must match exactly what the user signs into Teams with. Will be lowercased during ingest | Email_Addr |
| FirstName | VARCHAR(100) | `DimStaff.FirstName` | | First_Name |
| LastName | VARCHAR(100) | `DimStaff.LastName` | | Last_Name |
| HomeSchoolID | VARCHAR(10) | `DimStaff.HomeSchoolID` | Per-person primary/home school (4-digit provincial number). Sourced from a joined PS table; same value on every row of a multi-row staff member. Leave blank for itinerant staff with no single home school | HomeSchoolID |
| CanChangeSchool | VARCHAR(255) | `DimStaff.CanChangeSchool` | Per-person semicolon-separated list of school IDs the user can navigate to in PS (e.g. `0;79;167;1199;999999`). Sourced from a joined PS table; same value on every row of a multi-row staff member. Populated only for staff with multi-school access; leave blank otherwise. Special markers: `0` = district-level tier, `999999` = graduates pseudo-school | CanChangeSchool |
| SchoolID | VARCHAR(10) | `FactStaffAssignment.SchoolID` | 4-digit provincial school number for **this row's** assignment (leading zeros normalized during ingest). Different from HomeSchoolID — this varies per row when staff appear multiple times | SchoolID |
| RoleCode | VARCHAR(50) | `FactStaffAssignment.RoleCode` | Expected values: `Teacher`, `Administrator`, `Specialist`, `RegionalAnalyst`. PowerSchool's equivalent label goes here; we'll map during ingest | Group |
| ID | VARCHAR(50) | `FactStaffAssignment.SourceSystemID` | PowerSchool staff record ID for this specific email×school×role row. Reference/debug only, NOT used for matching | ID |

### `ActiveFlag` derivation (not a CSV column)

The PS report already filters to active staff, so every row in the export is active by definition. The merge procedure derives `ActiveFlag` on `DimStaff` via reconciliation against what it knew previously:

- Email present in the current import → `DimStaff.ActiveFlag = 1`
- Email already in `DimStaff` but **absent** from the current import → SCD Type 2 transition to `ActiveFlag = 0` (close current version, insert new inactive version)
- Returning staff (inactive → present again) → SCD Type 2 transition back to `ActiveFlag = 1`

Same pattern applies to `FactStaffAssignment` rows at the (email × school × role) grain: a triple that disappears from one import gets `EffectiveEndDate` set and `IsCurrent = 0`; a new triple gets inserted with today as `EffectiveStartDate`.

"Inactive" in the warehouse does **not** mean "no longer employed" — it means "dropped out of the active-staff report this cycle". Possible causes: on leave, sabbatical, retired, role change, left the region. Rows are retained forever so historical fact-table joins on `StaffKey` never break.

Because of this logic, **no `Status` / active-flag column is needed in the CSV** — it's implied by inclusion.

---

## Export 3 — Schools — *skipped*

**Schools are not requested from PowerSchool.** `DimSchool` is seeded directly from the Nova Scotia Department of Education 2024-2025 Directory of Public Schools (see [sql/scripts/seed_DimSchool_TCRCE.sql](../sql/scripts/seed_DimSchool_TCRCE.sql)). This is the authoritative provincial source.

**What PowerSchool must still match**: the `SchoolID` values used in `Students.CurrentSchoolID`, `FactStaffAssignment.SchoolID` (sourced from the Staff export), and `Sections.SchoolID` must all be the **4-digit provincial school number** (e.g. `'0079'`, `'0167'`). If PowerSchool strips leading zeros on export, that's fine — the ingest will zero-pad. But the number itself must be the provincial 4-digit code, not a PowerSchool-internal ID.

---

## Export 4 — Sections (→ `DimSection` + `FactSectionTeachers`)

One row per instructional section in the pilot schools. The primary teacher's email feeds **both** targets:
- `DimSection.TeacherStaffKey` — canonical teacher-of-record on the section dim
- One `FactSectionTeachers` row per section with `TeacherRole = 'Primary'`

Co-teaching arrangements (if PS tracks them) are handled by Export 5 below — **do not** include co-teachers here.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | **Business key** — region-unique identifier per section | ID |
| SchoolID | VARCHAR(10) | 4-digit provincial school number the section is in | SchoolID |
| TermID | INT | PS 4-digit TermID (e.g. `3501` = 2025-2026 Semester 1). Format: `YY` = year-1990, `TT` = 00 Year Long / 01 S1 / 02 S2. Joins to `DimTerm` to decode school year + term | TermID |
| CourseCode | VARCHAR(50) | Course identifier (e.g. 'MATH-3-FR') | Course_Number |
| PrimaryTeacherEmail | VARCHAR(255) | The teacher-of-record's email. On ingest: looked up against `DimStaff.Email` to resolve `StaffKey`, then written to (a) `DimSection.TeacherStaffKey` and (b) one `FactSectionTeachers` row per section with `TeacherRole = 'Primary'`. **SCD Type 2 trigger for DimSection** — a change here closes the current section row and opens a new version | [39]Email_Addr |

### SCD lifecycle (warehouse-derived, NOT pulled from PS)

`EffectiveStartDate` and `EffectiveEndDate` are not columns in this export — the merge procedure derives them at ingest from the import date.

**`DimSection` SCD Type 2:**
- New `SectionID` → INSERT row with `EffectiveStartDate = import_date`, `IsCurrent = 1`
- Existing `SectionID` with **same** `PrimaryTeacherEmail` → Type 1 update only (CourseCode, etc.)
- Existing `SectionID` with **different** `PrimaryTeacherEmail` → close current row (`EffectiveEndDate = import_date - 1`, `IsCurrent = 0`) and INSERT new version (`EffectiveStartDate = import_date`, `IsCurrent = 1`)
- `SectionID` no longer in import → close current row (`IsCurrent = 0`); do not insert a replacement

**`FactSectionTeachers` Primary rows** seeded from this export:
- New (`SectionKey`, primary `StaffKey`) → INSERT with `EffectiveStartDate = import_date`, `IsCurrent = 1`, `TeacherRole = 'Primary'`
- Same triple still appears → no-op (touch `LastUpdated`)
- Triple drops out (primary teacher changed, or section retired) → close current row (`EffectiveEndDate = import_date`, `IsCurrent = 0`)

---

## Export 5 — Co-Teachers (→ `FactSectionTeachers`) — *if PS tracks them*

**Purpose:** capture additional non-primary teachers (co-teachers, support staff, substitutes) per section. **Do NOT include the primary teacher** — they're already covered by Export 4.

If PS doesn't track co-teaching at all, **skip this export entirely**. `FactSectionTeachers` will end up populated with primary-teacher rows from Export 4 alone, and that's the complete picture.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | Must match a `SectionID` from the Sections export | ID |
| TeacherEmail | VARCHAR(255) | The non-primary teacher's email (matches `Email` in the Staff export). On ingest: looked up against `DimStaff.Email` to resolve `StaffKey` | [39]Email_Addr |
| TeacherRole | VARCHAR(50) | Expected values: `CoTeacher`, `Support`, `Substitute`. **NOT `Primary`** — that role is reserved for Export 4. PS's equivalent label goes here; we'll map during ingest | Role |

### SCD lifecycle (warehouse-derived, NOT pulled from PS)

Same pattern as the Primary rows from Export 4 — `EffectiveStartDate` and `EffectiveEndDate` are derived at ingest:
- New (`SectionKey`, `StaffKey`, `TeacherRole`) triple → INSERT with `EffectiveStartDate = import_date`, `IsCurrent = 1`
- Same triple still appears in this import → no-op (touch `LastUpdated`)
- Triple drops out (co-teacher removed, or assignment ended) → close current row (`EffectiveEndDate = import_date`, `IsCurrent = 0`)

The merge procedure reconciles primary and non-primary rows independently within `FactSectionTeachers` — a co-teacher leaving doesn't affect the primary row, and vice versa.

---

## Export 6 — Enrollments (→ `FactEnrollment`)

**Scope — currently active enrollments only**: Generated from the PowerSchool report that filters to enrollments with no `DateLeft`, **plus** any enrollments closed since the last export (i.e. with a `DateLeft` populated). Do not send a full historical roster — the warehouse uses presence in this export plus the `DateLeft` value to drive `ActiveFlag` and close-out logic.

One row per student-section assignment in the pilot schools.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| StudentNumber | BIGINT | Must match a StudentNumber from the Students export | [1]Student_Number |
| SectionID | VARCHAR(50) | Must match a SectionID from the Sections export | SectionID |
| StartDate | DATE | Enrollment start date | DateEnrolled |
| EndDate | DATE | Enrollment end date, or blank/NULL if still enrolled | DateLeft |
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
- **CSV format**: UTF-8 encoding, comma-delimited, double-quote text qualifier, first row is header.
- **One export = one CSV file**, named `students.csv`, `staff.csv`, `sections.csv`, `section-teachers.csv`, `enrollments.csv`. (Schools not exported — seeded from provincial directory.)
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

- `DimAssessmentWindow` — populated manually by admins when a new assessment pull is scheduled
- `DimCalendar` — auto-generated date dimension
- `DimProgram` — static reference data (PowerSchool program code categorization); seeded once from [sql/dimensions/DimProgram.sql](../sql/dimensions/DimProgram.sql)
- `DimReadingScale` — static reference data (reading level benchmarks)
- `FactAssessmentReading` / `FactAssessmentWriting` — populated by teachers via Power Apps
- `FactSubmissionAudit` — populated automatically by ingestion and Power Apps
- `vw_StaffSchoolAccess` — view derived live from `FactStaffAssignment` (no rebuild step, no PS data needed beyond what already feeds the Staff export)
