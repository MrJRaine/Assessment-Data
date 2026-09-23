---
name: reference_podman_windows_dev_container
description: "How to run the webapp container on a Windows/podman (WSL) machine — publish to 127.0.0.1 explicitly (the default binding empty-replies); THREE containers (awlive :3000 live, awdev :3001 dev, awdev-impersonation :3002 dev+impersonation from the dev-impersonation branch's -imp image); container-only-machine constraints (no node, no gh)."
metadata: 
  node_type: memory
  type: reference
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-22T19:42:46.949Z
---

Running the `webapp/` container locally on a Windows machine with rootless podman (WSL backend). Verified on a fresh laptop 2026-09-04.

**Publish to IPv4 loopback EXPLICITLY.** Use `-p 127.0.0.1:3000:3000`, NOT the default `-p 3000:3000`. With the default, podman's `wslrelay` forwarder binds **IPv6 `::1` only** and every request **empty-replies** (curl exit 52 / "connection closed unexpectedly") even though the app is healthy *inside* the container. Binding `127.0.0.1` makes `wslrelay` bind IPv4 and it works. Then browse via `http://localhost:PORT` (localhost also resolves to `::1`, but with nothing listening there the browser fails fast and falls back to IPv4).

**Each boot:** `podman machine start` (the VM doesn't auto-start; `podman machine init` only the first time). No compose provider is installed → use plain `podman build` / `podman run`, NOT `podman compose`.

**THREE containers as of 2026-09-22** (was two). Impersonation was pulled OFF main/`dev` and now
lives ONLY on the `dev-impersonation` branch, built into a separate `:<ver>-imp` image. So:
- **awlive** — :3000 — clean release image (built from `main`) — `.env` (**live** warehouse, real PII), Entra auth. "awlive = the latest build pointed at live data," not a separate track.
- **awdev** — :3001 — clean release image (built from `dev`) — `.env.dev` (synthetic `_Dev`), Entra auth. NO impersonation (clean image). Safe demo target ([[feedback_live_pii_boundary]]).
- **awdev-impersonation** — :3002 — the `:<ver>-imp` image (built from `dev-impersonation`) — `.env.dev` **with `-e AUTH_MODE=dev`** so it opens already signed-in as `DEV_FAKE_UPN` with the impersonation bar always on (dev auth ⇒ no `:3002` Entra redirect-URI needed). For how-tos / demos / troubleshooting.

`.env.dev` is now `AUTH_MODE=entra` + `ALLOW_IMPERSONATION=true` + `AUTH_URL=http://localhost:3001` (awdev signs in via Entra like live). The impersonation container overrides `AUTH_MODE=dev` at run time.

```
# build clean (from dev or main worktree)
podman build -t assessment-webapp:<ver> webapp
# build impersonation image (from the dev-impersonation worktree)
podman build -t assessment-webapp:<ver>-imp webapp
# forward-slash the absolute --env-file path (bash strips backslashes); swap = stop+rm+run (env-file isn't re-read on restart)
podman run -d --name awlive               --restart unless-stopped -p 127.0.0.1:3000:3000 --env-file 'c:/Git-Repos/Assessment-Data/webapp/.env'     localhost/assessment-webapp:<ver>
podman run -d --name awdev                --restart unless-stopped -p 127.0.0.1:3001:3000 --env-file 'c:/Git-Repos/Assessment-Data/webapp/.env.dev' localhost/assessment-webapp:<ver>
podman run -d --name awdev-impersonation  --restart unless-stopped -p 127.0.0.1:3002:3000 --env-file 'c:/Git-Repos/Assessment-Data/webapp/.env.dev' -e AUTH_MODE=dev localhost/assessment-webapp:<ver>-imp
```
**Per-release upkeep for the `-imp` image:** merge `main`→`dev-impersonation` (in its OWN temp worktree, never by flipping the `dev`/`-prod` worktrees), then re-layer any impersonation the auto-merge silently drops — the 0.6.0 merge dropped `data.ts:getImpersonationTargets`, the `cookies` imports in `auth.ts`+`AppShell`, and `AppShell`'s `DevImpersonationBar` import + a `currentUpn` scope. The image **build catches all of these** — always build-verify before swapping :3002. Confirm the DB in each `.env*` before running; all `.env*` are gitignored (travel by thumb drive). Health at `/api/health`.

**The container is NOT a SQL channel.** It holds service-principal credentials with broad warehouse
access, so `podman exec` + a `mssql`/`ClientSecretCredential` script reaches Fabric directly. I do not
do that — not writes, not reads, not diagnostics, dev or live. See
[[feedback_sql_write_authorization]]: the user runs ALL SQL and reports results. `podman` is for
building, running and inspecting the *app* (logs, `/api/health`, env vars) — nothing that talks to
the warehouse.

**Container-only machine constraints:** a machine set up just to run the container may have **no local `node` and no `gh`**. So: typecheck/lint by running the image build (`next build` runs both — a build that reaches COMMIT passed); `git push` still works via Git Credential Manager (see [[reference_gh_cli_token_via_git]]).
