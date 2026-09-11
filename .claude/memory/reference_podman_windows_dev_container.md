---
name: reference_podman_windows_dev_container
description: How to run the webapp container on a Windows/podman (WSL) machine — publish to 127.0.0.1 explicitly (the default binding empty-replies), awdev vs awlive recipes, and the container-only-machine constraints (no node, no gh).
metadata:
  type: reference
---

Running the `webapp/` container locally on a Windows machine with rootless podman (WSL backend). Verified on a fresh laptop 2026-09-04.

**Publish to IPv4 loopback EXPLICITLY.** Use `-p 127.0.0.1:3000:3000`, NOT the default `-p 3000:3000`. With the default, podman's `wslrelay` forwarder binds **IPv6 `::1` only** and every request **empty-replies** (curl exit 52 / "connection closed unexpectedly") even though the app is healthy *inside* the container. Binding `127.0.0.1` makes `wslrelay` bind IPv4 and it works. Then browse via `http://localhost:PORT` (localhost also resolves to `::1`, but with nothing listening there the browser fails fast and falls back to IPv4).

**Each boot:** `podman machine start` (the VM doesn't auto-start; `podman machine init` only the first time). No compose provider is installed → use plain `podman build` / `podman run`, NOT `podman compose`.

**Recipes** (run from repo root; image listens on 3000 internally):
```
# build (tag with the commit sha)
podman build -t assessment-webapp:dev -t assessment-webapp:$(git rev-parse --short HEAD) webapp
# awdev — synthetic _Dev data, dev auth + impersonation bar, port 3001
podman run -d --name awdev  --env-file webapp/.env.dev  -p 127.0.0.1:3001:3000 --restart unless-stopped assessment-webapp:dev
# awlive — live warehouse (real PII), Entra auth, port 3000
podman run -d --name awlive --env-file webapp/.env      -p 127.0.0.1:3000:3000 --restart unless-stopped assessment-webapp:dev
```
`awdev` = `.env.dev` (`FABRIC_SQL_DATABASE=Assessment_Warehouse_Dev`, `AUTH_MODE=dev`, `ALLOW_DEV_AUTH=true` → no Entra login + dev impersonation bar) — the safe target for meetings/demos ([[feedback_live_pii_boundary]]). `awlive`/`.env` point at the live `Assessment_Warehouse`. Confirm the DB in each `.env*` before running. All `.env*` are gitignored → they travel by thumb drive, not git. Verify health at `/api/health` (shows `authMode`, `fabricConfigured`, region).

**Container-only machine constraints:** a machine set up just to run the container may have **no local `node` and no `gh`**. So: typecheck/lint by running the image build (`next build` runs both — a build that reaches COMMIT passed); `git push` still works via Git Credential Manager (see [[reference_gh_cli_token_via_git]]).
