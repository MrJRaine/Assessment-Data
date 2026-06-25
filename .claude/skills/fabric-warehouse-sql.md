---
name: fabric-warehouse-sql
description: Microsoft Fabric Warehouse T-SQL compatibility guide. Use this skill when writing, reviewing, or debugging SQL for the Assessment_Warehouse in the Regional_Data_Portal Fabric workspace. Trigger whenever writing CREATE TABLE, stored procedures, views, or any T-SQL that will run in Fabric Warehouse — it has significant differences from standard SQL Server/SSMS syntax.
---

# Microsoft Fabric Warehouse — T-SQL Compatibility Guide

Fabric Warehouse is NOT standard SQL Server. It rejects many common T-SQL constructs that work in SQL Server or Azure SQL. Always write SQL against this guide before running it in the warehouse.

---

## CREATE TABLE — What Is NOT Supported

| Construct | What to do instead |
|---|---|
| `DEFAULT` constraints | Omit — supply values explicitly in every INSERT |
| `PRIMARY KEY` in CREATE TABLE | Omit — no enforced constraints |
| `FOREIGN KEY` in CREATE TABLE | Omit — define relationships in Power BI semantic model |
| `CHECK` constraints | Omit — enforce in ETL procedures |
| `UNIQUE` constraints | Omit |
| `NVARCHAR` | Use `VARCHAR` — Fabric uses UTF-8 collation so VARCHAR handles Unicode |
| `DATETIME` | Use `DATETIME2(n)` with explicit precision |
| `DATETIME2` without precision | Must specify precision: `DATETIME2(0)` through `DATETIME2(6)` |
| `INT IDENTITY` | IDENTITY columns must be `BIGINT`, not `INT` |
| `IDENTITY(1,1)` | Use bare `IDENTITY` — seed/increment parameters not supported |
| `CREATE INDEX` | Not supported — Fabric auto-manages columnstore indexes |

---

## Supported Data Types (confirmed working)

| Type | Notes |
|---|---|
| `BIGINT` | Required for IDENTITY columns |
| `INT` | Fine for non-identity columns (business keys, scores, counts) |
| `BIT` | Supported |
| `DATE` | Supported |
| `DATETIME2(0)`–`DATETIME2(6)` | Must include precision — use `DATETIME2(0)` for second-level |
| `VARCHAR(n)` | Use instead of NVARCHAR; supports Unicode via UTF-8 collation |
| `VARCHAR(MAX)` | Supported for large text (e.g. audit message columns) |

---

## CREATE TABLE — Minimal Valid Pattern

```sql
CREATE TABLE MyTable (
    MyKey       BIGINT      NOT NULL IDENTITY,   -- Surrogate PK
    BusinessID  INT         NOT NULL,
    Name        VARCHAR(100) NOT NULL,
    ActiveFlag  BIT         NOT NULL,
    CreatedAt   DATETIME2(0) NOT NULL
);
```

---

## What IS Supported

- `CREATE TABLE` with columns only (no constraints)
- `BIGINT NOT NULL IDENTITY` for surrogate keys
- `INSERT`, `UPDATE`, `DELETE`, `MERGE`
- `CREATE VIEW`
- `CREATE PROCEDURE`
- `DECLARE`, `SET`, `IF/ELSE`, `WHILE` loops
- `SELECT`, `JOIN`, `WHERE`, `GROUP BY`, `ORDER BY`
- `GETDATE()`, `DATEADD()`, `DATEDIFF()`, `FORMAT()`, `DATENAME()`, `DATEPART()`
- `CAST()`, `CONVERT()`
- `TOP`, `DISTINCT`, `CASE WHEN`

---

## Implications for This Project

**Data integrity**: Enforced through ETL stored procedures, not database constraints. The merge procedures must validate all foreign key relationships in code before inserting.

**Relationships in Power BI**: Since FK constraints can't be defined in the warehouse, all table relationships must be configured manually in the Fabric semantic model.

**Indexes**: Fabric auto-applies columnstore indexes to all tables. No manual indexing needed or supported.

**String columns**: All `NVARCHAR` in documentation and planning files should be treated as `VARCHAR` when writing actual warehouse SQL.

---

## Discovered During Schema Creation (2026-04-22)

Errors hit in sequence while deploying the initial schema to `Assessment_Warehouse`:
1. `DEFAULT` keyword not supported
2. `PRIMARY KEY` not supported in CREATE TABLE
3. `NVARCHAR` not supported — use `VARCHAR`
4. `DATETIME2` requires explicit precision (0–6)
5. `IDENTITY` columns must be `BIGINT`
6. `IDENTITY(1,1)` — seed/increment not supported, use bare `IDENTITY`
7. `CREATE INDEX` not a supported statement type

## Discovered During Data Population (2026-04-23)

8. **`ROW_NUMBER() OVER (ORDER BY (SELECT NULL))` on a CTE built from `SELECT 1 UNION ALL SELECT 1` cross-joined with itself does NOT produce the expected row count.** The query appears to succeed but silently returns far fewer rows than the cross-join math implies — likely the Fabric optimizer collapsing identical constant rows. Cross joins themselves are fine; the problem is assigning row numbers from a constant-value table.

**For generating a numbers sequence, use explicit digit values and compute the number via arithmetic rather than ROW_NUMBER:**

```sql
-- UNRELIABLE (silently produces wrong row count)
WITH L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
     L1 AS (SELECT 1 FROM L0 A CROSS JOIN L0 B),
     ...
     Nums AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM L4)

-- RELIABLE (explicit digits, number computed by arithmetic)
WITH Digits AS (
    SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
),
Nums AS (
    SELECT d4.d * 1000 + d3.d * 100 + d2.d * 10 + d1.d AS n
    FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3 CROSS JOIN Digits d4
)
-- Generates 10 000 distinct numbers; filter WHERE n <= desired_count
```

9. **Row-by-row `INSERT` inside a `WHILE` loop is extremely slow.** Populating 5844 calendar rows via a WHILE loop took 10+ minutes and did not complete cleanly. Always use set-based `INSERT ... SELECT FROM numbers_cte` for bulk data generation.

10. **`ALTER TABLE ADD COLUMN` and subsequent `UPDATE`/`SELECT` against that column cannot run in the same batch.** Fabric parses the whole script before executing, so any statement referencing the new column fails with "Invalid column name". Split into two separate query executions: run the ALTER first, then in a new query window run the UPDATE/SELECT. Same applies for DROP COLUMN followed by references to other columns.

11. **`DROP TABLE` + `CREATE TABLE` (new shape) + `INSERT` referencing new columns has the same parser failure** as item 10. Even though the CREATE will give the table its new shape at execution time, the parser checks the INSERT against the *existing* table catalog and rejects "Invalid column name" for any column not in the old shape. Discovered 2026-04-28 while running `migrate_add_LastUpdated.sql` — the combined script failed with `Msg 207 Level 16 'Invalid column name LastUpdated'` on the DimCalendar INSERT, even though the CREATE earlier in the same batch defined that column. Same workaround as item 10: split into two scripts — schema rebuild in batch 1, INSERTs in batch 2 (or higher). The "fresh CREATE TABLE with INSERT in the same script" pattern only works when the table doesn't already exist; rebuilds of existing tables must split.

## Discovered During Lakehouse Ingest Setup (2026-04-29)

12. **`COPY INTO` does NOT support `ENCODING`** in Fabric Warehouse. Standard T-SQL / Synapse `COPY INTO` accepts `ENCODING = 'UTF8' | 'UTF16'`, but Fabric Warehouse's subset rejects it with `Msg 102, Level 15 'Incorrect syntax near UTF8'`. Default encoding is UTF-8 — just omit the parameter.

    **Supported `COPY INTO` parameters** (per Fabric docs as of 2026-04-29):
    `FILE_TYPE` (CSV / PARQUET), `FIRSTROW`, `ROWTERMINATOR`, `FIELDTERMINATOR`, `FIELDQUOTE`, `COMPRESSION`, `PARSER_VERSION`, `CREDENTIAL`, `ERRORFILE`, `ERRORFILE_CREDENTIAL`.

    **Standard pattern for this project** (TAB-delimited PS exports, no quote qualifier):
    ```sql
    COPY INTO Stg_<Topic>
    FROM 'abfss://<workspace>@onelake.dfs.fabric.microsoft.com/<lakehouse>.Lakehouse/Files/imports/<topic>/<file>'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        FIRSTROW        = 2
    );
    ```

    **Staging table prerequisite**: `COPY INTO` does not create the target table. Define it first as all-VARCHAR ("load as text, validate/convert in merge"). This avoids COPY INTO failing on a single malformed value and matches the standard staging pattern.

13. **`COPY INTO` default `ROWTERMINATOR` doesn't catch CR-only line endings — silent 0-row load.** PowerSchool direct table extracts emit files with CR-only line endings (0x0D, no LF — old-Mac style), not CRLF. Without an explicit `ROWTERMINATOR = '0x0D'`, COPY INTO finds no row boundaries past the header and silently loads zero rows (no error, just `(0 records affected)`). Discovered 2026-04-29 after multiple guess-and-check cycles on a Students export. Diagnosed by counting line-ending bytes locally: file had 6064 CR, 0 LF, 0 CRLF. Adding `ROWTERMINATOR = '0x0D'` immediately loaded all 6064 rows.

    **Standard COPY INTO config for PS direct table extracts**:
    ```sql
    COPY INTO Stg_<Topic>
    FROM '<onelake_path>'
    WITH (
        FILE_TYPE       = 'CSV',
        FIELDTERMINATOR = '\t',
        ROWTERMINATOR   = '0x0D',   -- CR only (PS quirk)
        FIRSTROW        = 2
    );
    ```

    Long-term fix: the Step 29 Power Automate flow should normalize line endings (CR → CRLF or LF) on file arrival, alongside the `.text` → `.txt` rename — so downstream tooling that expects standard line endings doesn't have to special-case PS quirks.

## Discovered During RLS View Authoring (2026-05-01)

14. **`USERPRINCIPALNAME()` is NOT a recognized function** in Fabric Warehouse T-SQL. Standard SQL Server / Synapse Dedicated supports it; Fabric Warehouse rejects it with `Msg 195, Level 15 'USERPRINCIPALNAME' is not a recognized built-in function name`. **Use `CURRENT_USER` instead** — when the connection authenticates with Entra ID (the default in Fabric), `CURRENT_USER` returns the user's UPN (e.g. `jeffrey.raine@tcrce.ca`). All four of these return the same UPN value in Fabric Warehouse with Entra auth: `CURRENT_USER`, `USER_NAME()`, `SUSER_NAME()`, `SUSER_SNAME()`. Going with `CURRENT_USER` for semantic clarity (standard SQL-92 keyword, no parens needed).

    **Important caveat — DAX RLS roles still use `USERPRINCIPALNAME()`**. The DAX function exists in Power BI semantic models and works as expected there. The Fabric-specific limitation only applies to T-SQL contexts (views, stored procs, ad-hoc queries against the warehouse SQL endpoint). Don't conflate the two when writing RLS — SQL views use `CURRENT_USER`, DAX RLS roles use `USERPRINCIPALNAME()`.

    **Standard pattern for SQL view RLS in this project**:
    ```sql
    -- Wrap both sides in LOWER() defensively. DimStaff.Email and
    -- FactSectionTeachers.TeacherEmail are lowercased at ingest, but
    -- CURRENT_USER's casing is environment-dependent.
    WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
    ```

## Discovered During Power Apps Write Path Testing (2026-05-11)

15. **`OUTPUT` clause is NOT supported in Fabric Warehouse.** Standard T-SQL allows `INSERT…OUTPUT INSERTED.*`, `UPDATE…OUTPUT DELETED.col, INSERTED.col`, etc. for capturing affected-row data inline. Fabric Warehouse rejects all of these. **Workaround:** if you need the inserted/updated rows, capture them via a separate `SELECT` against the table after the write, ideally filtered by a known business key. This affects any new merge procs, write procs, and audit-trail patterns.

    Per the [Power Apps write workaround blog](https://shabnamwatson.com/2024/10/26/updating-microsoft-fabric-warehouse-with-power-apps-visual-in-power-bi/) — *"Fabric Warehouse supports sp_executesql, it does not yet support the OUTPUT clause."*

16. **Power Apps `Patch()` and `SubmitForm()` do NOT work against Fabric Warehouse tables.** The standard SQL Server connector exposes the warehouse for reads but cannot perform Patch/SubmitForm writes — `Defaults(<FabricTable>)` returns an empty record (`{}`), causing the connector to reject any Patch call with "The function 'Patch' has some invalid arguments" or similar generic errors. Confirmed against `Assessment_Warehouse.FactSubmissionAudit` 2026-05-11.

    **Workaround pattern for Power Apps writes**: create a wrapper stored procedure in the warehouse, expose it as a data source from the same SQL connection, and call it directly from Power Apps formulas:

    ```
    -- Warehouse-side proc (NO OUTPUT clause):
    CREATE PROCEDURE usp_InsertSubmissionAudit
        @RecordType  VARCHAR(50),
        ...
    AS
    BEGIN
        SET NOCOUNT ON;
        INSERT INTO FactSubmissionAudit (...) VALUES (...);
    END;
    ```

    ```
    // Power Apps OnSelect formula (approximate; Power Apps formats per locale):
    'Assessment_Warehouse'.dbo.usp_InsertSubmissionAudit({
        RecordType: "Test",
        ...
    })
    ```

    Same SQL connector that's already validated for reads — no Power Automate intermediary needed. Stored procs also align with the project's existing `usp_*` convention. This is the established Power Apps write pattern for the project; do not propose Patch/SubmitForm against warehouse tables in any future design.

    **Caveat — Fabric Warehouse is not OLTP-optimized**: per the same blog, frequent small writes generate parquet-file churn that eventually requires optimization. At MVP / pilot volume (a handful of writes per teacher per assessment window), this is fine. At full rollout (200 teachers × multiple assessments × multiple windows), monitor and consider write batching if performance degrades.

## Time Zone Convention (project-specific, 2026-05-11)

**Fabric Warehouse runs all server clocks in UTC.** `GETDATE()`, `SYSDATETIME()`, `CURRENT_TIMESTAMP` all return UTC regardless of workspace region. This is a Microsoft Fabric design choice (consistent with Azure SQL); it cannot be configured to a local timezone.

**Project convention: store UTC, display/compare in Atlantic time** (Atlantic Standard Time with automatic DST → Atlantic Daylight Time). The Atlantic Provinces school system is the only audience.

**For "today in Atlantic" in views and procs**, use:
```sql
CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)
```

Notes on `AT TIME ZONE`:
- Windows timezone ID `'Atlantic Standard Time'` includes DST handling automatically despite the legacy "Standard" naming — `AT TIME ZONE` returns ADT (UTC-3) during DST and AST (UTC-4) outside DST without any explicit logic.
- First `AT TIME ZONE 'UTC'` is required to mark a bare `DATETIME2` value as UTC (returns a `datetimeoffset`). Skipping it makes the conversion ambiguous.
- Cast back to `DATE` (or `DATETIME2`) afterward if you only need the date or want to strip the offset.

**Apply consistently:**
- Date-gated view filters (e.g. `vw_TeacherStudents`'s pre-enrolled date gate)
- Merge proc `@EffectiveDate` defaults
- Year-end close-out date computations
- Any T-SQL that compares `GETDATE()` to a `DATE`-typed column to answer "is this today?"

**Audit-only timestamps** (`SubmissionTimestamp`, `LastUpdated`, `RunTimestamp` on audit tables) — leave as UTC. Storage convention is UTC; only display-layer conversion is needed in Power Apps / Power BI for those.

## Reserved Words — bracket-quote when used as identifiers

These T-SQL reserved words have bitten this project as column names or aliases. Always wrap in `[brackets]` when used as identifiers (column names, aliases, etc.):

| Reserved word | Where it bit us | How |
|---|---|---|
| `Group` | PS staff export column name | `s.[Group]` in T-SQL — discovered during DimStaff merge proc work |
| `RowCount` | `COPY INTO` result column | `COPY INTO ... WITH (...) AS [RowCount]` or use `RowsLoaded` — discovered 2026-04-29 |
| `Current` | column alias in baseline-count query | `SUM(...) AS [Current]` — discovered 2026-05-11 while validating Step 14 ran clean |

Don't rely on `"Double quotes"` for identifier quoting in this project — it depends on `QUOTED_IDENTIFIER ON` session state. Brackets are unconditional.

## SCD Type 2 merge — same-day re-version reverses the effective window (2026-06-23)

**Symptom:** a same-day **corrective re-ingest** (the source file changes a record again on the same day its current row was created) trips the data-quality gate with `EffectiveEndDate < EffectiveStartDate` (reversed window) and, on the dimensions, a self-overlap.

**Cause:** the standard close+insert close step sets `EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate)`. If the current row's `EffectiveStartDate = @EffectiveDate` (created today), the close stamps it `@EffectiveDate - 1` < its start → reversed; and the new version inserted at `@EffectiveDate` shares "today" with the just-closed row → overlap. Hit on dev 2026-06-23 (DimStudent + DimStaff). The truncate-all reset clears the *data* but not the proc bug.

**Fix pattern (applied to all 4 merge procs):**
- **Change-close step**: add `AND d.EffectiveStartDate < @EffectiveDate` so it only versions rows that started on an earlier day.
- **Same-day change** (`d.EffectiveStartDate = @EffectiveDate` + attributes differ): **UPDATE the current row IN PLACE** with the incoming business columns — no close, no new version. The surrogate key is preserved (so fact-table references stay valid), and a same-day re-run correctly collapses into today's row.
- **Missing/deactivation close** (close-only, no replacement insert): guard the end date —
  `EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY,-1,@EffectiveDate) THEN d.EffectiveStartDate ELSE DATEADD(DAY,-1,@EffectiveDate) END`
  (closes a same-day-created-then-missing row as a valid 0-day window instead of a reversed one).
- **Bridge facts** (`FactStaffAssignment`, `FactSectionTeachers`): no overlap DQ check exists for them, only reversed-window — so the end-date guard alone suffices; no in-place needed.

DimSection is the most-exposed dimension because `EnrollmentCount` versions it on nearly every ingest. Full detail in memory `project_scd_same_day_reversion_fix`.

## Ongoing-assessment / multiple-entry fact patterns (2026-06-25)

When an assessment fact allows **multiple rows per (student, window)** (the ongoing-assessment model — grain Student×Window×Date), every read that joins that fact per (student, window) MUST pick the latest, or a plain `LEFT JOIN ... ON (window, student)` fans a student out to one row per entry:
```sql
LatestInWindow AS (
    SELECT ..., ROW_NUMBER() OVER (PARTITION BY StudentKey, AssessmentWindowID
                                   ORDER BY AssessmentDate DESC, <FactID> DESC) AS rn
    FROM FactAssessmentX WHERE AssessmentWindowID = CAST(@WindowID AS BIGINT)
)
... LEFT JOIN LatestInWindow f ON f.StudentKey = sg.StudentKey AND f.AssessmentWindowID = sg.AssessmentWindowID AND f.rn = 1
```
This bit `tvf_TeacherRoster` (reading) after the upsert grain changed — it duplicated rows until the rn=1 pick was added. The cohort TVF already partitioned by StudentKey, so it was fine.

**Reuse a shared lookup dim "by code" instead of duplicating it.** Writing's 4-trait average maps to the SAME achievement bands as reading. Rather than add a `Domain` column to `DimAchievementLevel` (which would force a `Domain='Reading'` filter into every existing reading read — miss one and a value matches two rows → duplicate output), map the derived value to a band **code** in the writing read and join by code for name+colour only:
```sql
LEFT JOIN DimAchievementLevel dal ON dal.ActiveFlag = 1 AND f.AvgScore IS NOT NULL
     AND dal.AchievementLevelCode = CASE WHEN f.AvgScore >= 3.50 THEN 4 WHEN f.AvgScore >= 2.75 THEN 3
                                         WHEN f.AvgScore >= 1.75 THEN 2 ELSE 1 END
```
Zero change to the proven reading reads; the dim's reading-delta bounds simply aren't used on the writing path.

**Monthly-window generator gotchas** (`usp_GenerateMonthlyWindows`):
- Month-end via `DATEADD(DAY, -1, DATEADD(MONTH, n+1, @firstOfMonth))` — don't rely on `EOMONTH`/`FORMAT`/`DATEFROMPARTS` (CLR-ish; treat as unavailable in Fabric Warehouse). Month-name via a `CASE MONTH(d)` map, not `FORMAT`.
- **NULL-safe idempotency**: when a key column can be NULL (writing's `ScaleSystem`), `w.Col = sc.Col` is UNKNOWN for NULLs and the `NOT EXISTS` re-inserts every run — use `ISNULL(w.Col,'~') = ISNULL(sc.Col,'~')`.

**`DROP PROCEDURE IF EXISTS` hygiene**: a bare `CREATE PROCEDURE` errors `Msg 2714 (object already exists)` on redeploy. Every proc/function file should start with `DROP ... IF EXISTS; GO` so a re-run is self-contained (bit us on `usp_RunDataQualityChecks`).
