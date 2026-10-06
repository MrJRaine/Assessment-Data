---
name: reference_it_modifies_sps_and_copyinto_auth
description: "When app sign-in or ingest breaks with 'nothing changed in our code', suspect IT modified the Entra app registrations / service principals or tenant SP settings — check those FIRST. Plus: Fabric COPY INTO from OneLake is caller-passthrough only (no Managed Identity)."
metadata:
  node_type: memory
  type: reference
---

**Set 2026-10-04**, after a multi-hour ingest debug.

## IT changes the Entra apps / SPs without notifying us — check that FIRST
Two prod-auth breakages traced to IT modifying the app registrations / service principals / tenant SP
settings with no notice:
- **Local sign-in broke** — the **login app** (`TCRCE Data Web App`, client ID `819f9480-5e65-469e-be27-89ac30381f1f`, tenant `0320ef6f-7349-4acf-b62a-e780da155b7e`) lost its `http://localhost:3000/api/auth/callback/microsoft-entra-id` redirect URI (AADSTS50011). **RECURRED 2026-10-05** (localhost confirmed absent again) → IT request now asks for BOTH `:3000` and `:3001` localhost redirect URIs: `docs/it-request-login-redirect-uris.md`. Callback path = `/api/auth/callback/microsoft-entra-id`; keep the prod URI `https://data.tcrce.ca/...`.
- **In-app ingest broke** — the **data SP** (`StudentDataAssessment`, App ID `c33fb2d3-b64e-4818-aa9b-0ac7515f1710`) can still connect + run SQL + is workspace **Contributor**, but can no longer get a **OneLake token for `COPY INTO`**. **IT ticket #1119**. **UPDATE 2026-10-06 — tenant-setting hypothesis DISPROVEN:** IT confirmed **"Service principals can call Fabric public APIs" = Enabled for the ENTIRE org, no security-group exceptions** (screenshot). So the SP is NOT blocked by that toggle. Remaining cause per MS docs = the SP's **control-plane Fabric token was never (re)established**: `COPY INTO`/OPENROWSET (data plane) needs a control-plane token that is minted ONLY by a Fabric REST API call (`api.fabric.microsoft.com`), NOT by the SQL connection — and our app only ever connects via SQL + mints its own `storage.azure.com` token (upload), so nothing bootstraps/refreshes the Fabric token (which also lapses ~30d). NEXT ACTION (self-serviceable, setting now allows it): `az login --service-principal` as the SP → GET `api.fabric.microsoft.com/v1/workspaces/<ws>/items` to bootstrap the token → retry ingest. If it works, add a recurring <30d refresh (app timer or scheduled task). See [[reference_it_modifies_sps_and_copyinto_auth]] "control-plane vs data plane" below.

**#1119 STILL OPEN as of 2026-10-06 EOD — Workspace Identity (abfss form) did NOT fix the SP path.** Tried:
add `CREDENTIAL = (IDENTITY = 'Workspace Identity')` to each loader's `COPY INTO WITH (...)` to authorize the
OneLake read via the workspace identity instead of the SP's caller-passthrough token. Provisioned the
workspace identity (App ID `0d9df426-abef-46fd-9601-9178422a0e4c`) + gave IT (not the data SP) Contributor +
waited for propagation; the credentialed loaders then created clean. BUT the **app/SP ingest run still throws
Msg 13840** ("access token couldn't be fetched … unsupported URL"). The earlier SQL-editor run reaching the DQ
gate was a FALSE POSITIVE — it ran as a USER, and user COPY INTO has worked the whole time. **Lesson: you
CANNOT test the SP path in the Fabric SQL editor (user passthrough masks it) — only the awdev app run exercises
the SP.** Leading theory now: with the `abfss://` source form the credential is IGNORED (error says
"unsupported URL"); every MS `Workspace Identity` example uses the `https://onelake…` form. OPEN LEVERS for
next session: (1) **https-form credentialed loaders** (change `abfss://…` → `https://onelake.dfs.fabric.microsoft.com/<ws>/<lh>/Files/…`) then app-test; (2) the **token bootstrap** (NEVER actually run; setting confirmed
on) — `az login`/PowerShell client-creds as the SP → GET `api.fabric.microsoft.com/v1/workspaces/<ws>/items`
→ app-test the ORIGINAL passthrough loaders. Dev loaders currently sit credentialed-abfss
(`sql/scripts/deploy_dev_loaders_workspace_identity.sql`); revert = `deploy_dev_cutover_loaders.sql`.
**FABRIC GOTCHA (confirmed this session):** a `COPY INTO` with a CREDENTIAL clause is validated at **CREATE
PROCEDURE time** (eager, not deferred) — if the credential/identity can't authorize, the CREATE fails, and
since loaders are `DROP IF EXISTS` + `CREATE`, the DROP leaves the proc GONE. Test a new credential/path with
a STANDALONE `COPY INTO` into staging first, never via the DROP+CREATE loader. This is DISTINCT from the
Managed Identity we ruled out (`Msg 13838`); 'Workspace Identity' IS supported for OneLake COPY INTO.
PREREQS that bit us (do in THIS order or it fails): (1) provision a Workspace Identity on the workspace
(Workspace settings → Workspace identity; App ID `0d9df426-abef-46fd-9601-9178422a0e4c`), (2) grant THAT
identity (not the data SP) ≥Contributor on the workspace, (3) WAIT ~10-15 min for the role to propagate,
THEN deploy the credentialed loaders. GOTCHA: Fabric validates the `COPY INTO` credential at **CREATE
PROCEDURE time** (eager, not deferred) — so a credentialed loader whose identity lacks access FAILS to
create, and since the proc is `DROP IF EXISTS` + `CREATE`, the DROP leaves the loader GONE. Test a new
credential with a STANDALONE `COPY INTO` (writes to staging, drops nothing), never via the DROP+CREATE
loader, until it loads. Dev loaders: `sql/scripts/deploy_dev_loaders_workspace_identity.sql`; revert (no
credential) `deploy_dev_cutover_loaders.sql`. TODO: port the `CREDENTIAL` clause to the LIVE loaders
(`sql/procedures/usp_Load*Staging.sql`) once dev runs a clean cycle → closes #1119 on prod (same workspace,
same identity + grant already cover live). (user filed their own ticket off `docs/it-request-restore-sp-onelake.md`; awaiting response as of 2026-10-06). Worked **continuously from the 2026-06-22 in-app-ingest build** (B6 — validated end-to-end on dev that June, DQ PASS), straight through the **2026-08-27 prod cutover**, to the **2026-09-12** ingest (last successful app-triggered run); **broke between 09-12 and 09-29** — by 09-29 the app ingest was failing and had to be run manually. ~3 months of standing access ⇒ it was **standing tenant permission**, NOT a one-time/expiring token (there was NO manual token bootstrap — confirmed by record + user recall; the app only ever mints SQL + `storage.azure.com` tokens, never calls the Fabric REST API). Ruled out 2026-10-06: app/page code (3-version container A/B, identical error), storage permission (upload lands clean), workspace role (SP elevated Contributor→Admin, same error, reverted). Cause is a **tenant-level SP/OneLake access change** (the "service principals can use Fabric APIs"/OneLake setting or its security group), not the workspace role (intact) and not our code. **Parked for troubleshooting until #1119 resolves — DO NOT clean up yet:** worktrees `Assessment-Data-premaint` (branch `test/pre-ingest-maint` @ `1ac44b6`) + `Assessment-Data-preauth` (branch `test/pre-auth-cache` @ `9d27031`) and images `assessment-webapp:pre-maint` / `:pre-authcache` (the A/B builds, kept in case IT wants to see it in action). Remove all four + both branches once the ticket closes. The normal containers (awlive :3000, awdev :3001, awdev-impersonation :3002) are back up.

**Rule:** when auth or ingest breaks and our code/deploys didn't change the relevant path, **check the Entra side before deep-diving the code** — login-app redirect URIs, the data SP's tenant OneLake access + group membership. "Nothing changed on our side" usually means something changed on IT's. IT request template: `docs/it-request-restore-sp-onelake.md`.

## Fabric COPY INTO from OneLake = caller-passthrough only (no Managed Identity)
`COPY INTO` reads OneLake as a **different Entra token** than the SQL-connection token (storage audience
vs SQL audience), acquired for the **executing identity**:
- **User** (Fabric SQL editor): works (delegated identity gets the OneLake token).
- **Service principal** (the app): needs the warehouse to broker a OneLake token for the SP — gated by
  the tenant SP/OneLake setting above, separately from workspace RBAC.
- The app's **direct upload** works regardless (it mints the SP's own `storage.azure.com` token via
  `@azure/identity` → ADLS REST — a different path than `COPY INTO`'s brokered token).

**You cannot route `COPY INTO` around the caller via Managed Identity** — Fabric Warehouse rejects it:
`Msg 13838 "...using 'Managed Identity' credential is not supported"` (tested on dev 2026-10-04). Fabric
`COPY INTO` supports EntraID-passthrough (default), SAS, and Storage Account Key — not MI. So an SP that
needs to `COPY INTO` OneLake must have its OneLake token access restored (IT), OR use a SAS credential
(extra secret + rotation; last resort), OR run the ingest as a user. See [[project_webapp_fabric_connection]].

## The ingest run-log (added same session)
`dbo.IngestRunLog` (sql/facts/IngestRunLog.sql) + instrumented `usp_RunFullIngestCycle` now record per
cycle: who (`CallerUPN`), when, **App vs FabricSQL** (`@Source`), and rows loaded per file. `COPY INTO`
has no OneLake-token dependency change here — it's purely logging. Co-teacher skip was removed at the
same time (co-teachers always load); `@SkipCoTeachers` is a deprecated no-op kept only for pre-1.1.0
container compat.
