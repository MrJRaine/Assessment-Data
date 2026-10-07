# Dev warehouse catch-up → HEAD (1.1.0-dev) — 2026-10-06

**Why:** the dev `Assessment_Warehouse_Dev` fell behind the app. Root cause: the git flow
(back-merge main→dev / recreate dev worktree) only syncs **code**; nothing in it re-applies SQL to the
dev **warehouse**, and the full-rebuild bundle (`deploy_all_dev.sql`) is frozen at 2026-06-23. The 0.7.0
grace SQL is on live but was never (re)applied to dev, so:

- `usp_UpsertShortCycleHeader` on dev is pre-`@GraceHours` → **saving a cycle throws "too many arguments"**.
- `tvf_UserAssessmentWindows` on dev is pre-grace → **a closed-in-grace cycle (SCoR 1) doesn't appear in Data Entry**.

**Scope / blast radius:** incremental, **no table drops, no data loss**. One guarded column migration
(adds columns only if missing) + object `DROP+CREATE` (idempotent). Safe to run even where dev is already
current. This is NOT the full `deploy_all_dev.sql` rebuild (that drops tables and needs a re-ingest, which
IT ticket #1119 currently blocks).

**You run these; I don't touch the warehouse.** Apply in order against **`Assessment_Warehouse_Dev`**.
Trailing `GRANT … TO [StudentDataAssessment]` lines are no-ops / benign on dev (the dev SP is workspace
Contributor, not a DB principal) — the object still deploys; ignore any grant-only error.

| # | File | Brings current | Fixes |
|---|------|----------------|-------|
| 1 | [sql/deploy/live_0.7.0/01_migrations.sql](../deploy/live_0.7.0/01_migrations.sql) | `GraceHours` (DimShortCycle), `CanOverrideMath`/`CanOverrideLiteracy` (StaffAppAccess) — all guarded | prerequisite for 2–5 |
| 2 | [sql/security/tvf_UserAssessmentWindows.sql](../security/tvf_UserAssessmentWindows.sql) | grace `WindowStatus` (Open/ClosesToday/Closed[grace]/Locked) | **"No cycles" — SCoR 1 reappears** |
| 3 | [sql/procedures/usp_UpsertShortCycleHeader.sql](../procedures/usp_UpsertShortCycleHeader.sql) | `@GraceHours` parameter | **save-cycle "too many arguments"** |
| 4 | [sql/procedures/usp_SetStaffAppAccess.sql](../procedures/usp_SetStaffAppAccess.sql) | writes `CanOverride*` (needs #1's columns) | staff-access grace overrides |
| 5 | [sql/procedures/usp_UpsertReadingAssessment.sql](../procedures/usp_UpsertReadingAssessment.sql) | 51040 grace-lock gate + **today's 51014 instance-based scale fix** | late-immersion English reading entry |
| 6 | [sql/procedures/usp_UpsertWritingAssessment.sql](../procedures/usp_UpsertWritingAssessment.sql) | 51040 grace-lock gate | grace enforcement on writing |
| 7 | [sql/procedures/usp_UpsertMathAssessment.sql](../procedures/usp_UpsertMathAssessment.sql) | 51040 grace-lock gate | grace enforcement on math |
| 8 | [sql/security/tvf_StudentCohort.sql](../security/tvf_StudentCohort.sql) | 1.1.0 `@CycleGroupID` (likely already on dev — harmless re-run) | cohort cycle time-binding |

**Verify after:**
1. `/cycles` → edit SCoR 1 → **Save dates** succeeds (no server error).
2. `/enter` (Data Entry) → **SCoR 1 appears** (it's in its 7-day grace window, ended 2026-10-05).
3. Enter an **English** reading level for a **Late Immersion (J020)** student → saves (51014 fix).

**Separately** (not part of this catch-up): the `jeffrey.raine` DimStaff duplicate (one RegionalAnalyst/active
row + one NULL-access/ActiveFlag-0 row dated 2026-10-04) — see the stacked-marker diagnostic. If the entry
path still resolves you to no access after this catch-up, that's the cause, not the SQL drift.
