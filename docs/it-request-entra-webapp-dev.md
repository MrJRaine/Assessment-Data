# IT Request — Entra App Registration for the Assessment Web App (dev/pilot)

**Requested by:** jeffrey.raine@tcrce.ca
**Date:** 2026-06-18
**Status:** Self-service registration **confirmed blocked** — the App registrations blade
returns "You don't have access" (error 401) for this account. IT action required.

## Context

The student assessment platform's data-entry app is being rebuilt as a self-hosted web app
so it can authenticate staff with Entra ID and read/write the Fabric Warehouse
**server-side** — which removes the per-user premium-connector licence cost that blocked the
Power Apps approach. This request sets up the app's identity and its data access in one pass.

Please action **Part 1** (required to unblock testing) and, ideally in the same pass,
**Part 2** (data access) to avoid a second request.

---

## Part 1 — App registration + sign-in (required)

A **single-tenant** Entra ID **app registration**:

| Setting | Value |
|---|---|
| Name | `Assessment WebApp (dev)` |
| Supported account types | Single tenant (this directory only) |
| Platform | Web |
| Redirect URI (dev) | `http://localhost:3000/api/auth/callback/microsoft-entra-id` |
| Redirect URI (pilot/prod) | TBD — a Canadian-region host URL, to be added when we deploy |
| Credential | One **client secret** (12-month is fine). Please share the secret **Value** with me securely (not by email) — see note below. |

**API permissions — Microsoft Graph, delegated:** `openid`, `profile`, `email`, `User.Read`

## Part 2 — Fabric Warehouse data access (please include)

So the signed-in user's token can query the Fabric Warehouse (`Assessment_Warehouse`,
Canada East) with row-level security intact:

- **API permission — Azure SQL Database, delegated:** `user_impersonation`
  (APIs my organization uses → *Azure SQL Database* → Delegated → `user_impersonation`).
  This lets the web app obtain a SQL-resource token on the user's behalf.
- **Confirm** the developer account (jeffrey.raine@tcrce.ca) has at least read access to the
  Fabric workspace / warehouse SQL endpoint (real teachers already do via the secured views;
  the dev account needs it to test).

## Admin consent (required)

Because user consent appears to be restricted in this tenant, please **grant admin consent**
for the app's delegated permissions above, so sign-in doesn't prompt each user for approval.

## Secret handoff

The client secret is a credential — please deliver the **Value** via a secure channel
(Teams private message, a secrets vault, or in person), **not** plain email. It will be
stored only in a local `.env` (never committed) for dev, and in a Canadian-region secret
store when the app is hosted.

## Least-privilege notes

- **Delegated only** (the app acts strictly as the signed-in user), **single tenant**.
- Initial use: the developer account only (jeffrey.raine@tcrce.ca).
- This is a **different, lighter** registration than the SharePoint-bridge daemon request
  (`docs/it-request-entra-bridge.md`), which needs an *application* permission
  (`Sites.Selected`) + admin consent. **The web-app path (Phase 3b) is likely to supersede
  the bridge (Phase 3a) — please check with the requester before actioning both**, to avoid
  standing up an app identity we won't use.
