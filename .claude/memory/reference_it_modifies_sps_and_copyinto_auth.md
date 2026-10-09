---
name: reference_it_modifies_sps_and_copyinto_auth
description: "When app sign-in or ingest breaks with 'nothing changed in our code', suspect IT modified the Entra app registrations / service principals or tenant SP settings — check those FIRST. Plus: Fabric COPY INTO from OneLake is caller-passthrough only (no Managed Identity)."
metadata:
  node_type: memory
  type: reference
  originSessionId: 81b06086-0f59-47db-b6fb-84b7a577c17f
  modified: 2026-10-07T15:22:25.018Z
---

**Set 2026-10-04**, after a multi-hour ingest debug.

## IT changes the Entra apps / SPs without notifying us — check that FIRST
Two prod-auth breakages traced to IT modifying the app registrations / service principals / tenant SP
settings with no notice:
- **Local sign-in broke** — the **login app** (`TCRCE Data Web App`, client ID `819f9480-5e65-469e-be27-89ac30381f1f`, tenant `0320ef6f-7349-4acf-b62a-e780da155b7e`) lost its `http://localhost:3000/api/auth/callback/microsoft-entra-id` redirect URI (AADSTS50011). **RECURRED 2026-10-05** (localhost confirmed absent again) → IT request now asks for BOTH `:3000` and `:3001` localhost redirect URIs: `docs/it-request-login-redirect-uris.md`. Callback path = `/api/auth/callback/microsoft-entra-id`; keep the prod URI `https://data.tcrce.ca/...`.
- **In-app ingest broke** — the **data SP** (`StudentDataAssessment`, App ID `c33fb2d3-b64e-4818-aa9b-0ac7515f1710`) can still connect + run SQL + is workspace **Contributor**, but can no longer get a **OneLake token for `COPY INTO`**. **IT ticket #1119**. **UPDATE 2026-10-06 — tenant-setting hypothesis DISPROVEN:** IT confirmed **"Service principals can call Fabric public APIs" = Enabled for the ENTIRE org, no security-group exceptions** (screenshot). So the SP is NOT blocked by that toggle. **RESOLVED 2026-10-07 — the fix is a Workspace Identity CREDENTIAL on the loaders, NOT a control-plane token bootstrap** (that theory was wrong; `az login` was never run). See the RESOLVED paragraph below.

**#1119 — CLOSED 2026-10-09 as "workaround found, root cause NOT fixed; NOT PURSUING further" (user call).**
Ingest was UNBLOCKED 2026-10-07 via a WORKAROUND (Workspace Identity CREDENTIAL); the ROOT CAUSE was never
identified and we are **no longer investigating it** — per [[feedback_fix_vs_workaround]] this is recorded as
a workaround, not a fix. We never identified WHY the SP's OneLake passthrough token broke tenant-side
(~Sept 12) — the SP passthrough is STILL broken (both passthrough tests still fail), and that underlying
question stays open-but-unpursued; reopen only if something ever specifically needs SP passthrough restored. We routed around it: add
`CREDENTIAL = (IDENTITY = 'Workspace Identity')` to each loader's `COPY INTO WITH (...)` so the OneLake read
authorizes as the WORKSPACE identity, not the SP's caller-passthrough token. The URL scheme (abfss vs https)
is IRRELEVANT. This is a work-around, not a fix — if the real passthrough breakage ever needs resolving,
this ticket's underlying question is still open. Proven by a full 2×2 on dev via the APP (SP) run — the ONLY valid test (a Fabric
SQL-editor EXEC runs as a USER, and user passthrough always worked): passthrough+abfss ❌ (the outage) ·
passthrough+https ❌ "Access token couldn't be fetched" · **WI+abfss ✅** · WI+https ✅. The 2026-10-06
WI+abfss failure (Msg 13840 "unsupported URL") was a **FALSE NEGATIVE** — the WI's Contributor grant had not
PROPAGATED yet (granted late that day); re-tested 2026-10-07 after **overnight** propagation → clean app
ingest. So Msg 13840 here meant "the WI can't authorize yet", NOT "wrong URL form": do NOT chase the URL
scheme, an https rewrite, or a token bootstrap. **Root cause stands:** the SP's OneLake passthrough is
genuinely broken tenant-side (both passthrough tests still fail); the WI credential routes around it.
**LIVE — DONE 2026-10-07:** the one `CREDENTIAL` line is committed into the 5 abfss procs
`sql/procedures/usp_Load*Staging.sql` (+ a `DROP IF EXISTS` guard); deployed to the live warehouse and a
**live app ingest ran clean over the SP path on data.tcrce.ca** → ingest UNBLOCKED on prod via the workaround
(root cause of the passthrough breakage still undiagnosed). The loader source shipped **as part of the
v1.1.0 release** — PR #34 (`fix/1119-loader-wi-credential`) merged to `main`, back-merged to `dev` (@ `7690244`),
and it is in the `v1.1.0` tag; `main` carries the credential. Dev working form = `deploy_dev_loaders_workspace_identity.sql`
(WI+abfss); revert-to-passthrough = `deploy_dev_cutover_loaders.sql`. (The investigative dead-ends — the
two https-form scripts and the standalone `test_copyinto_https_wi_dev.sql` — were DELETED 2026-10-09 on
#1119 closure; the 2×2 result above records what they proved.)
**FABRIC GOTCHA (confirmed this session):** a `COPY INTO` with a CREDENTIAL clause is validated at **CREATE
PROCEDURE time** (eager, not deferred) — if the credential/identity can't authorize, the CREATE fails, and
since loaders are `DROP IF EXISTS` + `CREATE`, the DROP leaves the proc GONE. Test a new credential/path with
a STANDALONE `COPY INTO` into staging first, never via the DROP+CREATE loader. This is DISTINCT from the
Managed Identity we ruled out (`Msg 13838`); 'Workspace Identity' IS supported for OneLake COPY INTO.
PREREQS that bit us (do in THIS order or it fails): (1) provision a Workspace Identity on the workspace
(Workspace settings → Workspace identity; App ID `0d9df426-abef-46fd-9601-9178422a0e4c`), (2) grant THAT
identity (not the data SP) ≥Contributor on the workspace, (3) WAIT for the role to propagate — the ~10-15 min
MS quotes was NOT enough here; WI+abfss still failed the same day and only worked after OVERNIGHT propagation,
so do NOT trust an early post-grant failure (that was exactly the 2026-10-06 false negative). THEN deploy the
credentialed loaders. GOTCHA: Fabric validates the `COPY INTO` credential at **CREATE
PROCEDURE time** (eager, not deferred) — so a credentialed loader whose identity lacks access FAILS to
create, and since the proc is `DROP IF EXISTS` + `CREATE`, the DROP leaves the loader GONE. Test a new
credential with a STANDALONE `COPY INTO` (writes to staging, drops nothing), never via the DROP+CREATE
loader, until it loads. Dev loaders: `sql/scripts/deploy_dev_loaders_workspace_identity.sql`; revert (no
credential) `deploy_dev_cutover_loaders.sql`. The `CREDENTIAL` clause is **already ported to the LIVE loaders**
(`sql/procedures/usp_Load*Staging.sql`) and ran a clean live app ingest 2026-10-07 — #1119 is closed on prod.
The loader source is **on `main` as part of the v1.1.0 release** (PR #34
`fix/1119-loader-wi-credential`, in the `v1.1.0` tag), back-merged to `dev` — no git step outstanding. Worked **continuously from the 2026-06-22 in-app-ingest build** (B6 — validated end-to-end on dev that June, DQ PASS), straight through the **2026-08-27 prod cutover**, to the **2026-09-12** ingest (last successful app-triggered run); **broke between 09-12 and 09-29** — by 09-29 the app ingest was failing and had to be run manually. ~3 months of standing access ⇒ it was **standing tenant permission**, NOT a one-time/expiring token (there was NO manual token bootstrap — confirmed by record + user recall; the app only ever mints SQL + `storage.azure.com` tokens, never calls the Fabric REST API). Ruled out 2026-10-06: app/page code (3-version container A/B, identical error), storage permission (upload lands clean), workspace role (SP elevated Contributor→Admin, same error, reverted). Cause is a **tenant-level SP/OneLake access change** (the "service principals can use Fabric APIs"/OneLake setting or its security group), not the workspace role (intact) and not our code. **#1119 is now CLOSED (2026-10-09) so the troubleshooting apparatus can be cleaned up when convenient:** worktrees `Assessment-Data-premaint` (branch `test/pre-ingest-maint` @ `1ac44b6`) + `Assessment-Data-preauth` (branch `test/pre-auth-cache` @ `9d27031`) and images `assessment-webapp:pre-maint` / `:pre-authcache` (the A/B builds) — remove all four + both branches (they were kept only for the investigation). The normal containers (awlive :3000, awdev :3001, awdev-impersonation :3002) are up.

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
