---
name: Fabric Warehouse Data Preview is Stale
description: The Fabric Warehouse table data-preview pane caches and does not auto-refresh — verify state via SQL COUNT(*), never via the preview pane
type: feedback
originSessionId: 3751f3e9-fe2f-4363-a306-6b6b418b7daa
---
The data-preview pane shown when you click a table in the Fabric Warehouse Explorer is a cached snapshot from when the tab was first opened. It does NOT re-query on tab focus, on switching back to it, or after stored procs run. A table can show "0 rows" in the preview while a live `SELECT COUNT(*)` returns 18.

**Why:** wasted ~30 min on 2026-04-30 chasing a phantom "DimStudent is empty" bug after running `usp_MergeStudent`. The preview pane showed empty but the table was actually populated; only the SQL count revealed the truth.

**How to apply:** never trust the data preview pane for verification. Always confirm table state with SQL:
```sql
SELECT COUNT(*) AS TotalRows, SUM(CAST(IsCurrent AS INT)) AS CurrentRows FROM <table>;
```
To refresh the preview after a known change: right-click the table in Explorer → Refresh, or close and reopen the preview tab. But for diagnostics, just go straight to SQL — it's faster and authoritative.
