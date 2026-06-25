---
name: project_dev_live_environment_split
description: "Dev/test = `_Dev`-suffixed warehouse+lakehouse in the SAME workspace as live (Dev folder; reuses the SP Contributor grant + capacity), SYNTHETIC data; develop+test there, promote by applying the same SQL to live + swapping the container .env. Runbook in docs/dev-environment.md."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

Decided 2026-06-22. To keep real PII out of the dev loop ([[feedback_live_pii_boundary]]) and make promotion clean:

- **Same workspace** `Regional_Data_Portal` (chosen 2026-06-22 to reuse the existing SP Contributor grant + capacity — no new permissions/capacity). Dev items sit in a **Dev folder** with a `_Dev` suffix (item names must be unique in a workspace): `Assessment_Warehouse_Dev` + `Assessment_Landing_Dev`. SQL object names live INSIDE the warehouse, so repo SQL + app code are identical across dev/live; only `.env` differs. Caution: dev+live items sit side by side — when running SQL by hand confirm you're on `Assessment_Warehouse_Dev`.
- **5 env values differ** between `.env.dev` and `.env.live`: `AUTH_MODE` (dev=`dev` so headless/Claude can reach screens via `DEV_FAKE_UPN`; live=`entra`), `DEV_FAKE_UPN`, `FABRIC_SQL_SERVER` (may be the same host — same workspace), `FABRIC_SQL_DATABASE` (`Assessment_Warehouse_Dev` vs `Assessment_Warehouse`), `ONELAKE_LANDING_LAKEHOUSE` (dev lakehouse GUID). **`ONELAKE_WORKSPACE` is the SAME** (same workspace GUID), as are ENTRA_* / AUTH_SECRET / region. Run via `podman run --env-file webapp/.env.dev|.env.live`.
- **Repo is fully reproducible:** base object files are kept CURRENT (migration history folded into headers), so a fresh build = base files + `seed_*` (and inline-seeded DimGender/DimRole/DimProgram/DimTerm/DimCalendar) + synthetic ingest. **Skip all `sql/scripts/migrate_*`** on a fresh build. Dependency-ordered deploy list = `docs/dev-environment.md` §3 (doubles as the live DR/redeploy order).
- **The one place dev/live SQL diverges:** the 5 `usp_Load*Staging` procs hard-code the lakehouse GUID in their `COPY INTO` source (name-based OneLake paths failed auth historically). For dev, swap the live lakehouse GUID for the **dev lakehouse** GUID (workspace GUID is the same). Candidate future cleanup: parameterize the path.
- **Promotion (dev→live):** test on dev (synthetic) → apply the same SQL file(s) to live in dependency order (re-run `grant_webapp_sp.sql` after any proc/TVF/view redeploy) → swap container to `.env.live` (rebuild image only if code changed) → PII-free smoke test.
- Claude **cannot** create the Fabric items (portal-only: workspace/warehouse/lakehouse, SP Contributor, GUIDs). Once created, Claude can drive the deploy + shake out ordering against synthetic data.

**Dev seed — validated end-to-end 2026-06-23 (app-driven ingest works on dev: upload→OneLake→COPY INTO→merges→DQ gate PASS). Gotchas learned:**
- **Load-proc format:** dev's synthetic exports under `data/imports/` are **TAB direct-extracts** (`.text`, `FIELDTERMINATOR='\t'`, `ROWTERMINATOR='0x0D'`), but the repo's current `usp_Load*Staging` files are the not-yet-deployed **comma/CSV** (cutover) version. `deploy_all_dev.sql` is now generated with TAB loaders for the 4 direct extracts (students/staff/sections/enrollments) and comma/CSV only for co-teachers. Don't deploy the repo CSV loaders against TAB test data.
- **Test analyst belongs in the staff FILE, not hand-INSERTed:** add `jeffrey.raine@tcrce.ca` as a **Group 40** (→RegionalAnalyst) row in `data/imports/staff/AssessmentDataStaffExport.text` (done 2026-06-23, HomeSchoolID `0167`). A manual `INSERT` into `DimStaff` fights `usp_MergeStaff` — the merge deactivates the not-in-file row, and repeated inserts produce duplicate IsCurrent=1 rows + overlapping windows that FAIL the data-quality gate. Being in the file means you survive re-ingests.
- **Full reset = the 6 orchestrator tables PLUS `FactStudentIPP` + `FactAssessmentReading`** (TRUNCATE). The canonical `reset_and_run_full_ingest.sql` lists only the 6, but `usp_MergeStudent` Step 6 populates `FactStudentIPP` off `StudentKey`, so the IDENTITY reset orphans it unless also truncated.
- **Large-paste partial apply:** pasting the full ~9.5k-line `deploy_all_dev.sql` into the Fabric web SQL editor silently skipped/errored the 5 `COPY INTO` load-proc batches while creating everything else — verify with `SELECT name FROM sys.objects WHERE type='P'` (expect 18 procs) after a fresh deploy.
