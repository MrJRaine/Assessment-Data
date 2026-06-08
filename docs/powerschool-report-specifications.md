# PowerSchool Report Specifications

**Audience:** PowerSchool administrator.

**Purpose:** Specifications for five SQL reports to be authored in PowerSchool for the Regional Student Assessment Data Platform. Each report is run by individual users on demand and produces a downloadable file. This document defines, for each report: what the data is used for, the source table, the fields to include, formatting expectations, and naming conventions. One section per report.

**Scope:** All programs (English + French) and all schools. The Students report is **not** filtered by program. The Sections and Enrollments reports are filtered to the **current school year**.

---

## Conventions that apply to every report

- **Output format:** comma-separated values (CSV) with a double-quote (`"`) text qualifier and a header row — the standard sqlReport download.
- **Encoding:** UTF-8.
- **Column order:** produce the columns in the order shown in each report.
- **Dates:** `MM/DD/YYYY` (e.g. `10/13/2014`).
- **Leave values in their native PowerSchool form** — do not re-code grade values, Yes/No flags, etc. The platform interprets the raw values; re-coding them upstream causes errors.
- **School numbers:** use the **4-digit provincial school number** (e.g. `0167`, `0079`) — *not* a PowerSchool-internal school ID. Leading zeros may be stripped on export; that is fine.
- **Email:** the staff member's sign-in email (Entra/Teams UPN). Any letter case is acceptable.
- **Identifier consistency:** the same student number, staff email, school number, and section ID must be used across all five reports and across every future run.
- **Include only the fields listed** — no SINs, medical information, home addresses, or any field not specified (privacy / data-minimization).
- **Cross-table field references:** where a field is pulled from a related table, it is written with that table's number in square brackets — e.g. `[5]Email_Addr` means the `Email_Addr` field from table 5 (Teachers).

---

## Report 1 — Students

### Function
The master list of students the platform tracks. Every reading and writing assessment, every class roster, and every demographic breakdown ties back to a student from this report. The platform keeps a history of student changes (grade, school, program, name, etc.) so past reports stay accurate even after a student moves or their record is updated.

### Source table
**Students (1)**

### Filter
- `Enroll_Status IN (0, -1)` — **Active** (`0`) and **Pre-Enrolled** (`-1`, registered but not yet started). Exclude Inactive (`2`) and Graduated (`3`).
- All programs, all schools — no program-code filter.

### Fields (in this order)
| # | Column name | PowerSchool field | Type | Description |
|---|---|---|---|---|
| 1 | `Student_Number` | `Student_Number` | text | Provincial 10-digit student number — the stable, lifelong student identifier. |
| 2 | `ID` | `ID` | text | PowerSchool DCID. Reference only. |
| 3 | `First_Name` | `First_Name` | text | |
| 4 | `Middle_Name` | `Middle_Name` | text | Optional; helps tell apart students with the same first + last name. |
| 5 | `Last_Name` | `Last_Name` | text | |
| 6 | `SchoolID` | `SchoolID` | text | 4-digit provincial school number. |
| 7 | `Grade_Level` | `Grade_Level` | text | `0` = Primary, `-1` = Pre-Primary, `1`–`12` otherwise. Leave as-is. |
| 8 | `NS_Program` | `NS_Program` | text | 4-character program code (letter + 3 digits), e.g. `E005`, `J015`, `S120`. |
| 9 | `Home_Room` | `Home_Room` | text | Optional. |
| 10 | `Gender` | `Gender` | text | `M` / `F` / `X`. |
| 11 | `DOB` | `DOB` | text | `MM/DD/YYYY`. |
| 12 | `NS_AssigndIdentity_African` | `NS_AssigndIdentity_African` | text | Self-ID African descent. `Yes` or empty. **Note the literal extra `d` in `Assignd`** — that is the real column name. |
| 13 | `NS_aboriginal` | `NS_aboriginal` | text | Self-ID Indigenous descent. `1` (Yes) / `2` (No) / empty. |
| 14 | `CurrentIPP` | `CurrentIPP` | text | Has an IPP. `Y` / `N` / empty. |
| 15 | `CurrentAdap` | `CurrentAdap` | text | Has adaptations. `Y` / `N` / empty. |
| 16 | `Enroll_Status` | `Enroll_Status` | text | `0` = Active, `-1` = Pre-Enrolled. |

### Formatting expectations
- Emit the raw coded values shown above (`0`/`-1` grades; `Yes`/empty; `1`/`2`/empty; `Y`/`N`/empty).
- Dates as `MM/DD/YYYY`.
- An empty cell for the self-ID, IPP, or adaptations fields means "not declared" — leave it blank rather than entering a value.

### Naming conventions
- Use the exact column names listed above, in that order.
- `Student_Number` is the canonical student identifier — it must match the value used in the Enrollments report and every future run.

---

## Report 2 — Staff

### Function
The list of staff represented in the platform, and the school(s) and role(s) each one holds. This determines who can sign in and which school's data each administrator or specialist is able to see.

### Source table
**Teachers (5)** (with `HomeSchoolID` and `CanChangeSchool` joined from the related access table).

### Filter
- Currently active staff only (teachers, school specialists, administrators).
- Do not include inactive or former staff.

### Grain — expected duplicates
**One row per person × school × role.** A person at two schools appears twice; a vice-principal who also teaches appears twice (once per role); an itinerant specialist serving five schools appears five times. This is expected — do not collapse. The per-person fields (`First_Name`, `Last_Name`, `Title`, `HomeSchoolID`, `CanChangeSchool`, `Group`) must be identical across all rows for the same email; the per-row fields (`SchoolID`, `ID`) vary.

### Fields (in this order)
| # | Column name | PowerSchool field | Type | Description |
|---|---|---|---|---|
| 1 | `Email_Addr` | `Email_Addr` | text | Staff sign-in email (Entra/Teams UPN) — the canonical staff identifier. |
| 2 | `First_Name` | `First_Name` | text | Per-person. |
| 3 | `Last_Name` | `Last_Name` | text | Per-person. |
| 4 | `Title` | `Title` | text | Job title (e.g. `Vice Principal`, `Educational Assistant`). Per-person, optional. |
| 5 | `HomeSchoolID` | `HomeSchoolID` | text | Per-person home school (4-digit). `0` for district-level staff with no single home school; blank for itinerant. |
| 6 | `SchoolID` | `SchoolID` | text | The school for **this row's** assignment (4-digit) — varies per row. `0` for the district-tier row. |
| 7 | `CanChangeSchool` | `CanChangeSchool` | text | Per-person semicolon-separated school list (e.g. `0;79;167;1199;999999`). Blank for single-school staff. |
| 8 | `Group` | `Group` | text | PowerSchool role/group number. Output exactly as PowerSchool stores it. |
| 9 | `ID` | `ID` | text | PowerSchool staff record ID for this row. |

### Formatting expectations
- Output `Group` as the **numeric** PowerSchool value — do not translate it to a role name.
- Pass the `0` markers in `HomeSchoolID` / `SchoolID` and the `0` / `999999` markers in `CanChangeSchool` through exactly as PowerSchool stores them.
- No status/active column is needed — including a staff member means they are active.

### Naming conventions
- Use the exact column names listed above, in that order.
- `Email_Addr` is the canonical staff identifier — it must match the teacher emails used in the Sections and Co-Teachers reports.

---

## Report 3 — Sections

### Function
The class sections offered this year and the teacher of record for each. Sections connect students to teachers and populate the class/section pickers teachers use when entering assessments. The current enrolled count is included so it doesn't have to be recalculated elsewhere.

### Source table
**Sections (3)** (with course name joined from Courses, and primary teacher email joined from Teachers).

### Filter
- **Current school year only.** In PowerSchool this is the TermID range for the active year — for example, 2025-2026 is `TermID >= 3500 AND TermID < 3600`. **The report must select whatever the current school year is at run time**, not a hard-coded past year. (Each year shifts the range up by 100, e.g. `3600`–`3700` for 2026-2027.)
- All schools.

### Fields (in this order)
| # | Column name | PowerSchool field | Type | Description |
|---|---|---|---|---|
| 1 | `ID` | `ID` | text | Section ID — the canonical section identifier. |
| 2 | `SchoolID` | `SchoolID` | text | 4-digit provincial school number. |
| 3 | `TermID` | `TermID` | text | 4-digit term (e.g. `3501` = 2025-2026 Semester 1). |
| 4 | `Course_Number` | `Course_Number` | text | Course code (e.g. `MATH-3-FR`). |
| 5 | `Section_Number` | `Section_Number` | text | School-set section number (e.g. `01`). |
| 6 | `[2]course_name` | `[2]course_name` | text | Human-readable course name (from table 2, Courses). |
| 7 | `No_of_students` | `No_of_students` | text (number) | Current enrolled count. |
| 8 | `MaxEnrollment` | `MaxEnrollment` | text (number) | Section capacity. |
| 9 | `[5]Email_Addr` | `[5]Email_Addr` | text | Primary teacher's email (from table 5, Teachers). Must match a staff email. |

### Formatting expectations
- `TermID` as the 4-digit number; `No_of_students` and `MaxEnrollment` as plain integers.
- `SchoolID` as the 4-digit provincial number.

### Naming conventions
- Use the exact column names listed above, in that order (including the bracketed `[2]course_name` and `[5]Email_Addr`).
- `ID` is the canonical section identifier — it must match the section IDs used in the Co-Teachers and Enrollments reports.

---

## Report 4 — Co-Teachers *(optional)*

### Function
Additional, **non-primary** teachers assigned to a section — co-teachers, support, substitutes — so they also get access to that section's students. **Skip this report entirely if PowerSchool does not track co-teaching.** **Do not include the primary teacher here** — they come from the Sections report.

### Source
PowerSchool sqlReport (e.g. *Reports → sqlReports → Teacher → "Find Co-Teachers"*).

### Filter
- Current school year.

### Fields (in this order)
| # | Column name | PowerSchool field | Type | Description |
|---|---|---|---|---|
| 1 | `School` | (report label) | text | Reference only. |
| 2 | `TermID` | (report label) | text | Reference only. |
| 3 | `Course` | (report label) | text | Reference only. |
| 4 | `Section` | (report label) | text | Reference only. |
| 5 | `Teacher` | (report label) | text | `LastName, FirstName`. Contains a comma — the double-quote qualifier is required. Reference only. |
| 6 | `Email` | `[5]Email_Addr` | text | The co-teacher's email — must match a staff email. |
| 7 | `Role` | `Role` | text | The co-teaching role (e.g. co-teacher, support, substitute). **Never the primary teacher.** |
| 8 | `SectionID` | `ID` | text | Must match a section ID from the Sections report. |

### Formatting expectations
- Comma-separated, double-quote text qualifier (**required** — the `Teacher` field contains a comma).
- The `Role` value must never be the primary teacher's role; primary teachers come from the Sections report only.

### Naming conventions
- Use the exact column names listed above, in that order.

---

## Report 5 — Enrollments

### Function
Which students are in which sections. This is what places each student on the correct teacher's roster and determines which students a teacher can enter assessments for. One row per student-section assignment.

### Source table
**CC (4)** — the PowerSchool course-enrollment table.

### Filter
- **Current school year only** — same TermID rule as the Sections report (e.g. `TermID >= 3500 AND TermID < 3600` for 2025-2026; select the current year at run time, not a hard-coded past year).
- Include currently-active enrollments, plus any enrollments closed since the previous run (those with a `DateLeft`). Do not send a full historical roster.

### Fields (in this order)
| # | Column name | PowerSchool field | Type | Description |
|---|---|---|---|---|
| 1 | `[1]Student_Number` | `[1]Student_Number` | text | Provincial student number (from table 1, Students). Must match a student number from the Students report. |
| 2 | `SectionID` | `SectionID` | text | Must match a section ID from the Sections report. |
| 3 | `DateEnrolled` | `DateEnrolled` | text | Enrollment start date. `MM/DD/YYYY`. |
| 4 | `DateLeft` | `DateLeft` | text | See note below. `MM/DD/YYYY` or empty. |
| 5 | `ID` | `ID` | text | Enrollment record ID. Reference only. |

### Formatting expectations — note on `DateLeft`
PowerSchool automatically fills `DateLeft` with the section's term-end date when a student enrolls (so it can auto-exit the student when the course ends). It is **not** by itself a "left early" signal. Emit `DateLeft` exactly as PowerSchool holds it — do not blank it out or change it. (`DateLeft` earlier than the term-end date means the student actually left early; equal to the term-end date, or empty, means still enrolled.)

### Naming conventions
- Use the exact column names listed above, in that order (including the bracketed `[1]Student_Number`).

---

## A note on schools

There is **no school report** — school details come from the provincial directory. The only requirement here is that the `SchoolID` columns in the Students, Staff, and Sections reports use the **4-digit provincial school number** (e.g. `0079`, `0167`), not a PowerSchool-internal ID.
