# PowerSchool Export Procedures

**Purpose:** Operational record of how each test CSV is being pulled from PowerSchool — which table/report, which filters, when. This is a working document; fill in the blanks for each pull and update notes as quirks come up.

**Scope:** MVP pilot (French Immersion) test data pulled by Jeff using own PS access. Once the schema and ingest are validated end-to-end, the PS admin will reproduce these pulls as scheduled SQL reports.

**Reference:** Field semantics and warehouse rationale are in [powerschool-field-mapping.md](powerschool-field-mapping.md). This doc is the *how* (where the data comes from); that doc is the *why* (what each field means).

---

## Export 1 — Students → `DimStudent`

**Source table / report:** "Students (1)"

**Filters applied:** Enroll_Status = 0 (Indicates an actively enrolled student)

**Output filename:** `students.csv`

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
| SelfIDAfrican | NS_AssignIdentity_African |
| SelfIDIndigenous | NS_aboriginal |
| CurrentIPP | CurrentIPP |
| CurrentAdap | CurrentAdap |
| SourceSystemID | ID |

**Required filter (pilot scope):** `NS_Program` IN (`E015`, `J015`, `J020`, `S015`, `S020`, `S115`, `S120`, `S215`, `S220`) — French Immersion only.

**Notes:** ____________________________________________

---

## Export 2 — Staff → `DimStaff` + `FactStaffAssignment`

**Source table / report:** "Teachers (5)"

**Filters applied:** Status = 1 (Indicates active staff)

**Output filename:** `staff.csv`

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

**Notes:** ____________________________________________

---

## Export 3 — Sections → `DimSection` + `FactSectionTeachers` (Primary)

**Source table / report:** "Sections (3)"

**Filters applied:** TermID >= 3500 ; TermID < 3600 (Limits to sections from the 2025-2026 School year, filter value will change each year.)

**Output filename:** `sections.csv`

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

**Notes:** ____________________________________________

---

## Export 4 — Co-Teachers → `FactSectionTeachers` (non-Primary)

**Source table / report:** ____________________________________________

**Filters applied:** ____________________________________________

**Output filename:** `section-teachers.csv`

**Skip this export entirely if PS does not track co-teaching.** Do NOT include the primary teacher here — they come from Export 3.

| Warehouse Field | PowerSchool Field |
|---|---|
| SectionID | ID |
| TeacherEmail | [5]Email_Addr |
| TeacherRole | Role |

**Notes:** ____________________________________________

---

## Export 5 — Enrollments → `FactEnrollment`

**Source table / report:** ____________________________________________

**Filters applied:** ____________________________________________

**Output filename:** `enrollments.csv`

**Scope:** include currently-active enrollments AND any enrollments closed since last pull (i.e. with `DateLeft` populated). Do NOT send a full historical roster.

| Warehouse Field | PowerSchool Field |
|---|---|
| StudentNumber | [1]Student_Number |
| SectionID | SectionID |
| StartDate | DateEnrolled |
| EndDate | DateLeft |
| SourceSystemID | ID |

**Notes:** ____________________________________________

---

## Schools — *not exported from PowerSchool*

`DimSchool` is seeded from the Nova Scotia Department of Education 2024-2025 Directory of Public Schools (see [seed_DimSchool_TCRCE.sql](../sql/scripts/seed_DimSchool_TCRCE.sql)). PowerSchool's `SchoolID` values must match the 4-digit provincial school numbers used in that seed.

---

## General Conventions

- **Encoding:** UTF-8
- **Delimiter:** comma
- **Text qualifier:** double quote
- **Header row:** required
- **Number padding:** ingest will zero-pad `SchoolID` to 4 digits, so leading-zero stripping in PS is fine
- **Email casing:** ingest will lowercase, so original casing doesn't matter
- **Source table notation:** entries in "Source table / report" are written as `"TableName (N)"` where `N` is the PowerSchool internal table number (e.g. `"Students (1)"`, `"Teachers (5)"`). The same `N` is used in field references like `[5]Email_Addr` to indicate the field is pulled from a related table — table 5 (Teachers) in that example. This makes the export reproducible by the PS admin without ambiguity about which table a field came from.

---

## Pull History

| Date | Export(s) | Notes |
|---|---|---|
| | | |
| | | |
| | | |
