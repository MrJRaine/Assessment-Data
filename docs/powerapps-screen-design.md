# Power Apps Screen Design — Reading Assessment Entry

**Created**: 2026-05-11
**Status**: Design spec (Step 17). Formulas land in Step 18.
**Region**: Canada East (PIIDPA compliant)
**Audience**: Teachers, school admins, and regional analysts entering / reviewing reading assessments via Teams-embedded canvas app

---

## Overview

Four screens. Confirmation collapses to a toast on save (no dedicated confirmation screen — modern UX, faster cycle).

```
                                  ┌─→ scrStudentData     [Phase 5+ placeholder]
                                  │
scrLanding ───→ choose path ──────┤
                                  │
                                  └─→ scrWindowSelect ──→ scrGroupSelect ──→ scrRosterGrid
                                                                              (Tap a window,
                                                                               then a group, then
                                                                               enter the roster)
```

**Design principles:**
- **Window-first navigation** — multiple assessment windows can be open concurrently (e.g. P-6 Reading + 7-12 Writing, or English-Reading-for-all + French-Reading-for-FI). Force the user to pick which one they're entering before showing groups.
- **Group-then-roster within a window** — teachers think in classes/homerooms, not individual students.
- **Spreadsheet-style entry** — Tab/Enter moves down through input fields. Approximation, not Excel-perfect (see Technical Realities).
- **Save explicitly, never auto** — eliminates "did it save?" anxiety; user controls timing.
- **Edit during open window** — teachers can re-save during the window to fix typos. School admins / regional analysts can edit anytime, including past windows. Enforced server-side in the proc.
- **Atlantic time throughout** — per project convention.

**Role-based UI gating** (computed once on App.OnStart from current user's `DimStaff.AccessLevel`):

| User type | scrLanding | scrWindowSelect | scrRosterGrid edit |
|---|---|---|---|
| Teacher | both paths | own applicable windows only; no SY dropdown | edit if window open AND owner-teacher; read-only if closed |
| School Admin (`AccessLevel = 'Administrator'` / `'SpecialistTeacher'`) | both paths | all applicable windows in the schools they cover; SY dropdown visible | edit any window (open or closed) for students in their schools |
| Regional Analyst (`AccessLevel = 'RegionalAnalyst'`) | both paths | all applicable windows region-wide; SY dropdown visible | edit any window region-wide |

---

## Schema Impact

### `DimAssessmentWindow` — cleanup

| Column | Action | Why |
|---|---|---|
| `ProgramCode` | **Rename to `ProgramFamily`** | Semantic clarity. NULL = applies to all programs; non-NULL filters by `DimProgram.ProgramFamily` (e.g. `'French Immersion'`) |
| `AppliesTo` | Drop | Redundant with `MinGrade` / `MaxGrade` |
| `IsCurrentWindow` | Drop | Compute from `today BETWEEN StartDate AND EndDate AND ActiveFlag = 1` |
| `AssessmentType`, `SchoolYear`, `StartDate`, `EndDate`, `MinGrade`, `MaxGrade`, `ActiveFlag` | Keep | All still meaningful |

A migration script is needed: `sql/scripts/migrate_DimAssessmentWindow_v2.sql` (drops two columns, renames one, no data backfill since the table likely has at most one seeded row at this point).

### New: `DimGrade` lookup table

Solves the lexicographic-ordering bug on `DimStudent.Grade` ('P' > '12', '10' < '2' as strings). Required for grade-range BETWEEN comparisons in window applicability filters.

```sql
CREATE TABLE DimGrade (
    GradeCode    VARCHAR(10)   NOT NULL,    -- Business key: 'PP', 'P', '1', ..., '12', 'RG'
    GradeOrder   INT           NOT NULL,    -- Sort order: -1, 0, 1, ..., 12, 13
    GradeName    VARCHAR(50)   NOT NULL,    -- Human-readable: 'Pre-Primary', 'Primary', 'Grade 1', etc.
    GradeBand    VARCHAR(20)   NOT NULL,    -- 'Elementary' / 'Junior High' / 'Senior High'
    ActiveFlag   BIT           NOT NULL,
    LastUpdated  DATETIME2(0)  NOT NULL
);

INSERT INTO DimGrade (GradeCode, GradeOrder, GradeName, GradeBand, ActiveFlag, LastUpdated) VALUES
    ('PP',  -1, 'Pre-Primary',         'Elementary',   1, GETDATE()),
    ('P',    0, 'Primary',              'Elementary',   1, GETDATE()),
    ('1',    1, 'Grade 1',              'Elementary',   1, GETDATE()),
    ('2',    2, 'Grade 2',              'Elementary',   1, GETDATE()),
    ('3',    3, 'Grade 3',              'Elementary',   1, GETDATE()),
    ('4',    4, 'Grade 4',              'Elementary',   1, GETDATE()),
    ('5',    5, 'Grade 5',              'Elementary',   1, GETDATE()),
    ('6',    6, 'Grade 6',              'Elementary',   1, GETDATE()),
    ('7',    7, 'Grade 7',              'Junior High',  1, GETDATE()),
    ('8',    8, 'Grade 8',              'Junior High',  1, GETDATE()),
    ('9',    9, 'Grade 9',              'Junior High',  1, GETDATE()),
    ('10',  10, 'Grade 10',             'Senior High',  1, GETDATE()),
    ('11',  11, 'Grade 11',             'Senior High',  1, GETDATE()),
    ('12',  12, 'Grade 12',             'Senior High',  1, GETDATE()),
    ('RG',  13, 'Returning Graduate',   'Senior High',  1, GETDATE());
```

PS emits `grade_level = 13` for Returning Graduates → translate to `'RG'` at ingest (alongside the existing `0`→`'P'` and `-1`→`'PP'` translations) in `Wrk_Student` build inside `usp_MergeStudent`.

### Window-applicability join pattern

Every applicability check joins `DimStudent → DimProgram → DimGrade ↔ DimAssessmentWindow`:

```sql
INNER JOIN DimProgram dp ON dp.ProgramCode = s.ProgramCode
INNER JOIN DimGrade   sg ON sg.GradeCode   = s.Grade
INNER JOIN DimGrade   wmin ON wmin.GradeCode = w.MinGrade
INNER JOIN DimGrade   wmax ON wmax.GradeCode = w.MaxGrade
WHERE sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
  AND (w.ProgramFamily IS NULL OR dp.ProgramFamily = w.ProgramFamily)
```

---

## Screen 1: scrLanding

### Purpose
First screen on app launch. Two-card menu: where do you want to go?

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [Header bar]                                               │
│  Hello, Jeff                                                │
│  jeffrey.raine@tcrce.ca                                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────────────────────┐  ┌──────────────────────────┐│
│   │                          │  │                          ││
│   │      📊  Student Data    │  │      ✏️   Data Entry      ││
│   │                          │  │                          ││
│   │   Look up student        │  │   Enter assessment       ││
│   │   results and progress.  │  │   results for your       ││
│   │                          │  │   classes.               ││
│   │                          │  │                          ││
│   └──────────────────────────┘  └──────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Controls

| Control | Type | Purpose | Key properties |
|---|---|---|---|
| `lblGreeting` | Label | "Hello, {first name}" | `Text: "Hello, " & First(Split(User().FullName, " ")).Result` |
| `lblUserUPN` | Label (small, muted) | UPN diagnostic display | `Text: User().Email` |
| `btnStudentData` | Button (large card) | Navigate to data viewer | `OnSelect: Navigate(scrStudentData)` |
| `btnDataEntry` | Button (large card) | Navigate to entry flow | `OnSelect: Navigate(scrWindowSelect)` |

### Phase scope
`scrStudentData` is a placeholder for now — wire the button but the destination screen is just a "Coming soon" stub. Full buildout is Phase 5.

---

## Screen 2: scrWindowSelect

### Purpose
User picks the assessment window they're entering / reviewing. Filtered to windows where they have applicable students. Admins additionally get a school year dropdown for historical access.

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│ [⬅]   Choose an assessment window                           │
├─────────────────────────────────────────────────────────────┤
│   School Year: [ 2025-2026 ▼ ]   ← admin/analyst only       │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ 🔓  English Reading EOY 2025-2026                   │   │
│   │     Reading · Grades P-12 · Closes June 30 2026     │   │
│   │     ✓ 18 of 51 entered                              │   │
│   └─────────────────────────────────────────────────────┘   │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ 🔓  French Reading EOY 2025-2026 — French Immersion │   │
│   │     Reading · Grades P-12 · Closes June 30 2026     │   │
│   │     ◐ 12 of 23 entered                              │   │
│   └─────────────────────────────────────────────────────┘   │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ 🔒  English Writing Q3 2025-2026                    │   │
│   │     Writing · Grades 7-12 · Closed March 31 2026    │   │
│   │     ✓ 28 of 28 entered                              │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Status icons: 🔓 open · 🔒 closed · ⏰ closes today

### Controls

| Control | Type | Purpose | Key properties |
|---|---|---|---|
| `icoBack` | Icon (arrow-left) | Returns to scrLanding | `OnSelect: Navigate(scrLanding)` |
| `lblTitle` | Label | "Choose an assessment window" | static |
| `cmbSchoolYear` | Dropdown | School year filter | `Visible: gblIsAdminOrAnalyst`, `Items: distinct SchoolYear from vw_UserAssessmentWindows`, `Default: <current school year>` |
| `galWindows` | Gallery (vertical) | One row per applicable window | `Items: Filter(vw_UserAssessmentWindows, SchoolYear = cmbSchoolYear.Selected.Value)` |
| Within each gallery row: | | | |
| `lblWindowName` | Label | Title with status icon | `Text: ThisItem.StatusIcon & " " & ThisItem.WindowName` |
| `lblWindowMeta` | Label (smaller) | "Reading · Grades P-12 · Closes June 30 2026" | composed string |
| `lblProgress` | Label | "✓ 18 of 51 entered" | composed string |

### Data source

**New view to build** (Step 18 prereq): `vw_UserAssessmentWindows` — implements role-branched **historical roster reconciliation** per `project_historical_roster_reconciliation.md` memory (decided 2026-05-12). For closed windows, teachers see the roster they HAD at the time of the window (not current); admins see students who were in their schools at the window's effective date.

**Window effective date**: `CASE WHEN today_atlantic > window.EndDate THEN window.EndDate ELSE today_atlantic END` — resolves point-in-time roster for closed windows; resolves current state for open/future windows.

```sql
CREATE VIEW vw_UserAssessmentWindows AS
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
-- Resolve caller's role + identity once
Caller AS (
    SELECT TOP 1
        d.StaffKey,
        LOWER(d.Email) AS Email,
        d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER)
      AND d.IsCurrent = 1
),
-- For each active window, compute its effective date for historical-roster resolution
WindowEffectiveDates AS (
    SELECT
        w.AssessmentWindowID,
        w.WindowName,
        w.AssessmentType,
        w.SchoolYear,
        w.StartDate,
        w.EndDate,
        w.MinGrade,
        w.MaxGrade,
        w.ProgramFamily,
        CASE WHEN at.Today > w.EndDate THEN w.EndDate
             ELSE at.Today END AS EffectiveDate,
        CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
             WHEN at.Today > w.EndDate   THEN 'Closed'
             WHEN at.Today = w.EndDate   THEN 'ClosesToday'
             ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w
    CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- ROLE BRANCH 1: Teacher — students in sections they taught during the window
-- Each join gated on the window effective date being within the relevant
-- Type 2 row's effective period.
TeacherStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN FactSectionTeachers fst
            ON LOWER(fst.TeacherEmail) = c.Email
           AND wed.EffectiveDate BETWEEN fst.EffectiveStartDate AND COALESCE(fst.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimSection sec
            ON sec.SectionID = fst.SectionID
           AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
    INNER JOIN FactEnrollment e
            ON e.SectionKey  = sec.SectionKey
           AND e.StartDate  <= wed.EndDate
           AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
    INNER JOIN DimStudent s
            ON s.StudentKey = e.StudentKey
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IS NULL                                         -- teachers have no school-tier AccessLevel
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 2: School Admin / SpecialistTeacher — students whose DimStudent
-- (effective at window date) had SchoolID in their CURRENT StaffSchoolAccess list.
AdminStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN StaffSchoolAccess ssa
            ON ssa.StaffKey = c.StaffKey
    INNER JOIN DimStudent s
            ON s.SchoolID = ssa.SchoolID
           AND wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel IN ('Administrator', 'SpecialistTeacher')
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
-- ROLE BRANCH 3: Regional Analyst — all students whose DimStudent
-- (effective at window date) matches the window's scope.
AnalystStudents AS (
    SELECT
        wed.AssessmentWindowID,
        s.StudentKey
    FROM Caller c
    CROSS JOIN WindowEffectiveDates wed
    INNER JOIN DimStudent s
            ON wed.EffectiveDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
    INNER JOIN DimGrade   sg   ON sg.GradeCode   = s.Grade
    INNER JOIN DimGrade   wmin ON wmin.GradeCode = wed.MinGrade
    INNER JOIN DimGrade   wmax ON wmax.GradeCode = wed.MaxGrade
    INNER JOIN DimProgram dp   ON dp.ProgramCode = s.ProgramCode
    WHERE c.AccessLevel = 'RegionalAnalyst'
      AND sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
      AND (wed.ProgramFamily IS NULL OR dp.ProgramFamily = wed.ProgramFamily)
),
ApplicableStudents AS (
    SELECT * FROM TeacherStudents
    UNION ALL SELECT * FROM AdminStudents
    UNION ALL SELECT * FROM AnalystStudents
)
SELECT
    wed.AssessmentWindowID,
    wed.WindowName,
    wed.AssessmentType,
    wed.SchoolYear,
    wed.StartDate,
    wed.EndDate,
    wed.MinGrade,
    wed.MaxGrade,
    wed.ProgramFamily,
    wed.WindowStatus,
    COUNT(DISTINCT a.StudentKey) AS ApplicableStudentCount,
    COUNT(DISTINCT CASE WHEN far.ReadingAssessmentID IS NOT NULL
                        THEN a.StudentKey END) AS EnteredStudentCount
FROM WindowEffectiveDates wed
INNER JOIN ApplicableStudents a
        ON a.AssessmentWindowID = wed.AssessmentWindowID
LEFT JOIN FactAssessmentReading far
       ON far.AssessmentWindowID = wed.AssessmentWindowID
      AND far.StudentKey         = a.StudentKey
GROUP BY
    wed.AssessmentWindowID, wed.WindowName, wed.AssessmentType, wed.SchoolYear,
    wed.StartDate, wed.EndDate, wed.MinGrade, wed.MaxGrade, wed.ProgramFamily, wed.WindowStatus;
```

**Notes:**
- The three role-branch CTEs are written as separate UNION ALL inputs but in practice only one returns rows per caller — the `c.AccessLevel` filter in each branch ensures mutual exclusivity. This pattern keeps the role logic visible while letting the Fabric optimizer prune empty branches fast.
- `StaffSchoolAccess` is treated as current-only — admin role changes are NOT historically reconciled. Only the student side is. Documented in the historical-roster memory as an MVP scope decision.
- The empty-result case (user has no role / no applicable students) returns zero rows — Power Apps shows the empty-state message.

### Navigation
Tap a row → set state and navigate:
```
Set(gblSelectedWindow, ThisItem);
Navigate(scrGroupSelect)
```

### Empty state
If `vw_UserAssessmentWindows` returns zero rows for the selected school year:
> No assessment windows currently apply to your students for school year {SY}. New windows appear here when admins open them.

---

## Screen 3: scrGroupSelect

### Purpose
Filtered to groups (homerooms or sections) that have students applicable to the selected window. Same group-list pattern as before, but parameterized.

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│ [⬅]   French Reading EOY 2025-26 — French Immersion         │
├─────────────────────────────────────────────────────────────┤
│  Choose a class                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Homeroom 5A                                          │    │
│  │ Grade 5 · 12 applicable students                     │    │
│  │ ✓ 8 of 12 entered                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ FRA12.01 — French 12                                 │    │
│  │ Grade 12 · 18 applicable students                    │    │
│  │ ◐ 4 of 18 entered                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Controls

Identical structure to original spec, but `vw_TeacherGroups` is parameterized by the chosen window (i.e., students must be applicable to `gblSelectedWindow`). Only changes:

- Header shows `gblSelectedWindow.WindowName` instead of "the current window"
- Gallery `Items` filtered both by group ownership AND window applicability
- Each row's count is "applicable students for THIS window," not "all my students"
- Progress count is for THIS window only

### Data source

`vw_TeacherGroups` (revised — see prereq list).

### Navigation
Tap → set selected group, navigate to roster:
```
Set(gblSelectedGroup, ThisItem);
Navigate(scrRosterGrid)
```

---

## Screen 4: scrRosterGrid

### Purpose
Editable grid of all *applicable* students in the selected group for the selected window. Save commits all dirty rows in one batch. Read-only mode for users who can't edit.

### Layout (edit mode)

```
┌─────────────────────────────────────────────────────────────┐
│ [⬅]   Homeroom 5A — French Reading EOY 2025-26    [💾 Save] │
├─────────────────────────────────────────────────────────────┤
│  Student                  Existing Level   New Level        │
│  ─────────────────────────────────────────────────────────  │
│  Alpha, Aaron             K                 [Level B ▼]      │
│  Beta, Beatrice           —                 [Level C ▼]      │
│  Gamma, Gillian           A                 [Level A ▼]  ✓   │
│  Delta, Dmitri            —                 [           ▼]   │
│  Epsilon, Eve             B                 [Level B ▼]  ✓   │
│  ...                                                         │
│                                                              │
│                       [ 💾 Save 4 changes ]                  │
└─────────────────────────────────────────────────────────────┘
```

### Layout (read-only mode — teacher viewing closed window)

```
┌─────────────────────────────────────────────────────────────┐
│ [⬅]   Homeroom 5A — Reading EOY 2024-25     🔒 Read-only    │
├─────────────────────────────────────────────────────────────┤
│  Student                                  Level             │
│  ─────────────────────────────────────────────────────────  │
│  Alpha, Aaron                             K                 │
│  Beta, Beatrice                           —                 │
│  Gamma, Gillian                           A                 │
│  ...                                                         │
│                                                              │
│  ℹ️ This window closed on June 30 2025. Contact a school    │
│  admin if changes are needed.                               │
└─────────────────────────────────────────────────────────────┘
```

### Controls (edit mode)

| Control | Type | Purpose | Key properties |
|---|---|---|---|
| `icoBack` | Icon | Back to scrGroupSelect (with unsaved warning) | `OnSelect: <see navigation>` |
| `lblGroupTitle` | Label | "Homeroom 5A — French Reading EOY 2025-26" | composed |
| `lblReadOnlyBadge` | Label | "🔒 Read-only" — only visible if `gblCanEdit = false` | `Visible: !gblCanEdit` |
| `btnSaveTop` | Button (top-right) | Triggers batch save | `Visible: gblCanEdit`, `OnSelect: SaveAllPending()` |
| `galRoster` | Gallery (vertical) | One row per applicable student | `Items: vw_TeacherRoster filtered by group + window` |
| Within each gallery row (edit mode): | | | |
| `lblStudentName` | Label | "Lastname, Firstname" | `Text: ThisItem.LastName & ", " & ThisItem.FirstName` |
| `lblExistingLevel` | Label | Previous value or "—" | `Text: Coalesce(ThisItem.ExistingScaleValue, "—")` |
| `cmbNewLevel` | ComboBox | Reading scale dropdown filtered to student's grade+program | `Items: Filter(DimReadingScale, ProgramCode = ThisItem.ProgramCode && Grade = ThisItem.Grade)`; `DisplayMode: gblCanEdit` |
| `icoDirty` | Icon (✓) | Dirty indicator | `Visible: IsDirty(ThisItem.StudentNumber)` |
| `btnSaveBottom` | Button (centered, bottom) | Mirrors top-right save | `Visible: gblCanEdit`, `Text: "💾 Save " & CountRows(colDirty) & " changes"`, `OnSelect: SaveAllPending()` |
| `lblReadOnlyExplain` | Label (bottom) | "This window closed on..." message | `Visible: !gblCanEdit`, composed text |

### Edit-permission state (`gblCanEdit`)

Set on screen entry:
```
Set(gblCanEdit,
    // Admins / analysts always can
    gblIsAdminOrAnalyst
    // Teachers: only if window is currently open
    || (gblSelectedWindow.WindowStatus IN ["Open", "ClosesToday"])
)
```

The proc independently re-checks this server-side (defense in depth — UI gating is a UX hint, not the security boundary).

### Data source

`vw_TeacherRoster` (revised — parameterized by window) — only includes students applicable to the current `gblSelectedWindow` and shows the existing assessment value (if any) for THAT window.

### Save behavior (dirty-tracking)

Same as before — `colDirty` collection, `cmbNewLevel.OnChange` records changes, Save button does:

```
ForAll(
    colDirty,
    'Assessment_Warehouse'.dbouspUpsertReadingAssessment({
        StudentNumber:      StudentNumber,
        AssessmentWindowID: gblSelectedWindow.AssessmentWindowID,
        ReadingScaleID:     ReadingScaleID,
        AssessmentDate:     AssessmentDate
    })
);
Clear(colDirty);
Notify("Saved " & CountRows(colDirty) & " assessments", NotificationType.Success);
Refresh(vw_TeacherRoster);
```

### Back arrow with unsaved-changes warning

Same as original spec — modal confirms discard if `colDirty` is non-empty.

### Keyboard navigation
Same approximation strategy as before — see Technical Realities.

---

## State Management

App-level variables, set on `App.OnStart` or screen-entry:

| Variable | Set on | Used by | Notes |
|---|---|---|---|
| `gblIsAdminOrAnalyst` | App.OnStart | scrLanding, scrWindowSelect, scrRosterGrid | Lookup current user's `DimStaff.AccessLevel` |
| `gblSelectedWindow` | scrWindowSelect tap | scrGroupSelect, scrRosterGrid | Full row from vw_UserAssessmentWindows |
| `gblSelectedGroup` | scrGroupSelect tap | scrRosterGrid | GroupKey + label info |
| `gblCanEdit` | scrRosterGrid OnVisible | scrRosterGrid controls | Derived from role + window status |
| `colDirty` | cmbNewLevel.OnChange | scrRosterGrid Save | Cleared on save success and confirmed back-nav |

---

## Prerequisite SQL Objects (Step 18 build list)

In suggested build order:

1. **`DimGrade`** — new lookup table + 15-row seed (PP, P, 1-12, RG). Sort-key resolver for grade-range BETWEEN comparisons.
2. **Ingest translation update** — `usp_MergeStudent` (Wrk_Student build): add `13`→`'RG'` translation alongside the existing `0`→`'P'` and `-1`→`'PP'`.
3. **`DimAssessmentWindow` schema migration** — drop `AppliesTo`, drop `IsCurrentWindow`, rename `ProgramCode`→`ProgramFamily`. Migration script + redeploy.
4. **`vw_UserAssessmentWindows`** — new view powering scrWindowSelect (full SQL drafted above). **Role-branched historical roster reconciliation** per `project_historical_roster_reconciliation` memory.
5. **`vw_TeacherGroups`** — revised. **Must use the same historical-reconciliation pattern as `vw_UserAssessmentWindows`** — returns one row per (user, window, group) tuple. Power Apps filters client-side by `gblSelectedWindow.AssessmentWindowID`. Grade-range applicability via DimGrade. Group key: `'HR:' + Homeroom` for PP-9 students (uses student's homeroom at the window's effective date), `'SEC:' + SectionID` for 10-12 students. Progress count is per-(group, window).
6. **`vw_TeacherRoster`** — revised. **Same historical-reconciliation pattern** — returns one row per (user, window, group, student) tuple with existing assessment value if any. Power Apps filters client-side by `WindowID` and `GroupKey`. The "existing assessment" column matches on `AssessmentWindowID` only (one assessment per student per window by design).
7. **`usp_UpsertReadingAssessment`** — new write proc:
   - Resolves `StudentKey` via effective-date join on `(StudentNumber, AssessmentDate)`
   - Existence check on `(StudentKey, AssessmentWindowID)`
   - Edit-permission re-check server-side: caller's role + window status (Open vs Closed)
   - INSERT new or UPDATE existing
   - Computes `ReadingDelta` from scale + DimReadingScale expected for grade/program
   - Audit row to `FactSubmissionAudit` per call
   - **No `OUTPUT` clause** (Fabric limitation)
   - Returns specific error codes Power Apps can surface (e.g. "window closed", "not your student")
8. **Seed `DimAssessmentWindow`** with the MVP pilot windows (likely 2 — English Reading all-grades + French Reading FI).
9. **Verify `DimReadingScale`** is populated for the program codes + grades teachers will be entering (FR Immersion grades P-12, English grades P-12). Probably needs an external task — sourcing the actual scale values from the assessment team.

---

## Power Apps Technical Realities (Pilot test items)

1. **Keyboard navigation is approximation, not Excel-perfect.** `SetFocus()` between dropdowns approximates spreadsheet nav but feels less crisp. Pilot teachers validate. Fallback: per-row save buttons.
2. **Gallery virtualization.** Large rosters (>50) may have off-screen rows whose controls aren't instantiated. Probably not an issue for MVP homeroom sizes (~25), worth testing for senior high sections (~30).
3. **`Refresh()` on views may be slow.** Post-save refresh of `vw_TeacherRoster` may take seconds against Fabric Warehouse. Alternative: optimistic local update without re-query. Decision deferred until pilot timing.
4. **Toast visibility in Teams shell.** `Notify()` toasts may be partly obscured by Teams chrome. Visual-test during pilot UAT.
5. **Concurrent edit races.** Same student × same window edited by two users (e.g. teacher + admin) → last-write-wins, no UI feedback to the loser. Acceptable for MVP; revisit if it surfaces.
6. **Multiple concurrent windows on same student.** Verified: a student in BOTH an English-Reading-all-students window AND a French-Reading-FI window has TWO `FactAssessmentReading` rows for the year (different `AssessmentWindowID`). The fact table's natural uniqueness key is `(StudentKey, AssessmentWindowID)` — this is by design, not a bug.

---

## Out of Scope for Step 17

- Power Apps formula text (Step 18 deliverable)
- `scrStudentData` full design (Phase 5+ — placeholder button only for MVP)
- Power Apps embedding in Teams (Step 20)
- App sharing / role gating in Teams (Step 21)
- Writing assessment entry form (Phase 5 / Step 31)
- School admin monitoring dashboard (Phase 5 / Step 32)
