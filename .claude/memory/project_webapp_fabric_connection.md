---
name: project_webapp_fabric_connection
description: "How the Phase 3b web app connects to Fabric Warehouse from Node — the tedious-18-vs-19 root cause, the @azure/identity token pattern, and the Next standalone packaging gotcha. Proven 2026-06-19."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

The self-hosted Next.js web app (Phase 3b, `webapp/`) reads Fabric Warehouse `Assessment_Warehouse` server-side as the `StudentDataAssessment` service principal. Connection PROVEN end-to-end in the container 2026-06-19 (`/api/dbcheck` → `{ok:true, connected_as:"StudentDataAssessment"}`). Three non-obvious things had to be true at once:

1. **tedious 19, not 18.** `tedious` 18 cannot complete Fabric's TDS login — it dies right after Login7 with `ConnectionError: Connection lost - socket hang up` (`ESOCKET`). `tedious` 19 fixed this (tediousjs/tedious PR #1668). The driver version is chosen transitively by `mssql`: **`mssql@^11` pins `tedious@^18` (BROKEN); `mssql@^12` uses `tedious@^19` (WORKS).** So the app depends on `mssql@^12`. This is the real answer to the whole "tedious can't connect to Fabric" claim (e.g. the r/MicrosoftFabric thread) — it's version-specific, not a permanent incompatibility.

2. **Mint the token ourselves; don't let tedious do SP auth.** tedious's built-in `azure-active-directory-service-principal-secret` mode mints a token Fabric rejects (same socket-hang-up symptom, which masquerades as #1). Instead: `@azure/identity` `ClientSecretCredential(tenantId, clientId, clientSecret).getToken('https://database.windows.net/.default')`, then pass it to mssql as `authentication: { type: 'azure-active-directory-access-token', options: { token } }`. `@azure/identity` is a standard library (just calls login.microsoftonline.com) — $0, no premium connector. See [[project_powerapps_write_pattern]] for the parallel Power Apps-era write path.

3. **Next.js `output: 'standalone'` does not trace `tedious`.** `mssql` loads `tedious` via a *dynamic* require, which the standalone file-tracer can't follow, so tedious is omitted from `.next/standalone` and the connection fails. Fix: list `['mssql','tedious','@azure/identity']` in `serverExternalPackages` (keep them out of the webpack bundle — the bundled tedious is broken too) AND copy a real `node_modules` into the runner image (Dockerfile `proddeps` stage, overlaid by the standalone server). Regenerate `package-lock.json` with a REAL `npm install`, never `npm install --package-lock-only` (the lock-only mode mis-flags tedious as `dev`, so `--omit=dev` then drops it).

Dead end explored first: ODBC Driver 18 + `msnodesqlv8` (suggested by the Reddit thread). It builds fine but **segfaults (exit 139) on Linux the moment the driver does AAD ServicePrincipal auth** — a libcurl/OpenSSL conflict with Node's embedded OpenSSL. msnodesqlv8 has no access-token escape hatch. Abandoned for the pure-JS path above; image stayed Alpine (no native toolchain needed).

Code lives in `webapp/src/lib/db.ts` (lazy mssql pool, `getCredential()`, `queryAsUser(upn, ...)` passing `@UPN` for the secured views since the SP connection's `CURRENT_USER` is the app, not the teacher). Long-term this whole dialect retires under the planned Postgres/Supabase move ([[project_licensing_pivot_2026_06]]). Production still needs the IT-gated app registration ([[project_entra_appreg_it_gated]]); B3 used the shared dev SP.
