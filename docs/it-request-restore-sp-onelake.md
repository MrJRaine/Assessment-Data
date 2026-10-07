# IT request — restore service-principal OneLake access (SCoR Dashboard ingest)

## Summary
The in-app PowerSchool ingest on `data.tcrce.ca` is failing at the warehouse load step. The data
service principal can still **connect to the warehouse, run SQL, and is a workspace Contributor**, but
it can **no longer obtain a OneLake storage token for `COPY INTO`**. The **last successful app-triggered
ingest was 2026-09-12**; by **2026-09-29** the app ingest was already failing and had to be run manually,
so the break occurred **sometime between Sept 12 and Sept 29, 2026**. It worked at the 2026-08-27
production cutover with the same role. The most likely cause is a
**tenant-level change to service-principal / OneLake access** (the setting or its backing security
group). Only a Fabric tenant admin can confirm and restore this.

## The service principal
- **Name:** `StudentDataAssessment` (the data SP — reads the warehouse, uploads to and `COPY INTO`s from OneLake)
- **App (client) ID:** `c33fb2d3-b64e-4818-aa9b-0ac7515f1710`
- **Object ID:** `479b9fde-5f89-4d52-b1d9-e03b4ce62594`
- **Workspace:** `Regional_Data_Portal` — the SP is still listed as **Contributor** (verified in Manage access).

## Re-confirmed 2026-10-06 (and ruled out the workspace role)
Re-tested against the **dev** warehouse (`Assessment_Warehouse_Dev`, landing lakehouse `8c5589bd-d04e-4e94-bb2c-482db645afab`): a fresh file upload via the app **landed clean**, and the loader `COPY INTO` **still threw the same token error**. Because it's the same SP and workspace, this is not environment-specific — restoring the SP at the tenant fixes **both dev and live** at once.

To pre-empt the obvious first guess, we **elevated the SP from Contributor → Admin** on the workspace and re-ran: **identical token error**. So the **workspace role is not the cause** (and the SP has been returned to Contributor). This matches the symptom — the error is a failure to *mint* a OneLake token, which is gated at the **tenant** level, not by the workspace role.

## Exact symptom
When the ingest runs **as the SP** (the app path), the loader `COPY INTO` throws:

> Access token couldn't be fetched for storage path
> `https://onelake.dfs.fabric.microsoft.com/…/Files/imports/students/Students*`
> as it's an unsupported URL or cause of a transient error.

The **identical `COPY INTO` succeeds when run by a user** (a workspace Admin/Contributor) in the Fabric
SQL editor. So:
- SP → warehouse SQL connection: **works** (reports/screens render).
- SP → OneLake direct upload (ADLS REST, `storage.azure.com` token): **works** (files land).
- SP → `COPY INTO` reading OneLake (Fabric brokers a OneLake token for the SP): **fails.**

That last one is a distinct permission from the workspace Contributor role, which is why the role looks
healthy but the load fails.

## What we need
1. **Confirm**: between **2026-09-12** (last successful app-triggered ingest) and **2026-09-29**
   (confirmed failing — ingest run manually), was there a change to the tenant setting **"Service principals can
   use Fabric APIs"** (or any OneLake / "service principals can access data" setting) — including the
   **security group** that backs it — and is `StudentDataAssessment` (`c33fb2d3…`) still in scope?
2. **Restore** the SP's ability to obtain a OneLake token (re-add it to the allowed group / re-enable
   the setting) so `COPY INTO` works for the SP again.
3. **Going forward**: please notify the project lead before modifying these app registrations / SPs or
   their tenant settings — production auth (sign-in and ingest) breaks silently otherwise. This is the
   second incident traced to an un-notified SP/app change (the other: the login app's `localhost:3000`
   redirect URI was removed, breaking local testing).

## Why we can't just work around it in code
We tested routing `COPY INTO` through the **workspace Managed Identity** instead of the SP. **Fabric
Warehouse does not support a Managed Identity credential for OneLake** (`Msg 13838: "...using 'Managed
Identity' credential is not supported"`). `COPY INTO` from OneLake authenticates as the **caller**
(EntraID passthrough) — so the SP's own OneLake access is required. There is no app-side fix; this must
be restored at the tenant.

## How to confirm it's fixed
Re-run the in-app ingest (or `EXEC dbo.usp_RunFullIngestCycle` under an SP-authenticated connection):
`COPY INTO` loads the staging rows instead of throwing the token error.

## Interim
Until restored, ingest is run manually in the Fabric SQL editor by a workspace Admin (upload the files
via the app, then `EXEC dbo.usp_RunFullIngestCycle`), which authenticates as the user and works.
