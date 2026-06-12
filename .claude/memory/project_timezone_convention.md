---
name: Time Zone Convention
description: Store UTC, display/compare in Atlantic time (AST/ADT with automatic DST). Fabric Warehouse server clocks are UTC by design. Established 2026-05-11.
type: project
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**Store UTC, display in Atlantic.**

**Why:** Fabric Warehouse server clocks return UTC unconditionally — `GETDATE()`, `SYSDATETIME()`, `CURRENT_TIMESTAMP` all return UTC regardless of workspace region. The user (Step 16 testing 2026-05-11) confirmed the intent is for end-user-facing time to be Atlantic local with DST awareness (AST UTC-4 standard, ADT UTC-3 daylight). The system audience is Nova Scotia school staff, so Atlantic is the only locale that matters.

**How to apply:**

**Storage**: leave as UTC. Don't shift values at write time. Every `DATETIME2` / `DATE` column in the warehouse stores UTC. Includes:
- Audit timestamps (`SubmissionTimestamp`, `LastUpdated`, `RunTimestamp`)
- SCD effective dates (`EffectiveStartDate`, `EffectiveEndDate`) — these are conceptually point-in-time markers, so UTC date is fine for storage
- Enrollment dates (`StartDate`, `EndDate` on FactEnrollment) — PS source data is date-only, no time component, so timezone doesn't apply

**Conversion for "today in Atlantic" in T-SQL** (views, procs, ad-hoc queries):
```sql
CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)
```
The Windows TZ ID `'Atlantic Standard Time'` includes automatic DST handling — returns ADT during DST window and AST outside, without conditional logic.

**Conversion for display in Power Apps / Power BI** — handle at the presentation layer:
- Power Apps: `DateAdd(utcValue, -TimeZoneOffset(utcValue), Minutes)` for client-side conversion, OR use a server-side computed display column in the view that pre-applies AT TIME ZONE
- Power BI: format datetime measures with `FORMAT(... AT TIME ZONE ..., "...")` in DAX, or apply timezone conversion in the Power Query layer

**Locations to audit and fix** (in order of priority):
1. `vw_TeacherStudents` — pre-enrolled date gate `e.StartDate <= CAST(GETDATE() AS DATE)` returns wrong date late-evening Atlantic time. Needs Atlantic conversion.
2. Merge procs' `@EffectiveDate DATE = NULL` defaults that fall back to `GETDATE()` — late-evening ingests would set effective dates to next calendar day. Convert before fallback.
3. `usp_YearEndCloseOut` — verify any internal GETDATE()-based year computation aligns with the Pipeline trigger's Atlantic-time July 1.

**What NOT to change:**
- Audit table timestamps (`FactSubmissionAudit`, `FactDataQualityAudit`) — UTC storage is correct; conversion happens only at display in Power Apps / Power BI reports.
- LastUpdated columns — same as audit; UTC fine.
- `EffectiveStartDate`/`EffectiveEndDate` on SCD dims — date-only, no time component to convert (just need to ensure the calendar-day they're set to matches Atlantic local day at write time, which the @EffectiveDate fix above handles).
