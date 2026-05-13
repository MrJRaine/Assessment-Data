<!-- Chunk 2 of 5 — Schema reference (scrWindowSelect) -->

# Schema Reference Cards (part 2/5)

Continued from [99a-schema-reference.md](99a-schema-reference.md).

## scrWindowSelect

**Data sources used:** `vw_UserAssessmentWindows` — secured view, RLS-scoped to caller. One row per (caller, applicable window) tuple.

| Column | Type | Notes |
|---|---|---|
| `AssessmentWindowID` | Number | Primary key of the window. |
| `WindowName` | Text | Display name. |
| `AssessmentType` | Text | `'Reading'` / `'Writing'` / `'Math'`. MVP only seeds Reading. |
| `SchoolYear` | Text | e.g. `'2025-2026'`. Filter source for `cmbSchoolYear`. |
| `StartDate` | Date | |
| `EndDate` | Date | |
| `MinGrade` | Text | `DimGrade.GradeCode`. |
| `MaxGrade` | Text | `DimGrade.GradeCode`. |
| `ProgramFamily` | Text | NULL = all programs; else `'English'` / `'French Immersion'` / etc. |
| `WindowStatus` | Text | One of `'Open'` / `'ClosesToday'` / `'Closed'` / `'Upcoming'`. |
| `ApplicableStudentCount` | Number | Distinct students the caller can see for this window. |
| `EnteredStudentCount` | Number | Distinct students with a Reading assessment for this window. (Writing/Math counts: see TODO in view header.) |

**Stored procs used:** none.

Continues in [99c-schema-reference.md](99c-schema-reference.md).
