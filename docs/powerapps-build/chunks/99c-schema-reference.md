<!-- Chunk 3 of 5 — Schema reference (scrGroupSelect + scrRosterGrid data sources) -->

# Schema Reference Cards (part 3/5)

Continued from [99b-schema-reference.md](99b-schema-reference.md).

## scrGroupSelect

`vw_TeacherGroups` — one row per (caller, applicable window, group).

| Column | Type | Notes |
|---|---|---|
| `AssessmentWindowID` | Number | Filter target for the gallery. |
| `GroupKey` | Text | `'HR:' + Homeroom` (PP-9); `'SEC:' + SectionID` (10-12 / RG). |
| `GroupType` | Text | `'Homeroom'` or `'Section'`. |
| `GroupLabel` | Text | Display string (e.g. "Homeroom 5A"). |
| `Grade` | Text | Shared grade of students in this group (`DimGrade.GradeCode`). |
| `ApplicableStudentCount` | Number | Students in this group for this window. |
| `EnteredStudentCount` | Number | Of those, how many entered. |

**Stored procs used:** none.

## scrRosterGrid — Data sources

`vw_TeacherRoster` — one row per (caller, applicable window, group, student) with existing assessment value if any.

| Column | Type | Notes |
|---|---|---|
| `AssessmentWindowID` | Number | Filter target. |
| `GroupKey` | Text | Filter target (matches `gblSelectedGroup.GroupKey`). |
| `StudentKey` | Number | Internal surrogate key. Not used by Power Apps directly. |
| `StudentNumber` | Number | Provincial 10-digit student #. **Required for the upsert proc call.** |
| `FirstName` | Text | |
| `LastName` | Text | |
| `Grade` | Text | Student's grade at the window's effective date. |
| `ProgramCode` | Text | PowerSchool program code (e.g. `'E015'`). |
| `ProgramFamily` | Text | Resolved from DimProgram. |
| `ExistingReadingAssessmentID` | Number | NULL if no assessment. |
| `ExistingReadingScaleID` | Number | NULL if none. Used for `cmbNewLevel.DefaultSelectedItems`. |
| `ExistingScaleValue` | Text | Level code (e.g. `'C'`, `'30+'`). Display in `lblExistingLevel`. |
| `ExistingAssessmentDate` | Date | NULL if none. |

Continues in [99d-schema-reference.md](99d-schema-reference.md).
