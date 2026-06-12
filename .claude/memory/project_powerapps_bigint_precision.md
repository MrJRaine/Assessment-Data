---
name: powerapps-bigint-precision
description: "Power Fx Number is IEEE 754 double — precision-safe to 16 digits (2^53). BIGINT IDENTITY surrogate keys in Fabric Warehouse exceed that (Fabric's default IDENTITY allocator emits ~19-digit values). Expose surrogate keys to Power Apps as VARCHAR(20), not BIGINT, or filter comparisons silently return zero rows."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4d570a0f-69a3-4502-9cc3-3a36fa574b9d
---

**Power Fx Number cannot precisely represent Fabric BIGINT IDENTITY values.** Cast surrogate keys to VARCHAR(20) in every view that Power Apps reads from, and take VARCHAR(20) parameters in every proc Power Apps calls.

## The math

- Power Fx Number = IEEE 754 double-precision = 53-bit mantissa = max safe integer 2^53 = **9 007 199 254 740 992** (16 digits).
- Fabric Warehouse BIGINT IDENTITY allocator emits ~19-digit values (e.g. `6593269854470406145`).
- Any value above ~9 × 10^15 loses precision when round-tripped through Power Fx Number.

## How it bit us (2026-05-21)

scrGroupSelect's gallery used `Filter(vw_TeacherGroups, AssessmentWindowID = gblSelectedWindow.AssessmentWindowID)`. SQL returned 3 rows directly, but the Power Apps filter returned zero. Hypothesis: the BIGINT got coerced to Power Fx Number (rounded), then delegation serialized the rounded Number back to SQL as a parameter, and the comparison `BIGINT actual = parameter rounded` matched no rows. Note: display worked fine (lblWindowName showed the right window) because string columns don't go through this path — only the BIGINT key comparison.

## Fix pattern

**Views** — cast surrogate keys to VARCHAR(20) in the final SELECT:
```sql
CAST(AssessmentWindowID AS VARCHAR(20)) AS AssessmentWindowID,
CAST(StudentKey         AS VARCHAR(20)) AS StudentKey,
CAST(ReadingScaleID     AS VARCHAR(20)) AS ReadingScaleID,
```
Internal joins keep using BIGINT — only the surface column exposed to Power Apps changes. VARCHAR(20) is enough for any positive BIGINT (max value 9223372036854775807 = 19 digits).

**Stored procs** — take VARCHAR(20) parameters, CAST internally:
```sql
CREATE PROCEDURE usp_UpsertReadingAssessment
    @StudentNumber       BIGINT,           -- 10-digit provincial #, within safe range
    @AssessmentWindowID  VARCHAR(20),      -- was BIGINT; Power Apps sends string
    @ReadingScaleID      VARCHAR(20),      -- was BIGINT; Power Apps sends string
    @AssessmentDate      DATE
AS
BEGIN
    DECLARE @AssessmentWindowID_BI BIGINT = CAST(@AssessmentWindowID AS BIGINT);
    DECLARE @ReadingScaleID_BI     BIGINT = CAST(@ReadingScaleID     AS BIGINT);
    -- ... rest of proc uses the _BI locals for joins
END
```

**Tables** — you can't cast at the table level. If Power Apps needs to read a BIGINT IDENTITY directly from a table (e.g. `DimReadingScale`), wrap it in a view:
```sql
CREATE VIEW vw_DimReadingScale AS
SELECT CAST(ReadingScaleID AS VARCHAR(20)) AS ReadingScaleID,
       LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag
FROM DimReadingScale;
```
Then add `vw_DimReadingScale` (not `DimReadingScale`) as the Power Apps data source. Document the wrapper in the table's source file.

## What's safe to leave as BIGINT (no cast)

- `StudentNumber` — provincial 10-digit number, well within 16-digit safe range.
- Any BIGINT representing a count, age, or small ordinal.
- Internal BIGINT joins inside views — Power Apps never sees them.

## What needs the cast (audit list)

Anything that's both (a) a BIGINT IDENTITY in Fabric and (b) read by Power Apps:

- `AssessmentWindowID` (DimAssessmentWindow PK) — used in 3 views + 1 proc
- `StudentKey` (DimStudent PK) — surfaced by vw_TeacherRoster
- `StaffKey` (DimStaff PK) — internal-only currently; cast if exposed later
- `SectionKey` (DimSection PK) — internal-only currently; cast if exposed later
- `ReadingScaleID` (DimReadingScale PK) — used by cmbNewLevel + 1 proc
- `ReadingAssessmentID` (FactAssessmentReading PK) — surfaced by vw_TeacherRoster as ExistingReadingAssessmentID

## Status

- 2026-05-21 deployed: vw_UserAssessmentWindows, vw_TeacherGroups, vw_TeacherRoster — all AssessmentWindowID + roster's StudentKey/ExistingReadingAssessmentID/ExistingReadingScaleID cast to VARCHAR(20). Migration script: [sql/scripts/migrate_views_AssessmentWindowID_VARCHAR.sql](../../../../../Git-Repos/Assessment-Data/sql/scripts/migrate_views_AssessmentWindowID_VARCHAR.sql).
- 2026-05-21 NOT yet done: `usp_UpsertReadingAssessment` parameters still BIGINT. Update when we wire scrRosterGrid's Save action — flip `@AssessmentWindowID` + `@ReadingScaleID` to VARCHAR(20), CAST to BIGINT inside. Also add a `vw_DimReadingScale` wrapper view for the cmbNewLevel dropdown.

## Related

[[powerapps-control-names-globally-unique]] — different gotcha, also Power-Apps-specific.
[[powerapps-control-templates-verified]] — control template reference.
