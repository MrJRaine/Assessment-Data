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
