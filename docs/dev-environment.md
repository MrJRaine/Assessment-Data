# Dev / Test Environment + Promotion Runbook

**Goal:** a non-live Fabric workspace (warehouse + lakehouse) seeded with **synthetic** data, so all
development and testing — including anything Claude runs or screenshots — happens against fake data.
Promotion to live is then a `.env` swap on the container plus applying the same SQL changes to the
live warehouse. Keeps real student PII out of the dev loop entirely (see memory
`feedback_live_pii_boundary`).

---

## 1. Design

Dev lives in the **same workspace** as live, organized under a **Dev folder** — so the SP's
Contributor grant and the capacity assignment are already in place (nothing new to configure). The
one consequence: item names must be unique within a workspace, so the dev items take a `_Dev` suffix.

| | Live (today) | Dev (new) |
|---|---|---|
| Workspace | `Regional_Data_Portal` | **same** `Regional_Data_Portal` (in a *Dev* folder) |
| Warehouse | `Assessment_Warehouse` | `Assessment_Warehouse_Dev` |
| Lakehouse | `Assessment_Landing` | `Assessment_Landing_Dev` |
| Capacity | F8 (grant) | **same workspace ⇒ same capacity** (nothing to assign) |
| SP access | Contributor | **already Contributor on the workspace** (nothing to add) |
| Data | real PowerSchool (eventually) | **synthetic only** |

**Item names differ, but SQL object names don't:** `dbo.DimStudent`, the procs, views, and TVFs all
live *inside* the warehouse, so they're identical regardless of the warehouse's item name. The deploy
scripts run against whichever warehouse you're connected to, and the app picks the target by
`FABRIC_SQL_DATABASE`. So *nothing in the repo or app code differs between dev and live* — only the
`.env` target. The OneLake folder paths (`Files/imports/{topic}/`) are also identical inside each lakehouse.

> **Same-workspace caution:** dev and live items sit side by side, so when running SQL by hand be sure
> you're connected to **`Assessment_Warehouse_Dev`**, not live — the `_Dev` suffix is the visual guard.
> They also share the F-capacity compute; a heavy dev ingest competes with live, but at pilot scale
> that's negligible.

---

## 2. Portal setup checklist (one-time — your clicks)

No new workspace, capacity, or permissions — just two new items in the existing workspace:

1. **Create a *Dev* folder** in `Regional_Data_Portal` (New folder).
2. **Create lakehouse** `Assessment_Landing_Dev` in the Dev folder.
3. **Create warehouse** `Assessment_Warehouse_Dev` in the Dev folder.
4. **Collect the dev connection values** → they go into a new **`webapp/.env.dev`** file (the §5 table; gitignored, read by the container via `--env-file`). The only things that differ from live:
   - **Dev warehouse SQL connection string** (warehouse → Settings → SQL connection string) → `FABRIC_SQL_SERVER` (host) + `FABRIC_SQL_DATABASE` = `Assessment_Warehouse_Dev`. (The host may match live since it's the same workspace — use whatever the dev warehouse's string shows.)
   - **Dev lakehouse GUID** → `ONELAKE_LANDING_LAKEHOUSE`, from the lakehouse URL (`…/{workspaceGUID}/…/{lakehouseGUID}`).
   - `ONELAKE_WORKSPACE` is the **same workspace GUID as live** (same workspace) — no new value.

> **Heads-up:** the `COPY INTO` source paths in the `usp_Load*Staging` procs are **hard-coded** to the
> live lakehouse GUID. For the dev warehouse those procs must point at the **dev lakehouse** GUID
> (same workspace GUID, different lakehouse GUID). See §3, note ★.

---

## 3. Stand up the dev schema (run in the dev warehouse SQL editor, in this order)

Base object files are kept **current** (migrations are folded in) — so a fresh build runs the base
files + seeds and **ignores every `sql/scripts/migrate_*` script**. This order doubles as the live
redeploy/DR order.

**Tier 1 — reference dimensions** (independent; several seed inline, rest via `seed_*`)
```
dimensions/DimGender.sql            (inline seed)
dimensions/DimGrade.sql       + scripts/seed_DimGrade.sql
dimensions/DimRole.sql              (inline seed)
dimensions/DimProgram.sql           (inline seed)
dimensions/DimTerm.sql              (inline seed)
dimensions/DimCalendar.sql          (inline seed; or scripts/repopulate_DimCalendar.sql)
dimensions/DimSchool.sql      + scripts/seed_DimSchool_TCRCE.sql
dimensions/DimReadingScale.sql      + scripts/seed_DimReadingScale_EN.sql + _FR.sql
dimensions/DimReadingBenchmark.sql  + scripts/seed_DimReadingBenchmark_EN.sql + _FR.sql
dimensions/DimAchievementLevel.sql  + scripts/seed_DimAchievementLevel.sql
dimensions/DimAssessmentWindow.sql  + scripts/seed_DimAssessmentWindow_MVP.sql
```
**Tier 2 — core SCD dimensions**
```
dimensions/DimStudent.sql
dimensions/DimStaff.sql
dimensions/DimSection.sql            (FK → DimStaff)
```
**Tier 3 — facts**
```
facts/FactEnrollment.sql   facts/FactSectionTeachers.sql   facts/FactStaffAssignment.sql
facts/FactAssessmentReading.sql   facts/FactAssessmentWriting.sql   facts/FactStudentIPP.sql
facts/FactSubmissionAudit.sql   facts/FactDataQualityAudit.sql
```
**Tier 4 — staging + working tables**
```
staging/Stg_Student.sql  Stg_Staff.sql  Stg_Section.sql  Stg_Enrollment.sql  Stg_CoTeacher.sql
staging/Wrk_Student.sql  Wrk_StaffPersons.sql  Wrk_StaffAssignment.sql  Wrk_Section.sql
staging/Wrk_SectionTeacher.sql  Wrk_Enrollment.sql
```
**Tier 5 — security table**
```
security/StaffSchoolAccess.sql       (materialized table; populated by the staff merge)
```
**Tier 6 — procedures** ★ *in the 5 `usp_Load*Staging` `COPY INTO` paths, swap the live lakehouse GUID for the **dev lakehouse** GUID before running (workspace GUID stays the same)*
```
procedures/usp_LoadStudentsStaging.sql  usp_LoadStaffStaging.sql  usp_LoadSectionStaging.sql
procedures/usp_LoadEnrollmentStaging.sql  usp_LoadCoTeacherStaging.sql
procedures/usp_MergeStudent.sql  usp_MergeStaff.sql  usp_MergeSection.sql
procedures/usp_MergeEnrollment.sql  usp_MergeSectionTeachers.sql
procedures/usp_RunDataQualityChecks.sql  usp_RunFullIngestCycle.sql  usp_TriggerIngestCycle.sql
procedures/usp_YearEndCloseOut.sql  usp_InsertSubmissionAudit.sql
procedures/usp_UpsertReadingAssessment.sql  usp_DeleteReadingAssessment.sql  usp_UpsertStudentIPP.sql
```
**Tier 7 — views**
```
security/vw_TeacherStudents.sql  vw_SchoolStudents.sql  vw_RegionalData.sql
security/vw_UserAssessmentWindows.sql  vw_TeacherGroups.sql  vw_TeacherRoster.sql
security/vw_StudentCohort.sql  vw_StudentAssessmentHistory.sql  vw_StudentIPP.sql  vw_StudentCohortTeachers.sql
security/vw_DimReadingScale.sql
security/bridge_views.sql            (legacy; optional — app now uses the TVFs below)
```
**Tier 8 — inline TVFs (the web app's read path)**
```
security/tvf_UserAssessmentWindows.sql  tvf_TeacherGroups.sql  tvf_TeacherRoster.sql
security/tvf_StudentCohort.sql  tvf_StudentAssessmentHistory.sql  tvf_StudentIPP.sql
```
**Tier 9 — grants** (after the SP exists in the dev warehouse, i.e. after step 2.4)
```
security/grant_webapp_sp.sql
```
> Each TVF/proc file also self-grants on redeploy, but run the master grant once to cover everything.

> **Verify on first run.** I can't execute against the dev warehouse until it exists, so treat this
> order as best-effort dependency order — the dev warehouse is the safe place to shake out any
> ordering hiccup. Once you've created it, I can drive the deploy + fix ordering against synthetic data.

---

## 4. Seed synthetic data (dev only)

1. **Reference dims** are already seeded by Tier 1 above.
2. **Synthetic PowerSchool exports** live in `data/imports/{topic}/` (TAB `.text`; co-teachers `.csv`).
   Regenerate/extend with `data/imports/_generate_test_dummies.ps1` if needed.
3. **Land them in the dev lakehouse** `Files/imports/{topic}/` — once `.env.dev` points the container at
   dev (see §5), use the **/ingest** screen to upload each file, **or** upload via the portal.
4. **Run the ingest cycle** — `/ingest` → *Run ingest cycle*, or `EXEC usp_RunFullIngestCycle` (or
   `scripts/reset_and_run_full_ingest.sql`). Populates DimStudent/Staff/Section + FactEnrollment/SectionTeachers.
5. **Assessment windows** — `seed_DimAssessmentWindow_MVP.sql` (Tier 1) gives the EN + FR windows.
6. **A self-test analyst row** — ensure a `RegionalAnalyst` `DimStaff` row exists for the UPN you'll use as
   `DEV_FAKE_UPN` (e.g. `jeffrey.raine@tcrce.ca`), so the role-branched reads return data.
7. **Some assessment + IPP rows** — enter a few via the app, or use `scripts/reset_ipp_and_assessments.sql`
   to (re)create the NULL "needs-confirmation" IPP gate rows for testing that flow.

---

## 5. `.env.dev` vs `.env.live`

Keep two env files; **only six values differ** (the SP creds, auth secret, region, etc. are identical):

| Variable | `.env.dev` | `.env.live` |
|---|---|---|
| `AUTH_MODE` | `dev` (bypasses Entra so Claude/headless can reach screens; flip to `entra` only after the `:3001` redirect URI is registered — see note below) | `entra` |
| `DEV_FAKE_UPN` | synthetic analyst UPN | *(unset)* |
| `FABRIC_SQL_SERVER` | dev warehouse host | live warehouse host *(may be the same host)* |
| `FABRIC_SQL_DATABASE` | `Assessment_Warehouse_Dev` | `Assessment_Warehouse` |
| `ONELAKE_LANDING_LAKEHOUSE` | **dev** lakehouse GUID | live lakehouse GUID |

Identical in both (same workspace + same SP): `ONELAKE_WORKSPACE` (the shared workspace GUID),
`ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`, `AUTH_SECRET`/`NEXTAUTH_*`,
`DATA_REGION=canadaeast`. Both files stay **gitignored**.

**Run dev + live side by side** (same image, different env + host port — they coexist because dev is
`AUTH_MODE=dev` and never touches Entra, so there's no OAuth redirect clash):
```
podman run -d --name awdev  --env-file webapp/.env.dev  -p 3001:3000 assessment-webapp:token   # dev  → localhost:3001
podman run -d --name awtest --env-file webapp/.env.live -p 3000:3000 assessment-webapp:token   # live → localhost:3000
```
`AUTH_MODE=dev` only changes who the *end user* is (resolved to `DEV_FAKE_UPN`); the Fabric connection
is still the real service principal, so dev validates the full identity → `@UPN` scope → read/write/ingest
flow against live Fabric — everything except the literal Entra sign-in screen.

**Impersonation bar (dev only).** In dev mode an amber bar sits under the header letting you run the app
as any synthetic staff member without editing `DEV_FAKE_UPN` or restarting the container — handy for
making how-to docs from a teacher's / admin's point of view. Pick from the dropdown (teachers with a
roster, plus privileged staff) or type any UPN; **Reset to default** clears it back to `DEV_FAKE_UPN`.
It writes an httpOnly `dev_impersonate_upn` cookie that `getCurrentUpn()` honours **only** in dev mode
(the server actions and `getCurrentUpn` both hard-gate on dev), so it is completely inert on the
entra/live path — the bar never renders and the cookie is never read there. The identity widget and the
capability-gated nav (Cycles/Ingest) both re-resolve to the impersonated UPN so screenshots are accurate.

> **TODO (IT, deferred):** to run dev under real Entra login (`AUTH_MODE=entra` in `.env.dev`), the dev
> callback `http://localhost:3001/api/auth/callback/microsoft-entra-id` must be added to the
> `StudentDataAssessment` app registration's redirect URIs. IT-gated ([[project_entra_appreg_it_gated]]).
> Also watch localhost cookie overlap with live (`:3000`) when both run in entra mode.

---

## 6. Promotion: dev → live

1. Build + test the change on **dev** (apply the SQL to the dev warehouse; test the app against dev with synthetic data; for Claude, headless/screenshot verification happens here).
2. Apply the **same SQL file(s)** to the **live** warehouse, in dependency order (objects are `DROP+CREATE`
   / self-granting). Re-run `grant_webapp_sp.sql` if you redeployed a proc/TVF/view.
3. Point the container at live: rebuild the image only if **code** changed, then
   `podman run … --env-file webapp/.env.live …`.
4. Smoke-test live: `/api/health`, sign in, open one screen. **Verification stays PII-free** — counts /
   "does it load", not row dumps (see §7).

---

## 7. PII boundary (why this exists)

- **Dev = synthetic, and is Claude's sandbox.** All of Claude's iteration, queries, and any
  headless-browser screenshots run here, where there is no real PII.
- **Live = no row-level reads by Claude.** Once real PowerSchool data is ingested, Claude runs only
  schema / `COUNT(*)` / deploys against live — never queries that return student rows, and never points
  a screenshot tool at live. Full rule: memory `feedback_live_pii_boundary`.
