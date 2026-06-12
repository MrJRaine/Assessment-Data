---
name: Historical Roster Reconciliation
description: For window-context views (vw_UserAssessmentWindows, vw_TeacherGroups, vw_TeacherRoster), resolve the "applicable students" set via effective-date join against the window's dates — not against current-only RLS views. Decided 2026-05-12.
type: project
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**For closed windows, teachers see the roster they had AT THE TIME — not their current roster.**

**Why:** Resolved the `vw_UserAssessmentWindows` open question from 2026-05-11. Original draft used UNION across the 3 RLS views (`vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData`), which would have meant teachers viewing a closed window saw assessment status for their CURRENT roster — not the students they actually had during that window. For students who moved sections mid-year, the old teacher would lose visibility and the new teacher would see the historical assessment. User chose option 3 (build historical roster reconciliation now) to preserve historical accuracy even though it's more complex.

**How to apply:**

**Resolution strategy** — for any (user, window) pair, the relevant "applicable students" are determined by:

1. **Window effective date** — used to resolve point-in-time roster:
   - Open / future windows: `today_atlantic`
   - Closed windows: `window.EndDate`
   - Formula: `CASE WHEN today > window.EndDate THEN window.EndDate ELSE today END`

2. **Role-branched student resolution**:
   - **Teacher** (`AccessLevel IS NULL` and has FactSectionTeachers rows): students enrolled in sections they taught during the window. Resolve via FactSectionTeachers + DimSection + FactEnrollment, all gated on the window effective date being within each table's effective period.
   - **School Admin** (`AccessLevel IN ('Administrator', 'SpecialistTeacher')`): students whose DimStudent (effective at the window date) had `SchoolID` in their current `StaffSchoolAccess` list. Note: StaffSchoolAccess is CURRENT-only — admin role changes are not historically reconciled, only student-side movements are.
   - **Regional Analyst** (`AccessLevel = 'RegionalAnalyst'`): all students whose DimStudent (effective at the window date) matches the window's grade/program scope.

3. **Window-scope filter** applies to the historically-resolved student: grade-range BETWEEN via DimGrade.GradeOrder, ProgramFamily via DimProgram.

**Pattern for the SQL** (skeleton):

```sql
WITH AtlanticToday AS (
    SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
),
Caller AS (
    SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
    FROM DimStaff d
    WHERE LOWER(d.Email) = LOWER(CURRENT_USER) AND d.IsCurrent = 1
),
WindowEffectiveDates AS (
    SELECT w.*,
           CASE WHEN at.Today > w.EndDate THEN w.EndDate ELSE at.Today END AS EffectiveDate,
           CASE WHEN at.Today < w.StartDate THEN 'Upcoming'
                WHEN at.Today > w.EndDate   THEN 'Closed'
                WHEN at.Today = w.EndDate   THEN 'ClosesToday'
                ELSE 'Open' END AS WindowStatus
    FROM DimAssessmentWindow w CROSS JOIN AtlanticToday at
    WHERE w.ActiveFlag = 1
),
-- Three role-branch CTEs, then UNION ALL the results
TeacherStudents AS (...),
AdminStudents   AS (...),
AnalystStudents AS (...),
ApplicableStudents AS (
    SELECT * FROM TeacherStudents
    UNION ALL SELECT * FROM AdminStudents
    UNION ALL SELECT * FROM AnalystStudents
)
SELECT ... FROM WindowEffectiveDates wed
INNER JOIN ApplicableStudents a ON a.AssessmentWindowID = wed.AssessmentWindowID
LEFT JOIN FactAssessmentReading far ON ...
GROUP BY ...;
```

The branching is by `Caller.AccessLevel` inside each role-CTE's WHERE clause. The CTEs aren't mutually exclusive in code, but in practice only one returns rows for a given caller (the role check filters the other two to empty).

**Applies to three views**:

1. **`vw_UserAssessmentWindows`** — primary use case. Returns one row per (user, window) with applicable student count + entered count, both using the historically-reconciled student set.

2. **`vw_TeacherGroups`** — must also use the historical effective-date pattern. A teacher's groups for a closed window are the groups they HAD AT THAT TIME. Returns one row per (user, window, group) with student counts per group; Power Apps filters client-side by the selected `WindowID`.

3. **`vw_TeacherRoster`** — same treatment. Returns one row per (user, window, group, student) with existing assessment value if any. Power Apps filters client-side by selected window + group.

**Implication for view shape**: these views are no longer parameterized by "current window only" — they return rows tagged with `AssessmentWindowID`, and Power Apps filters the gallery `Items` to the selected window. Larger row counts but accurate historical semantics.

**Performance note (MVP scale ok, watch at full rollout)**: each view evaluates the historical-reconciliation joins for every accessible window every time it's queried. At pilot scale (~6 windows × ~30 students per teacher) it should complete sub-second. At full rollout (10 years of windows × 200 teachers), monitor. If it becomes a bottleneck, materialize per-window-snapshot tables on `usp_UpsertReadingAssessment` and other mutation paths.

**Important wrinkle — admin-side historical reconciliation is NOT applied**:
- `StaffSchoolAccess` is treated as current-only. An admin who moved from School A to School B last year sees only School B's data, including historical windows from when they were at School A.
- Rationale: admin role changes are operational, not analytical. We don't model admin career history; the model assumes "current admin authority = full authority over current scope." If this becomes a problem at full rollout, requires extending DimStaff history tracking and adding `vw_AdminHistoricalSchools` — out of scope for MVP.

**Power Apps integration**:
- `vw_UserAssessmentWindows` is queried once when scrWindowSelect loads
- After tap, `gblSelectedWindow` is set; scrGroupSelect filters `vw_TeacherGroups` Items to `WindowID = gblSelectedWindow.AssessmentWindowID`
- After group tap, scrRosterGrid filters `vw_TeacherRoster` Items to `WindowID = gblSelectedWindow.AssessmentWindowID AND GroupKey = gblSelectedGroup.GroupKey`
- All client-side filtering on already-loaded data — no extra SQL roundtrips per navigation
