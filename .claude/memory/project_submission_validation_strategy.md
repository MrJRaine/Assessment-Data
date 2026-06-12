---
name: Submission Validation Strategy (defense-in-depth)
description: Validate submissions at multiple layers — Power Apps client-side, then proc-entry server-side — BEFORE the data reaches DML. Last-line database guards (e.g. THROW in delta CASE) are safety nets, not the primary error reporting path. Decided 2026-05-12.
type: project
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**Validate before writing. The database is the last line of defense, not the first.**

**Why:** User flagged 2026-05-12 that data validation should screen submissions for range / consistency BEFORE writing to the database — `THROW`s inside compute logic (like the `ReadingDelta` CASE) should be safety nets for "should never happen" cases, not the primary mechanism for catching bad data. Reasoning: surface errors close to the source (UI), don't let bad data round-trip to the proc, don't have teachers see cryptic SQL error codes.

**Three validation layers, in order:**

**Layer 1: Power Apps client-side validation** (in the form, BEFORE the Save button submits)

**Strongest version of Layer 1: constrain the inputs themselves via data-driven `Items` filters so invalid choices are impossible to make.** This eliminates whole classes of error before they can be submitted, making most Layer 2 checks safety nets rather than user-facing error paths.

For the reading-assessment entry flow (`scrRosterGrid`):

- **Pre-populated dropdowns scoped to the relevant scale system** — `cmbNewLevel.Items` filters `DimReadingScale` by `gblSelectedWindow.ScaleSystem` (and `ActiveFlag = TRUE`) so teachers can only pick levels valid for the window they're in. English window → DT/A-Z; French window → whatever the FR_Reading levels are. Sort by `LevelOrder` ascending so the progression matches teacher mental model:
  ```
  SortByColumns(
      Filter(DimReadingScale,
          ScaleSystem = gblSelectedWindow.ScaleSystem
          && ActiveFlag = TRUE),
      "LevelOrder"
  )
  ```
  This makes the proc's ScaleSystem-mismatch check (THROW 51014) a programmer-error guard, not a user-error guard.

- **Roster gallery already filtered to applicable students** — `vw_TeacherRoster` returns only students whose grade range matches the window. Teacher can't even see students outside the scope, let alone submit assessments for them.

- **Save button gated on validation** — `DisplayMode` of `Disabled` when any required field is empty or invalid; visual indicators on invalid rows (red border, tooltip explaining the issue).

- **Window/role gating** (`gblCanEdit`) suppresses Save entirely if user can't write to this window (read-only mode for teachers viewing closed windows).

- **Pre-submit field check** — `IsValid(record)` helper checks all required-field rules; Save button `OnSelect` ForAll's only the rows that pass; Notify-toast the user about any skipped rows.

**Principle:** If the data model can constrain it via filtering, do that — don't write validation that checks "is this thing valid?" when you can use the data model to make only-valid-things selectable in the first place.

**Layer 2: Server-side proc input validation** (FIRST thing inside `usp_Upsert*` procs, BEFORE any INSERT/UPDATE)

Pattern for `usp_UpsertReadingAssessment`:
```sql
-- 1. Required parameters not NULL
IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL
    OR @ReadingScaleID IS NULL OR @AssessmentDate IS NULL
BEGIN
    ;THROW 51010, 'usp_UpsertReadingAssessment: required parameter is NULL', 1;
END;

-- 2. Student resolves via effective-date join
IF NOT EXISTS (
    SELECT 1 FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31')
)
BEGIN
    ;THROW 51011, 'usp_UpsertReadingAssessment: StudentNumber does not resolve to a DimStudent row at AssessmentDate', 1;
END;

-- 3. Window resolves and is active
IF NOT EXISTS (SELECT 1 FROM DimAssessmentWindow w
               WHERE w.AssessmentWindowID = @AssessmentWindowID AND w.ActiveFlag = 1)
BEGIN
    ;THROW 51012, 'usp_UpsertReadingAssessment: AssessmentWindowID does not resolve to an active window', 1;
END;

-- 4. Scale value resolves
IF NOT EXISTS (SELECT 1 FROM DimReadingScale rs
               WHERE rs.ReadingScaleID = @ReadingScaleID AND rs.ActiveFlag = 1)
BEGIN
    ;THROW 51013, 'usp_UpsertReadingAssessment: ReadingScaleID does not resolve to an active level', 1;
END;

-- 5. Scale system matches window's expected system
IF NOT EXISTS (
    SELECT 1
    FROM DimReadingScale rs
    INNER JOIN DimAssessmentWindow w ON w.ScaleSystem = rs.ScaleSystem
    WHERE rs.ReadingScaleID = @ReadingScaleID
      AND w.AssessmentWindowID = @AssessmentWindowID
)
BEGIN
    ;THROW 51014, 'usp_UpsertReadingAssessment: ReadingScaleID ScaleSystem does not match the window ScaleSystem', 1;
END;

-- 6. Student grade is within window's grade range (via DimGrade.GradeOrder)
-- ... etc.

-- 7. Window edit permission for this caller (role + window state)
-- ... etc.

-- After all validation passes, proceed to compute ReadingDelta + INSERT/UPDATE
```

Each validation has its own THROW code (51010+) so Power Apps can surface a meaningful message to the teacher. Codes 51001-51009 reserved for compute-logic safety nets (the impossible-state guards).

**Layer 3: Compute-logic safety nets** (LAST line of defense, should never fire in practice)

The `IF…THROW` on NULL `LevelOrder` values before the `ReadingDelta` CASE is one of these — it catches programming errors and race conditions, not user errors. If a Layer-2 validation already verified that `@ReadingScaleID` and the benchmark row both exist, the NULL case is essentially impossible at compute time. The safety-net THROW is fine but should be rare.

**Error code allocation:**
- `51001-51009`: Layer 3 safety nets (impossible-state guards)
- `51010-51029`: Layer 2 input validation (user-fixable submission errors)
- `51030-51049`: Layer 2 permission failures (role / window state)
- `51050+`: reserved for future use

**Power Apps error surfacing:**

Wrap each `usp_*` proc call in a try/catch-equivalent. Power Fx doesn't have try/catch but does have `IfError()`:

```
IfError(
    'Assessment_Warehouse'.dbouspUpsertReadingAssessment({...}),
    Notify("Could not save: " & FirstError.Message, NotificationType.Error)
)
```

The proc's RAISERROR message text should be teacher-friendly ("Student not in your roster", not "FK constraint violation on StudentKey").

**Why all three layers:**
- Layer 1 catches typos, missing fields, and obvious mistakes before any roundtrip
- Layer 2 catches anything that bypasses Layer 1 (URL manipulation, API misuse, dev tools, race conditions where the data changed between load and submit)
- Layer 3 catches programmer bugs and unexpected data corruption

Don't skip any layer — they catch different classes of problem and the cost of each is small.

**Applies to all write procs going forward:**
- `usp_UpsertReadingAssessment` (Step 18 — first one to follow the pattern)
- `usp_InsertWritingAssessment` (Phase 5)
- Any future writes from Power Apps to Fabric Warehouse via the stored-proc pattern

**Note on `usp_InsertSubmissionAudit`** (already deployed 2026-05-11): the smoke-test proc doesn't currently follow this pattern — it just trusts its inputs. That's fine for the audit table (worst case is a junk audit row) but should be revisited if `FactSubmissionAudit` ever becomes consequential downstream.
