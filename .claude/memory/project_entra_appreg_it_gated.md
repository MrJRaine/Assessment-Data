---
name: project_entra_appreg_it_gated
description: User cannot self-register Entra apps in the TCRCE tenant — app registration (and likely admin consent) is IT-gated; confirmed 401 on the App registrations blade 2026-06-18. Critical-path implication for all Entra-dependent work.
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

jeffrey.raine@tcrce.ca does NOT have rights to create Entra app registrations in the TCRCE tenant — the App registrations blade returns "You don't have access" / error 401 (confirmed 2026-06-18). The account is not an Application Developer/Administrator/Cloud App Admin/Global Admin there, and user-consent appears restricted too.

**Why:** Every Entra-dependent step now carries an IT dependency on the critical path — the web-app dev registration (Phase 3b / B2), the delegated Azure SQL / Fabric scope for read/write as the user (B3/B4), and the SharePoint-bridge daemon (`Sites.Selected`, Phase 3a). Because user consent is restricted, IT must both CREATE the app registrations AND grant admin consent for their permissions.

**How to apply:** Never present an Entra-auth step as something the user can just do in the portal — route it through an IT request (`docs/it-request-entra-webapp-dev.md` for 3b, `docs/it-request-entra-bridge.md` for 3a), bundle related needs into one pass (a second round-trip is costly given the July–August dead zone when both teachers and the user are away), and treat IT turnaround as the schedule driver. For mechanical/code testing that can't wait on IT, prove the flow in a separate free/dev Entra tenant (no TCRCE data) and swap the client/tenant IDs when the real registration lands. Related: [[project_licensing_pivot_2026_06]].
