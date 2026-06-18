# IT Request — Entra ID App Registration for the Assessment Platform Data Bridge

**Requested by:** Jeffrey Raine (jeffrey.raine@tcrce.ca)
**Date:** 2026-06-12
**Priority:** High — this registration gates the assessment-platform pilot timeline.

## What is being requested

One **Entra ID app registration** (single-tenant, daemon/server-side — no redirect URIs,
no user sign-in) to act as the identity for an automated data bridge between the
`Assessment_Warehouse` (Microsoft Fabric, Canada East) and SharePoint lists used by the
teacher assessment-entry app.

1. **Create the app registration** — suggested name: `Assessment-Platform-Bridge`.
2. **API permission:** Microsoft Graph → **Application** permission → **`Sites.Selected`**
   — with tenant-admin consent.
   - `Sites.Selected` is the least-privilege option: the app can access **zero** SharePoint
     sites until an admin explicitly grants it access to specific ones, and it can never
     touch any other site. (We are deliberately NOT requesting `Sites.ReadWrite.All`.)
3. **Grant the app access to one site** (one-time admin action after consent): assign the
   app the **`write`** role on the target site via the Graph site-permissions endpoint.
   Target site URL: **TBD — will be supplied before the grant step** (the dedicated
   site/private channel for assessment entry is being finalized).
4. **Credential:** client secret (or certificate if you prefer — your call), 12-24 month
   expiry, delivered securely. It will be stored in a **Canadian-region** secret store and
   used only by scheduled Fabric jobs in the existing `Regional_Data_Portal` workspace
   (Canada East).

## Why

- The assessment platform's teacher entry app is moving to SharePoint lists so that
  teachers' M365 A3 licenses fully cover it (no premium Power Platform licensing). A
  server-side bridge must sync rosters and submissions between the Fabric warehouse and
  those lists on a schedule; Graph API with an app identity is the only license-free,
  unattended way to do that.
- **Privacy/PIIDPA:** all processing stays inside the TCRCE tenant and Canadian regions —
  Fabric (Canada East) ↔ SharePoint Online (Canadian tenancy). The app identity narrows
  the bridge's reach to exactly one site via `Sites.Selected`.

## Relationship to the May 2026 request

This supersedes/parallels the earlier request for a service principal for OneLake ingest
(2026-05-22). If that registration was partially processed, it can likely be reused —
the requirement here is the Graph `Sites.Selected` application permission + consent +
single-site write grant, regardless of which registration carries it.

## What we need back

1. Application (client) ID + Directory (tenant) ID.
2. The client secret (secure channel) or certificate arrangement.
3. Confirmation that admin consent for `Sites.Selected` is granted.
4. (After we supply the site URL) confirmation of the `write` grant on that site.
