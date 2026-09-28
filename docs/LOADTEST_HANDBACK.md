# Load-test build: handback (app side → Locust/k3s side)

Answers to the "what to hand back" list in `LOADTEST_HANDOFF.md`. The load-test build lives on the
**`loadtest`** branch (cut from `dev-impersonation`), image tag **`localhost/assessment-webapp:0.7.1-loadtest`**.
**Never merged to `main`.**

## Bypass details

- **Master switch:** `LOADTEST_AUTH_BYPASS=true`. Off ⇒ normal Entra sign-in; the whole mechanism is inert.
- **Headers (every request to a protected route):**
  - `X-Loadtest-Key: <LOADTEST_KEY>` — required. Missing/wrong ⇒ **401**. (Store the key as a k8s Secret; it is NOT in the repo.)
  - `X-Loadtest-User: <upn>` — selects the identity. Must be on the `LOADTEST_USERS` allow-list, else the request falls back to `DEV_FAKE_UPN`. Real RLS applies to whichever UPN resolves — no superuser.
- **No Microsoft traffic** when the switch is on: the app never calls Graph, and dev-mode identity means no Entra redirect/token/JWKS. Verified: unkeyed request → 401 (middleware gate), banner logged at boot, landing/health 200.
- **Fail-closed:** the container **refuses to boot** (instrumentation guard throws) if `LOADTEST_AUTH_BYPASS=true` and any of: `AUTH_URL` contains `data.tcrce.ca`, `FABRIC_SQL_DATABASE` is not a `*_Dev` warehouse, `AUTH_MODE`≠`dev`/`ALLOW_DEV_AUTH`≠`true`, or `LOADTEST_KEY` unset. Proven by `scripts/loadtest_guard_check.mjs` and a live boot test.
- **Advisory CIDR:** `LOADTEST_ALLOWED_CIDRS` (e.g. `10.0.0.0/24`). Because the path is **direct (no proxy)** and Next 15 dropped `NextRequest.ip`, the app usually can't see the peer IP, so this is best-effort — **the VLAN firewall is the real perimeter; the key is the app gate.**

## Staging address

- **Direct to the container over HTTP** — `http://<staging-ip>:3001` — **not** through IIS/the provincial CDN (avoids DDoS flagging; the container speaks HTTP in prod too, behind IIS TLS). **Host port 3001** (mapped to the container's 3000) to stay clear of the live deploy's 3000; binds `0.0.0.0:3001` so the Pi VLAN can reach it.
- **TBD tomorrow:** the staging server IP. Locust `host` = `http://<ip>:3001`; pin the IP via `hostAliases` only if you address by name. **Open port 3001 in the VLAN firewall** (not just 443) — HTTPS/TLS/host-checks are moot on this path.

## Identities (`LOADTEST_USERS`)

An env allow-list, comma/space separated, of synthetic dev UPNs. Target mix: **2 regional analysts, 2 admins/principals, 16 teachers of varying class loads**. Pull the actual UPNs from the **dev warehouse** with
[`sql/scripts/list_loadtest_identities.sql`](../sql/scripts/list_loadtest_identities.sql) (read-only; you run it), then set e.g. `LOADTEST_USERS=analyst1@…,admin1@…,teacherA@…,…`. Widest scope = heaviest queries, so keep the analysts/admins in the mix.

## Teacher session (GET route map; RSC pages that SSR the Fabric reads)

| # | Method | Path | Fabric read | Rel. freq. | Notes |
|---|---|---|---|---|---|
| 1 | GET | `/` | none/light | on entry | public landing |
| 2 | GET | `/enter` | `tvf_UserAssessmentWindows` | high | window cards |
| 3 | GET | `/enter/cycle/{cycleGroupId}/{subject}` | `tvf_TeacherGroups` | high | group picker |
| 4 | GET | `/enter/cycle/{cycleGroupId}/{subject}/{groupKey}` | roster TVF (heavy) | high | the roster grid — a load-bearing read |
| 5 | GET | `/reports` | `tvf_StudentCohort` | med | cohort table |
| 6 | GET | `/reports/{studentKey}` | `tvf_StudentAssessmentHistory` | med | drill-down |
| 7 | GET | `/programming` | programming TVFs | low | |

`{subject}` ∈ `reading|writing|math`. Browsers also auto-fetch `/_next/static/*` per page (see Static assets).

## Admin / analyst session (superset — wider RLS = heavier)

Same as teacher, plus: `/reports/math` → `/reports/math/{groupKey}`, `/reports/rwm` → `/reports/rwm/{studentKey}`, `/cycles`, `/admin/staff-access`, `/ingest` (don't drive ingest under load). An analyst's group/cohort reads span many schools, so routes 2–6 cost far more for them — weight a few analyst/admin virtual users heavily to stress the pool.

## Writes

Assessment saves (roster entry, programming edits, cycle/staff-access changes) are **Next Server Actions** — POSTs to the same route path carrying a `Next-Action` header + an RSC payload, not a plain JSON body. They're **awkward to script** and they mutate the dev warehouse. **Recommendation: read-only first pass** (the reads are the pool/serving bottleneck anyway). If you add writes: dev warehouse only, and reset afterward via the full-reset truncate flow. I can hand over exact action payloads for a specific save route if you decide to include writes.

## Static assets

Served **by the app container** (`next start` standalone serves `/_next/static/*`, immutable-cached). No CDN/proxy on the direct path. Including them makes the mix realistic (extra cheap cached GETs); excluding them isolates the SSR/Fabric cost. Your call — they won't move the bottleneck.

## Health check

`GET /api/health` → `200 {"status":"ok"}` (public, no key). Also `GET /api/status`. Use `/api/health` for the pre-test sanity gate.

## Deployment (staging) — env var NAMES only

Run the `0.7.1-loadtest` image with, at minimum:

- **Warehouse (dev):** `FABRIC_SQL_SERVER`, `FABRIC_SQL_DATABASE` (must end `_Dev`), `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET` (the data SP — needed to READ the dev warehouse; a dev credential, not production), `FABRIC_POOL_MAX` (the sweep knob).
- **Dev auth:** `AUTH_MODE=dev`, `ALLOW_DEV_AUTH=true`, `DEV_FAKE_UPN` (fallback identity), `AUTH_SECRET`, `AUTH_URL=http://<staging-ip>:<port>`, `AUTH_TRUST_HOST=true`.
- **Load test:** `LOADTEST_AUTH_BYPASS=true`, `LOADTEST_KEY` (secret), `LOADTEST_USERS` (allow-list), `LOADTEST_ALLOWED_CIDRS` (optional).

Bind host **port 3001** to the LAN interface (`-p 0.0.0.0:3001:3000`) — off the live deploy's 3000. Sweep the pool between runs with `FABRIC_POOL_MAX` (e.g. 20 → 40 → 60). Pre-test: `curl http://<ip>:3001/api/health` → `200`.
