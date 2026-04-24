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
| FirstName | VARCHAR(100) | `DimStaff.FirstName` | | |
| LastName | VARCHAR(100) | `DimStaff.LastName` | | |
| SchoolID | VARCHAR(10) | `FactStaffAssignment.SchoolID` | 4-digit provincial school number (leading zeros normalized during ingest) | |
| RoleCode | VARCHAR(50) | `FactStaffAssignment.RoleCode` | Expected values: `Teacher`, `Administrator`, `Specialist`, `RegionalAnalyst`. PowerSchool's equivalent label goes here; we'll map during ingest | |
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

**What PowerSchool must still match**: the `SchoolID` values used in Students.CurrentSchoolID, Staff.HomeSchoolID, and Sections.SchoolID must all be the **4-digit provincial school number** (e.g. `'0079'`, `'0167'`). If PowerSchool strips leading zeros on export, that's fine — the ingest will zero-pad. But the number itself must be the provincial 4-digit code, not a PowerSchool-internal ID.

---

## Export 4 — Sections (→ `DimSection`)

One row per instructional section in the pilot schools. For now we only need the **primary teacher of record**; co-teaching fields handled in Export 5 below if available.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | **Business key** — region-unique identifier per section | |
| SchoolID | VARCHAR(10) | 4-digit provincial school number the section is in | |
| TermID | INT | PS 4-digit TermID (e.g. `3501` = 2025-2026 Semester 1). Format: `YY` = year-1990, `TT` = 00 Year Long / 01 S1 / 02 S2. Joins to `DimTerm` to decode school year + term | TermID |
| CourseCode | VARCHAR(50) | Course identifier (e.g. 'MATH-3-FR') | |
| TeacherEmail | VARCHAR(255) | **SCD Type 2 trigger** — the teacher-of-record's email (we'll look up the StaffKey during ingest via email match) | |

---

## Export 5 — Section Teachers (→ `FactSectionTeachers`) — *if available*

One row per teacher-section assignment. Include the primary teacher AND any co-teachers/support teachers for that section.

If PowerSchool **only** exports the primary teacher per section (no co-teachers), skip this export — the ingest will fall back to using `DimSection.TeacherStaffID` as the sole entry.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| SectionID | VARCHAR(50) | Must match a SectionID from Sections export | |
| TeacherEmail | VARCHAR(255) | The teacher's email (matches `Email` in the Staff export) | |
| TeacherRole | VARCHAR(50) | Expected values: 'Primary', 'CoTeacher', 'Support', 'Substitute'. PowerSchool's equivalent label goes here; we'll map during ingest | |
| EffectiveStartDate | DATE | When this teacher's assignment to the section began (or school year start if not tracked) | |
| EffectiveEndDate | DATE | When this teacher's assignment ended, or blank/NULL if still active | |

---

## Export 6 — Enrollments (→ `FactEnrollment`)

One row per student-section assignment in the pilot schools.

| Warehouse Field | Type | Description | PowerSchool Field |
|---|---|---|---|
| StudentNumber | BIGINT | Must match a StudentNumber from the Students export | Student_Number |
| SectionID | VARCHAR(50) | Must match a SectionID from the Sections export | |
| StartDate | DATE | Enrollment start date | |
| EndDate | DATE | Enrollment end date, or blank/NULL if still enrolled | |
| ActiveFlag | BIT | 1 = currently enrolled, 0 = dropped/transferred | |

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
- `StaffSchoolAccess` — derived automatically from `DimStaff` during the staff ingest
