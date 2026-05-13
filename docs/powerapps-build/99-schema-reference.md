# Schema Reference Cards (per-screen)

Per-screen list of Power Apps data sources, columns, and stored-proc
invocation signatures. The agent (and Copilot) should treat these as the
authoritative shape contract — anything not listed is out of scope for
the screen in question.

For full warehouse schema details (SCD policies, ingest translations,
audit conventions, etc.) the source of truth is the SQL files under
`sql/` and the `regional-assessment-platform` skill. This file is a
**Power-Apps-consumer-side** view: only the columns the entry app actually
reads or writes.

---

## Cross-screen — globals + identity

| Variable | Set on | Used by | Type |
|---|---|---|---|
| `gblIsAdminOrAnalyst` | App.OnStart | scrLanding, scrWindowSelect, scrRosterGrid | Boolean |
| `gblSelectedWindow` | scrWindowSelect tap | scrGroupSelect, scrRosterGrid | Full row from `vw_UserAssessmentWindows` |
| `gblSelectedGroup` | scrGroupSelect tap | scrRosterGrid | Full row from `vw_TeacherGroups` |
| `gblCanEdit` | scrRosterGrid OnVisible | scrRosterGrid controls | Boolean |
| `colDirty` | scrRosterGrid `cmbNewLevel` OnChange | scrRosterGrid Save | Collection of `{ StudentNumber: Number, ReadingScaleID: Number, LevelCode: Text }` |
| `gblSaveErrors` | scrRosterGrid Save | scrRosterGrid Save toast | Number |
| `ctxShowUnsavedConfirm` | scrRosterGrid back-arrow | unsaved-changes modal | Boolean |

Identity functions:
- `User().Email` → calling user's M365/Entra UPN (e.g. `jeffrey.raine@tcrce.ca`).
- `User().FullName` → display name.
- Never hardcode email addresses in formulas. Never use `USERPRINCIPALNAME()` (that's DAX, not Power Fx).

---

## scrLanding

**Data sources used:**

`DimStaff` — for the App.OnStart admin-detection LookUp.

| Column | Type | Notes |
|---|---|---|
| `Email` | Text | Business key. Lowercased at ingest; compare with `Lower(Email) = Lower(User().Email)`. |
| `IsCurrent` | Boolean | Filter to `IsCurrent = true` for the current Type 2 row. |
| `AccessLevel` | Text | NULL for teachers; non-NULL for school admins / specialists / regional analysts. |

**Stored procs used:** none.

---

## scrWindowSelect

**Data sources used:**

`vw_UserAssessmentWindows` — secured view, returns one row per (caller, applicable window) tuple. RLS-scoped to the caller's role.

| Column | Type | Notes |
|---|---|---|
| `AssessmentWindowID` | Number | Primary key of the window. |
| `WindowName` | Text | Display name. |
| `AssessmentType` | Text | `'Reading'` / `'Writing'` / `'Math'`. MVP only seeds Reading windows. |
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

---

## scrGroupSelect

**Data sources used:**

`vw_TeacherGroups` — secured view, returns one row per (caller, applicable window, group) tuple.

| Column | Type | Notes |
|---|---|---|
| `AssessmentWindowID` | Number | Filter target for the gallery. |
| `GroupKey` | Text | `'HR:' + Homeroom` for PP-9 students; `'SEC:' + SectionID` for 10-12 / RG. |
| `GroupType` | Text | `'Homeroom'` or `'Section'`. |
| `GroupLabel` | Text | Display string (e.g. "Homeroom 5A" or "FRA12.01 — French 12"). |
| `Grade` | Text | The shared grade of students in this group (`DimGrade.GradeCode`). |
| `ApplicableStudentCount` | Number | Students in this group applicable to this window. |
| `EnteredStudentCount` | Number | Of those, how many have entered an assessment. |

**Stored procs used:** none.

---

## scrRosterGrid

**Data sources used:**

`vw_TeacherRoster` — secured view, returns one row per (caller, applicable window, group, student) tuple with existing reading-assessment value if any.

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
| `ProgramFamily` | Text | Resolved from DimProgram (e.g. `'French Immersion'`). |
| `ExistingReadingAssessmentID` | Number | NULL if no assessment entered. |
| `ExistingReadingScaleID` | Number | NULL if no assessment entered. Used for `cmbNewLevel.DefaultSelectedItems`. |
| `ExistingScaleValue` | Text | The level code (e.g. `'C'`, `'Z'`, `'30+'`). Display in `lblExistingLevel`. |
| `ExistingAssessmentDate` | Date | NULL if no assessment entered. |

`DimReadingScale` — dropdown source for the per-row ComboBox.

| Column | Type | Notes |
|---|---|---|
| `ReadingScaleID` | Number | PK; passed to the upsert proc. |
| `LevelCode` | Text | Display value (e.g. `'A'`, `'DT'`, `'30+'`). |
| `LevelOrder` | Number | Sort order. EN: DT=0, A=1, ..., Z=26. FR: TD=0, 1-30=1-30, 30+=31. |
| `ScaleSystem` | Text | `'EN_Reading'` or `'FR_Reading'`. Filter target (matches `gblSelectedWindow.ScaleSystem`). |
| `ActiveFlag` | Boolean | Filter to `true`. |

**Stored procs used:**

### `usp_UpsertReadingAssessment`

Inserts a new reading assessment if (StudentKey, AssessmentWindowID) has no
row; otherwise updates the existing row's score + audit columns. StudentKey
and AssessmentDate are frozen on UPDATE.

**Power Apps invocation syntax** (dot-stripped name):

```
'Assessment_Warehouse'.dbouspUpsertReadingAssessment({
    StudentNumber:      <BIGINT — required>,
    AssessmentWindowID: <BIGINT — required>,
    ReadingScaleID:     <BIGINT — required>,
    AssessmentDate:     <Date  — required (Today() is the standard value)>
})
```

**Parameters:**

| Param | Type | Notes |
|---|---|---|
| `StudentNumber` | Number | Provincial student #; resolved server-side to StudentKey via effective-date join on AssessmentDate. |
| `AssessmentWindowID` | Number | Must resolve to ActiveFlag=1, AssessmentType='Reading'. |
| `ReadingScaleID` | Number | Must resolve to ActiveFlag=1, ScaleSystem matching the window's. |
| `AssessmentDate` | Date | Used for SCD effective-date StudentKey resolution on INSERT. IGNORED on UPDATE. |

**Server-side enforcement (proc throws on violation):**

| Code | Meaning |
|---|---|
| 51010 | A required parameter is NULL. |
| 51011 | StudentNumber doesn't resolve to a DimStudent row at AssessmentDate. |
| 51012 | AssessmentWindowID doesn't resolve to an active window. |
| 51013 | ReadingScaleID doesn't resolve to an active scale. |
| 51014 | Scale ScaleSystem mismatches window ScaleSystem. |
| 51015 | Window AssessmentType is not 'Reading'. |
| 51016 | Student grade is outside window's grade range. |
| 51017 | AssessmentDate is outside [window.StartDate, today]. |
| 51030 | Caller is not in DimStaff (IsCurrent=1). |
| 51031 | Teacher (AccessLevel IS NULL) attempting to write to a Closed window. |
| 51032 | Window is Upcoming (not yet started). |
| 51001 | Layer 3 safety net — impossible-state guard. |

**Error handling in Power Apps:** wrap each proc call in `IfError()`. The
THROW message is surfaced via `FirstError.Message` — pass it through to a
`Notify(...)` toast. The proc messages are intentionally teacher-friendly.

**Output:** the proc has no OUTPUT clause (Fabric Warehouse doesn't support
OUTPUT). Power Apps cannot read return values directly. After Save, call
`Refresh(vw_TeacherRoster)` to re-pull the updated state.

---

## Adding a data source to Power Apps

In Studio: Data panel → **+ Add data** → SQL Server connector → the existing
Microsoft Entra ID Integrated connection → expand `Assessment_Warehouse`
→ check the views and procs needed by the screen you're building → Connect.

The connector exposes:
- Views and tables under `[dbo].[ObjectName]` (or `'Assessment_Warehouse'.dbo.ObjectName` depending on context).
- Stored procedures with names stripped of dots (e.g. `dbo.usp_X` → `dbouspX`).

If a data source is missing when Copilot scaffolds a screen, Copilot will
invent the closest name it can guess — always wrong. Add the data source
**before** running Copilot prompts.
