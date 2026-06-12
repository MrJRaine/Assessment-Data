---
name: Full-Reset Truncate-All Rule
description: When resetting test state and running usp_RunFullIngestCycle, truncate ALL six target tables first — not just the ones being explicitly tested
type: feedback
originSessionId: 3850d3e5-464e-4d0c-a391-0c086e2b6527
---
When resetting warehouse state during testing and the next step is `EXEC usp_RunFullIngestCycle`, **truncate all six tables the orchestrator merges into, every time**. Don't selectively truncate just the tables the current test is about — always do the full set.

**Why:** ad-hoc partial truncates created repeated surprises during Step 8 / year-end close-out testing. Stale rows in DimStudent or DimStaff (which weren't being directly tested but got out of sync with the lakehouse files) caused unexpected counts and warning surfaces in unrelated merges. Truncating the full set every reset is a cheap insurance against compound state issues. Confirmed 2026-05-01 after multiple back-and-forth state-recovery cycles.

**How to apply:** When the user asks for a "reset", "fresh start", "rebuild from lakehouse", "restore baseline", or any equivalent that ends with `EXEC usp_RunFullIngestCycle`, ALWAYS use this canonical block:

```sql
TRUNCATE TABLE FactEnrollment;
TRUNCATE TABLE FactSectionTeachers;
TRUNCATE TABLE FactStaffAssignment;
TRUNCATE TABLE DimSection;
TRUNCATE TABLE DimStaff;
TRUNCATE TABLE DimStudent;
EXEC usp_RunFullIngestCycle;
```

The six tables are every dim and fact the orchestrator merges into. Order doesn't matter for TRUNCATE (no enforced FKs in Fabric Warehouse). DimSchool, DimRole, DimGender, DimProgram, DimCalendar, DimTerm, DimAssessmentWindow, DimReadingScale are reference dimensions seeded once and NOT touched by the orchestrator — leave those alone.

Do NOT add this to the orchestrator proc itself — the proc must remain idempotent and non-destructive for production scheduling. The truncate-all-six is a TEST-time reset pattern, not a production pattern.
