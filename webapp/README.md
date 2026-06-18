# Assessment Data Platform &mdash; web app

Self-hosted **Next.js (TypeScript)** front end for the Regional Student Assessment Data
Platform. Replaces the Power Apps canvas app to escape per-user premium-connector licensing:
the data connection lives **server-side**, so there is no per-seat license &mdash; just compute.

- **Now:** points at the existing **Fabric Warehouse** (`Assessment_Warehouse`, Canada East)
  via a server-side connection (`src/lib/db.ts`).
- **Later:** the same server layer swaps to Postgres/Supabase (driver + SQL dialect change,
  callers untouched) &mdash; the pinned capacity-review decision.

## Stack

| Layer | Choice |
|---|---|
| Framework | Next.js 15 (App Router), React 19, TypeScript |
| DB driver | `mssql` (Fabric SQL endpoint) |
| Container | OCI multi-stage build, runs under **Podman** (rootless) |
| Auth | MSAL / Entra on-behalf-of (pending IT app registration) |

All of the above are $0 / open-source. Hosting later = compute cost in a Canadian region,
**no per-user licensing**.

## First run

```sh
cp .env.example .env        # set AUTH_MODE=dev + DEV_FAKE_UPN; Fabric/Entra can stay blank
npm install
npm run dev                 # http://localhost:3000
```

The landing page and `GET /api/health` show a readiness check (config presence + region).
Nothing connects to Fabric until a screen actually queries it.

## Container (Podman)

```sh
podman build -t assessment-webapp:dev .
podman run --rm -p 3000:3000 --env-file .env assessment-webapp:dev
# or:
podman compose up --build
```

The `Dockerfile` is standard OCI &mdash; no Docker Desktop required (sidesteps its per-org
licensing at TCRCE's size). The VS Code **Container Tools** extension can drive Podman if you
prefer buttons over the CLI.

## What's stubbed (by design)

- **Auth** &mdash; `AUTH_MODE=dev` returns `DEV_FAKE_UPN` so the app runs before Entra is
  wired. `AUTH_MODE=entra` (MSAL OBO) is **blocked on the Entra app registration from IT**
  (the same critical-path dependency tracked for the SharePoint bridge).
- **DB** &mdash; `src/lib/db.ts` lazily connects; `queryAsUser()` passes the teacher's UPN as
  `@UPN` because the service-principal connection can't satisfy the views' `USERPRINCIPALNAME()`
  filter on its own. No screen queries it yet.

## Key gotchas baked in

- **Surrogate keys are strings** (`src/lib/keys.ts`) &mdash; Fabric BIGINT exceeds JS Number
  precision, same trap as Power Fx. Views already cast to `VARCHAR(20)`.
- **Region** &mdash; `DATA_REGION` is surfaced as an intent assertion; the real guard is
  deploying the container to a Canadian region.

## Next steps

1. `npm install` + first local run to confirm the skeleton builds.
2. Bind the first screen (window/group select) to a secured view via `queryAsUser()`.
3. Wire Entra OBO once the app registration lands.
4. Port the remaining screens from the existing Direction B design.
