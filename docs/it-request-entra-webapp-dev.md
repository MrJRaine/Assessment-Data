# IT Request — Entra App Registration for the Assessment Web App (dev/pilot)

**Requested by:** jeffrey.raine@tcrce.ca
**Date:** 2026-06-18
**Use only if self-service app registration is blocked** (most of this is user-consentable
and may not need IT — try the self-service steps first; see `docs/implementation-plan.md`
Phase 3b / B2).

## Context

The student assessment platform's entry app is being rebuilt as a self-hosted web app
(Phase 3b fork) so it can authenticate users with Entra ID and read/write the Fabric
Warehouse **server-side** — eliminating the per-user premium-connector cost that blocked the
Power Apps path. This request covers the **identity** piece (sign-in + ID validation).

## What's needed

A **single-tenant** Entra ID **app registration**:

| Setting | Value |
|---|---|
| Name | `Assessment WebApp (dev)` |
| Supported account types | Single tenant (this directory only) |
| Platform | Web |
| Redirect URI (dev) | `http://localhost:3000/api/auth/callback/microsoft-entra-id` |
| Redirect URI (pilot/prod) | TBD — a Canadian-region host URL, added when we deploy |
| Credential | One client secret (or certificate). Held only in the dev `.env` for now; for shared/hosted use, a secret with a rotation schedule. |

### API permissions (Microsoft Graph, **delegated**)

`openid`, `profile`, `email`, `User.Read`

These are **user-consentable — no admin consent required** for sign-in + ID validation.

### Later (separate follow-up, not this request)

To let the signed-in user's token read/write the **Fabric Warehouse** with native row-level
security (Phase 3b / B3-B4), we will additionally need a **delegated** permission to the
Azure SQL / Fabric data resource (e.g. Azure SQL Database `user_impersonation`). The user
(teacher) must also have access to the Fabric workspace/warehouse — which real users already
have via the secured RLS views. We will raise that as a small amendment once B2 is confirmed.

## Least-privilege notes

- **Delegated only** (acts as the signed-in user), **single tenant**, **no admin-consent
  scopes** for B2.
- This is a **different, lighter** registration than the SharePoint-bridge daemon request
  (`docs/it-request-entra-bridge.md`), which needs an *application* permission
  (`Sites.Selected`) + admin consent. If the web-app path (3b) supersedes the bridge (3a),
  the bridge request may no longer be needed — flag before actioning both.
- Initial assignment: the developer account (jeffrey.raine@tcrce.ca) only.
