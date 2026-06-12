---
name: webcontents-no-binary-uploads
description: "Power Automate's 'HTTP With Microsoft Entra ID (preauthorized)' connector base64-encodes all request bodies and is explicitly documented as not supporting binary content uploads. Don't try to use it for OneLake/ADLS Gen2 file writes — pivot to plain HTTP + service principal instead."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ca12bc4b-b536-4921-b462-8270e45bbad6
---

**Don't try to use Power Automate's "HTTP With Microsoft Entra ID (preauthorized)" connector (operationId `InvokeHttp`, connector reference `shared_webcontents`) for binary file uploads to OneLake or any other ADLS Gen2 endpoint.** It fails opaquely (500 InternalServerError with no error body) and there's no diagnostic or workaround at the connector level.

**Why:** Microsoft documents two relevant limitations in [the connector reference](https://learn.microsoft.com/en-us/connectors/webcontents/):

1. *"The connector encodes the request body into base64 encoding, hence it should be used to call backend services which expect the request body in this format. You cannot use this connector to call a backend service that expects the request body in raw binary format."*
2. *"Requests that include binary content (for example, PDF files, images, or Office documents) are not supported and may result in corrupted or unreadable files. This behavior is by design; only text-based payloads are supported."*

OneLake's ADLS Gen2 REST API expects raw binary on PUT/PATCH. The connector base64-encodes whatever you put in the body field. The server receives encoded bytes with a Content-Type header it doesn't expect, can't parse cleanly, and returns 500 with no detail. There's no header or option to disable the encoding.

**How to apply:**

- For Power Automate flows that need to upload files to OneLake (or any ADLS Gen2 endpoint that takes raw binary), use the **plain HTTP** connector with **Active Directory OAuth** authentication backed by a **service principal** (Client ID + Secret from an Entra app registration with workspace Contributor on the target Fabric workspace).
- Per-user delegated identity for OneLake writes via Power Automate is NOT achievable as of 2026 — there's no connector that combines delegated user auth with raw binary upload. If per-user file-write identity is critical, either accept the loss (compensate via UI/SQL/share-scope gates) OR build a custom connector OR use SharePoint as an intermediary with a separate sync mechanism.
- Microsoft's own documentation says: *"If your scenario requires something more advanced, please use the 'HTTP' connector or create a custom connector."*

**Why we burned time on this 2026-05-22:** the initial design called for in-app file upload from Power Apps → Power Automate → OneLake, with per-user delegated auth as the workspace-permission gating model. We iterated through three connector options (plain HTTP with AD OAuth which required app credentials; HTTP With Microsoft Entra ID regular which hit AADSTS65002; preauthorized which gave the opaque 500s) before finding the documented limitation. **Future me**: if a connector is returning opaque 500s on binary uploads, check Microsoft's connector docs for an "only text-based payloads supported" disclaimer BEFORE attempting more diagnostic loops.

**Architectural consequence:** the project pivoted to a different upload UX entirely (SharePoint private channel library → Power Automate file-arrival trigger → service-principal write to OneLake). The in-app file picker on scrIngest was abandoned. See `project_assessment_platform` Session 2026-05-22 section for the full architectural decision.

## Related

- [[powerapps-write-pattern]] — Power Apps writes to Fabric Warehouse via wrapper stored procs. Different layer of the same overall write story.
- [[powerapps-data-source-refresh]] — companion lesson; both are about cached/stale connector behavior surprising us.
