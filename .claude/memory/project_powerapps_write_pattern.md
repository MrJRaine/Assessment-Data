---
name: Power Apps Write Pattern (Fabric Warehouse)
description: Power Apps cannot Patch/SubmitForm directly to Fabric Warehouse tables — use stored-procedure data sources called from Power Apps formulas. Established 2026-05-11 (Step 16).
type: project
originSessionId: 51376352-db31-417d-b723-4cfddac4a13f
---
**Power Apps writes to Fabric Warehouse go through stored procedures, not Patch/SubmitForm.**

**Why:** Step 16 risk materialized 2026-05-11. Confirmed against `Assessment_Warehouse.FactSubmissionAudit`: the standard SQL Server connector exposes Fabric Warehouse tables for reads but `Patch(table, Defaults(table), {...})` errors with "The function 'Patch' has some invalid arguments." Diagnosis: `Defaults(<FabricTable>)` returns `{}` because the connector can't introspect Fabric's PK-less / no-DEFAULT schema enough to construct a base record. SubmitForm wraps Patch internally, so it has the same limitation.

Validated by [Shabnam Watson's blog](https://shabnamwatson.com/2024/10/26/updating-microsoft-fabric-warehouse-with-power-apps-visual-in-power-bi/) which states explicitly: *"SubmitForm and Patch don't work with Microsoft Fabric Warehouse."*

**How to apply:**

1. **For every Power Apps write target, create a wrapper `usp_Insert<X>` (or `usp_Update<X>`) stored procedure** in `Assessment_Warehouse`. Procs:
   - Take typed parameters matching the Power Apps form fields
   - Execute the INSERT/UPDATE
   - **Must NOT use the `OUTPUT` clause** (Fabric Warehouse doesn't support it — see fabric-warehouse-sql skill item 15)
   - Follow the existing `usp_*` naming convention used by all other procs in this project

2. **Expose the proc as a data source in Power Apps** via the existing SQL Server connection (same connection used for reads — no second connection needed).

3. **Call from Power Apps formulas** using the Power Apps record-literal syntax:
   ```
   'Assessment_Warehouse'.dbo.usp_InsertSubmissionAudit({
       RecordType: "ReadingAssessment",
       Source: "PowerApps",
       SubmittedBy: User().Email,
       Status: "Accepted",
       Message: "...",
       RecordCount: 1
   })
   ```

4. **Reads continue to use direct table/view access** through the same SQL connector — `vw_TeacherStudents`, `DimAssessmentWindow`, `DimReadingScale`, etc. all work with regular Power Apps formulas (Filter, LookUp, etc.). Only writes need the stored-proc wrapper.

**Wrong patterns to avoid (do not propose these in future designs):**
- `Patch(FactX, Defaults(FactX), {...})` — confirmed broken
- `SubmitForm(formCtrl)` against Fabric Warehouse data sources — same underlying issue
- Power Automate intermediary — earlier-considered fallback, not needed now that the stored-proc pattern is proven; rejected because it adds latency, requires a separate environment with its own region/permissions concerns, and obscures the data flow

**Caveat — Fabric Warehouse is not OLTP-optimized.** Frequent small writes generate parquet-file churn. At MVP / pilot volume (single-digit writes per teacher per assessment window) this is fine. At full rollout (200 teachers × 6 reading + 3 writing windows × ~25 students each) monitor and consider write batching if performance degrades. Could pre-batch in Power Apps via Collect() and flush via a single proc call per teacher session.

**Procs needed for MVP** (build incrementally as each Power Apps screen is wired up):
- `usp_InsertSubmissionAudit` — first one, also serves as Step 16 smoke test (in progress 2026-05-11)
- `usp_InsertReadingAssessment` — for FactAssessmentReading writes from teacher entry form
- `usp_InsertWritingAssessment` — Phase 5, for FactAssessmentWriting

**Status as of 2026-05-11:** stored-procedure pattern established as the design canon; smoke-test proc to validate end-to-end is the next concrete step.
