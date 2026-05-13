# Warehouse Schema — Full Reference for Power Apps Build

Comprehensive list of every table, view, and stored procedure in the
existing `Assessment_Warehouse` Fabric Warehouse that the Power Apps
canvas app reads from or writes to (directly or transitively).

Paste this into the Plan tool when it asks about your data model. **All
objects below already exist** — do NOT propose creating new Dataverse
tables or alternative storage. The app connects via the SQL Server
connector with Microsoft Entra ID (Integrated) authentication.

---

## Connection

| Property | Value |
|---|---|
| Server / workspace | `Regional_Data_Portal` (Microsoft Fabric workspace) |
| Database / warehouse | `Assessment_Warehouse` |
| Region | Canada East (PIIDPA-compliant) |
| Capacity | Fabric F8 |
| Connector | SQL Server (built-in Power Apps connector) |
| Authentication | Microsoft Entra ID — Integrated (the calling user's M365 identity) |
| Object naming in Power Apps | Tables exposed as `[dbo].[ObjectName]`. Stored procedures exposed with dots stripped: `dbo.usp_X` → `dbouspX` |

---

## Object inventory

### Used DIRECTLY by the app (4 reads, 1 write)

| Object | Type | Used by | Direction |
|---|---|---|---|
| `vw_UserAssessmentWindows` | View | scrWindowSelect | READ |
| `vw_TeacherGroups` | View | scrGroupSelect | READ |
| `vw_TeacherRoster` | View | scrRosterGrid | READ |
| `DimReadingScale` | Table | scrRosterGrid (cmbNewLevel dropdown) | READ |
| `DimStaff` | Table | App.OnStart (gblIsAdminOrAnalyst LookUp) | READ |
| `usp_UpsertReadingAssessment` | Stored procedure | scrRosterGrid (Save) | WRITE |

### Referenced indirectly (the views above join through these — listed so the Plan tool understands relationships, but the app does NOT query them directly)

| Object | Type | Purpose |
|---|---|---|
| `DimStudent` | Table (SCD Type 2) | Student profile over time |
| `DimSection` | Table (SCD Type 2) | Course sections over time |
| `DimSchool` | Table (SCD Type 1) | School reference data |
| `DimProgram` | Table (static) | PowerSchool program code lookup |
| `DimGrade` | Table (static) | Grade code lookup with ordering |
| `DimRole` | Table (static) | PowerSchool role-code lookup |
| `DimGender` | Table (static) | Gender code lookup |
| `DimTerm` | Table (static) | PS term-code lookup |
| `DimCalendar` | Table (static) | Standard date dimension |
| `DimAssessmentWindow` | Table | Assessment window definitions |
| `DimReadingBenchmark` | Table (static) | Reading-level expectations by grade × month |
| `FactEnrollment` | Fact table | Student-to-section enrollments |
| `FactSectionTeachers` | Bridge table | Teacher-to-section assignments (supports co-teaching) |
| `FactStaffAssignment` | Bridge table | Staff-to-school-to-role assignments |
| `FactAssessmentReading` | Fact table | Reading assessments (the upsert proc writes here) |
| `FactAssessmentWriting` | Fact table | Writing assessments (Phase 5+; not used by MVP) |
| `FactSubmissionAudit` | Audit table | Audit log of all writes (the upsert proc appends here) |
| `FactDataQualityAudit` | Audit table | Data quality check log |
| `StaffSchoolAccess` | Materialized RLS table | School-tier staff access (used by `vw_UserAssessmentWindows` etc.) |

---

## DIRECT-ACCESS objects (full column details)

### View: `vw_UserAssessmentWindows`

RLS-scoped to caller. Returns one row per (caller, applicable window) tuple.

| Column | Type | Description |
|---|---|---|
| AssessmentWindowID | BIGINT | Primary key of the window |
| WindowName | VARCHAR(100) | Display name |
| AssessmentType | VARCHAR(20) | `'Reading'` / `'Writing'` / `'Math'` (MVP only seeds Reading) |
| SchoolYear | VARCHAR(9) | e.g. `'2025-2026'` |
| StartDate | DATE | |
| EndDate | DATE | |
| MinGrade | VARCHAR(10) | Joins `DimGrade.GradeCode` |
| MaxGrade | VARCHAR(10) | Joins `DimGrade.GradeCode` |
| ProgramFamily | VARCHAR(50) | NULL = all programs; else `'English'` / `'French Immersion'` / `'French Second Language'` |
| WindowStatus | VARCHAR(20) | One of `'Open'` / `'ClosesToday'` / `'Closed'` / `'Upcoming'` (computed from today vs StartDate/EndDate) |
| ApplicableStudentCount | INT | Distinct applicable students for this user + window |
| EnteredStudentCount | INT | Of those, how many already have a `FactAssessmentReading` row for this window |

### View: `vw_TeacherGroups`

RLS-scoped to caller. Returns one row per (caller, applicable window, group) tuple.

| Column | Type | Description |
|---|---|---|
| AssessmentWindowID | BIGINT | Filter target |
| GroupKey | VARCHAR(60) | `'HR:' + Homeroom` for PP-9 students; `'SEC:' + SectionID` for 10-12 / RG |
| GroupType | VARCHAR(10) | `'Homeroom'` or `'Section'` |
| GroupLabel | VARCHAR(255) | Display string (e.g. `"Homeroom 5A"` or `"01 — French 12"`) |
| Grade | VARCHAR(10) | Shared grade of students in this group (`DimGrade.GradeCode`) |
| ApplicableStudentCount | INT | Students in this group applicable to this window |
| EnteredStudentCount | INT | Of those, how many have entered an assessment |

### View: `vw_TeacherRoster`

RLS-scoped to caller. Returns one row per (caller, applicable window, group, student) with existing assessment value if any.

| Column | Type | Description |
|---|---|---|
| AssessmentWindowID | BIGINT | Filter target |
| GroupKey | VARCHAR(60) | Filter target (matches `gblSelectedGroup.GroupKey`) |
| StudentKey | BIGINT | Internal surrogate key |
| StudentNumber | BIGINT | Provincial 10-digit student #; required for the upsert proc |
| FirstName | VARCHAR(100) | |
| LastName | VARCHAR(100) | |
| Grade | VARCHAR(10) | Student's grade at the window's effective date |
| ProgramCode | VARCHAR(10) | PowerSchool program code (e.g. `'E015'`) |
| ProgramFamily | VARCHAR(50) | Resolved from `DimProgram` (e.g. `'French Immersion'`) |
| ExistingReadingAssessmentID | BIGINT | NULL if no assessment entered |
| ExistingReadingScaleID | BIGINT | NULL if none. Used for `cmbNewLevel.DefaultSelectedItems` |
| ExistingScaleValue | VARCHAR(10) | The level code (e.g. `'C'`, `'Z'`, `'30+'`) — display in `lblExistingLevel` |
| ExistingAssessmentDate | DATE | NULL if no assessment entered |

### Table: `DimReadingScale`

Reference data — list of valid reading levels. The dropdown source for `scrRosterGrid.cmbNewLevel`.

| Column | Type | Description |
|---|---|---|
| ReadingScaleID | BIGINT (IDENTITY) | PK; passed to the upsert proc |
| LevelCode | VARCHAR(10) | Display value (e.g. `'A'`, `'DT'`, `'30+'`) |
| LevelOrder | INT | Sort order. EN: DT=0, A=1, …, Z=26. FR: TD=0, 1-30 = 1-30, 30+ = 31 |
| ScaleSystem | VARCHAR(20) | `'EN_Reading'` or `'FR_Reading'`. Must match the window's ScaleSystem |
| Description | VARCHAR(200) | Optional |
| ActiveFlag | BIT | Filter to `true` |
| LastUpdated | DATETIME2(0) | |

### Table: `DimStaff` (subset used by Power Apps)

The full table is SCD Type 2 (many versions per staff). Power Apps only reads the **current** row (`IsCurrent = true`) for the calling user, to detect admin/analyst status.

| Column | Type | Description |
|---|---|---|
| StaffKey | BIGINT (IDENTITY) | Surrogate key (one per version) |
| Email | VARCHAR(255) | Business key (M365/Entra UPN, lowercased) — match against `Lower(User().Email)` |
| FirstName | VARCHAR(100) | |
| LastName | VARCHAR(100) | |
| Title | VARCHAR(100) | e.g. `"Principal"`, `"Educational Assistant"` |
| HomeSchoolID | VARCHAR(10) | Primary school, NULL for itinerant staff |
| AccessLevel | VARCHAR(50) | `NULL` for teachers; `'Administrator'` / `'SpecialistTeacher'` / `'RegionalAnalyst'` for everyone else. **This is the only column Power Apps actually cares about.** |
| ActiveFlag | BIT | Currently-active staff: `true` |
| IsCurrent | BIT | Current SCD version: filter to `true` |
| EffectiveStartDate, EffectiveEndDate | DATE | SCD versioning |
| LastUpdated | DATETIME2(0) | |

(Other columns exist — `CanChangeSchool`, `IsDistrictLevel` — but the app doesn't use them. They drive `StaffSchoolAccess`, which the secured views use.)

### Stored procedure: `usp_UpsertReadingAssessment`

Inserts a new reading assessment if `(StudentKey, AssessmentWindowID)` has no row; otherwise updates the existing row's score + audit columns. StudentKey and AssessmentDate are frozen on UPDATE (immutable history of the assessment event).

**Power Apps invocation syntax** (dot-stripped):

```
'Assessment_Warehouse'.dbouspUpsertReadingAssessment({
    StudentNumber:      <BIGINT — required>,
    AssessmentWindowID: <BIGINT — required>,
    ReadingScaleID:     <BIGINT — required>,
    AssessmentDate:     <Date — required (Today() is the standard value)>
})
```

**Parameters:**

| Param | Type | Notes |
|---|---|---|
| StudentNumber | BIGINT | Provincial student #; resolved server-side to StudentKey via SCD effective-date join on AssessmentDate |
| AssessmentWindowID | BIGINT | Must resolve to ActiveFlag=1 AND AssessmentType='Reading' |
| ReadingScaleID | BIGINT | Must resolve to ActiveFlag=1 AND ScaleSystem matching the window's |
| AssessmentDate | DATE | Used for SCD effective-date StudentKey resolution on INSERT. IGNORED on UPDATE — existing row's date is preserved |

**Output:** the proc has no OUTPUT clause (Fabric Warehouse doesn't support OUTPUT). Power Apps cannot read return values. After Save, call `Refresh(vw_TeacherRoster)` to re-pull updated state.

**Server-side enforcement (proc throws on violation):**

| Code | Meaning |
|---|---|
| 51010 | A required parameter is NULL |
| 51011 | StudentNumber doesn't resolve to a DimStudent row at AssessmentDate |
| 51012 | AssessmentWindowID doesn't resolve to an active window |
| 51013 | ReadingScaleID doesn't resolve to an active scale |
| 51014 | Scale ScaleSystem mismatches window ScaleSystem |
| 51015 | Window AssessmentType is not 'Reading' |
| 51016 | Student grade is outside window's grade range |
| 51017 | AssessmentDate is outside [window.StartDate, today] |
| 51030 | Caller is not in DimStaff (IsCurrent=1) |
| 51031 | Teacher attempting to write to a Closed window |
| 51032 | Window is Upcoming (not yet started) |
| 51001 | Layer 3 safety net — impossible-state guard |

Wrap each call in Power Apps `IfError()`; surface `FirstError.Message` via `Notify()`. Messages are intentionally teacher-friendly.

---

## INDIRECTLY-REFERENCED objects (column details for context only)

### Table: `DimAssessmentWindow`

Defines when assessments are collected. Power Apps reads it transitively through `vw_UserAssessmentWindows`, not directly.

| Column | Type | Notes |
|---|---|---|
| AssessmentWindowID | BIGINT (IDENTITY) | PK |
| WindowName | VARCHAR(100) | |
| AssessmentType | VARCHAR(20) | `'Reading'` / `'Writing'` / `'Math'` |
| SchoolYear | VARCHAR(9) | |
| StartDate, EndDate | DATE | |
| MinGrade, MaxGrade | VARCHAR(10) | Join `DimGrade.GradeCode` |
| ProgramFamily | VARCHAR(50) | NULL = all; else matches `DimProgram.ProgramFamily` |
| ScaleSystem | VARCHAR(20) | `'EN_Reading'` / `'FR_Reading'` (Reading windows only); NULL for Writing/Math |
| ActiveFlag | BIT | |
| CreatedDate, CreatedBy, LastUpdated | (audit) | |

### Table: `DimStudent` (SCD Type 2 — full schema for context)

| Column | Type | Notes |
|---|---|---|
| StudentKey | BIGINT (IDENTITY) | Surrogate key |
| StudentNumber | BIGINT | Business key (provincial 10-digit number) |
| FirstName, MiddleName, LastName | VARCHAR(100) | |
| DateOfBirth | DATE | |
| Grade | VARCHAR(10) | `'PP'`, `'P'`, `'1'`–`'12'`, `'RG'` |
| SchoolID | VARCHAR(10) | 4-digit provincial school number |
| ProgramCode | VARCHAR(10) | e.g. `'E015'` |
| EnrollStatus | INT | 0=Active, 2=Inactive, 3=Graduated, -1=Pre-Enrolled |
| Homeroom | VARCHAR(50) | |
| Gender | VARCHAR(10) | `'M'` / `'F'` / `'X'` |
| SelfIDAfrican, SelfIDIndigenous, IPP, Adap | BIT | Demographic flags |
| EffectiveStartDate, EffectiveEndDate, IsCurrent | (SCD versioning) | |
| SourceSystemID | VARCHAR(50) | PS DCID for reference |
| LastUpdated | DATETIME2(0) | |

### Table: `DimSection` (SCD Type 2)

| Column | Type | Notes |
|---|---|---|
| SectionKey | BIGINT (IDENTITY) | Surrogate key |
| SectionID | VARCHAR(50) | Business key |
| SchoolID | VARCHAR(10) | |
| TermID | INT | Joins `DimTerm` |
| CourseCode | VARCHAR(50) | |
| SectionNumber | VARCHAR(20) | e.g. `'01'`, `'02'` |
| CourseName | VARCHAR(200) | |
| EnrollmentCount, MaxEnrollment | INT | |
| TeacherStaffKey | BIGINT | References `DimStaff.StaffKey` (primary teacher of record) |
| EffectiveStartDate, EffectiveEndDate, IsCurrent | (SCD versioning) | |

### Table: `DimSchool` (SCD Type 1)

| Column | Type | Notes |
|---|---|---|
| SchoolID | VARCHAR(10) | 4-digit provincial school number |
| SchoolName | VARCHAR(200) | |
| Abbreviation | VARCHAR(10) | e.g. `'BMHS'` |
| Community | VARCHAR(100) | |
| ActiveFlag | BIT | |

### Table: `DimProgram` (static reference)

| Column | Type | Notes |
|---|---|---|
| ProgramCode | VARCHAR(10) | e.g. `'E015'` |
| ProgramName | VARCHAR(200) | |
| GradeBand | VARCHAR(50) | `'Pre-Primary'` / `'Elementary'` / `'Junior High'` / `'Senior High'` |
| ProgramFamily | VARCHAR(50) | `'English'` / `'French Immersion'` / `'French Second Language'` |
| IsImmersion | BIT | |
| SpecialtyType | VARCHAR(50) | `'O2'` / `'IB'` / NULL |
| ActiveFlag | BIT | |

### Table: `DimGrade` (static reference)

| Column | Type | Notes |
|---|---|---|
| GradeCode | VARCHAR(10) | `'PP'`, `'P'`, `'1'`–`'12'`, `'RG'` |
| GradeOrder | INT | -1, 0, 1…12, 13 (for arithmetic BETWEEN comparisons) |
| GradeName | VARCHAR(50) | e.g. `'Grade 5'`, `'Returning Graduate'` |
| GradeBand | VARCHAR(20) | `'Elementary'` / `'Junior High'` / `'Senior High'` |
| ActiveFlag | BIT | |

### Table: `DimReadingBenchmark` (static reference; used by the upsert proc)

| Column | Type | Notes |
|---|---|---|
| ReadingBenchmarkID | BIGINT (IDENTITY) | PK |
| ScaleSystem | VARCHAR(20) | Matches `DimReadingScale.ScaleSystem` |
| ProgramFamily | VARCHAR(50) | NULL = all; else specific family |
| GradeCode | VARCHAR(10) | Matches `DimGrade.GradeCode` |
| AssessmentMonth | INT | 1-12 calendar month (window's "dominant month") |
| ExpectedMinLevel | VARCHAR(10) | Matches `DimReadingScale.LevelCode` within `ScaleSystem` |
| ExpectedMaxLevel | VARCHAR(10) | Same |

### Fact table: `FactAssessmentReading` (the proc writes here)

| Column | Type | Notes |
|---|---|---|
| ReadingAssessmentID | BIGINT (IDENTITY) | PK |
| StudentKey | BIGINT | Refs `DimStudent.StudentKey` (frozen at insert) |
| AssessmentWindowID | BIGINT | Refs `DimAssessmentWindow` |
| ReadingScaleID | BIGINT | Refs `DimReadingScale` (updateable on correction) |
| ReadingDelta | INT | Computed by proc; can be NULL if benchmark missing |
| AssessmentDate | DATE | Frozen at insert |
| EnteredByStaffKey | BIGINT | Refs `DimStaff.StaffKey` (most recent submitter) |
| SubmissionTimestamp | DATETIME2(0) | UTC |
| LastUpdated | DATETIME2(0) | UTC |

### Fact table: `FactAssessmentWriting` (Phase 5+; not used in MVP)

Schema present for future use. Same shape as Reading but with four 1-4 rubric scores (Ideas / Organization / Language / Conventions) instead of a single scale.

### Audit table: `FactSubmissionAudit` (the upsert proc also appends here)

Append-only audit log of every write. Reading-assessment writes show up as `RecordType='ReadingAssessment'`, `Source='PowerApps'`, with the caller's email in `SubmittedBy`.

---

## Relationships (for the Plan tool's model diagram)

```
DimStudent (SCD 2) <─── FactEnrollment ───> DimSection (SCD 2)
                                                  │
                              FactSectionTeachers ┘
                                  │
                                  └──> DimStaff (SCD 2) [via TeacherEmail]

DimStudent ───> DimSchool, DimProgram, DimGrade (via FK-style columns)
DimSection ───> DimSchool, DimTerm

DimStaff ───> FactStaffAssignment ───> DimSchool
DimStaff ───> StaffSchoolAccess ───> DimSchool       (materialized RLS oracle)

FactAssessmentReading ───> DimStudent (frozen StudentKey)
                       ───> DimAssessmentWindow
                       ───> DimReadingScale
                       ───> DimStaff (EnteredByStaffKey)

DimAssessmentWindow ───> DimGrade (MinGrade, MaxGrade)
                    ───> DimProgram (ProgramFamily, nullable)
                    ───> DimReadingScale (ScaleSystem, nullable)

DimReadingBenchmark ───> DimReadingScale (ScaleSystem)
                    ───> DimGrade (GradeCode)
                    ───> DimProgram (ProgramFamily, nullable)
```

The three secured views (`vw_UserAssessmentWindows`, `vw_TeacherGroups`,
`vw_TeacherRoster`) traverse most of these relationships internally, so
Power Apps doesn't need to join across them itself — it just reads the
flattened view rows.

---

## What the Plan tool should NOT propose

- **Dataverse tables.** Every entity above already exists in
  `Assessment_Warehouse`. Creating Dataverse equivalents would
  double-source the data and break the existing security model.
- **Direct INSERT/UPDATE/Patch against fact tables.** All writes go
  through `usp_UpsertReadingAssessment`. Fabric Warehouse rejects
  `Patch()` and `SubmitForm()` against its tables anyway (the
  connector can't introspect schema enough to make those work).
- **Forms generated from a table.** Power Apps' standard form
  generation will pick `FactAssessmentReading` and produce a
  SubmitForm-based screen — that's the wrong pattern here. The
  entry UI is a custom gallery + ComboBox; Save invokes the proc.
- **A separate "Students" table or "Sections" table for the app.**
  All student / section data is already accessible through the
  three secured views.
- **Modifying any column on the existing tables/views.** The
  schema is settled; the Plan tool's job is to design the app
  around it.
