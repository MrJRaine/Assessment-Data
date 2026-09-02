# Production Image Swap — `aw` container

How to deploy a new web-app image to the production server (`data.tcrce.ca`) by swapping the
running Podman container for a new one. This is the procedure that was used to cut over from
`f4432b6` → `c30095b` on 2026-09-02.

## Environment facts

- **Prod host:** Windows Server; IIS (`W3SVC`) reverse-proxies `https://data.tcrce.ca` → `127.0.0.1:3000`.
- **Container:** name `aw`, **rootless** Podman running inside WSL2 as user **`appuser`** (uid 1001).
  - Every podman command is wrapped: `wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && <cmd>"`.
- **Env / secrets:** non-secret config from `--env-file /mnt/c/temp/.env.live`; three credentials come
  from **podman secrets** via the `*_FILE` convention (the image's `load-secrets.cjs` reads them at boot):
  - `aw_auth_secret` → `AUTH_SECRET_FILE`
  - `aw_login_secret` → `AUTH_ENTRA_CLIENT_SECRET_FILE`
  - `aw_wh_secret` → `ENTRA_CLIENT_SECRET_FILE`
- **Port binding:** `-p 127.0.0.1:3000:3000` (localhost only; IIS fronts it).
- **Restart policy:** `--restart=unless-stopped`.
- **Health endpoint:** `GET /api/health` → `200 {"status":"ok"}`.

## Image naming convention

Each build is tagged with its **short commit SHA** (e.g. `:f4432b6`, `:c30095b`) so prod history is
legible and rollback is unambiguous. The tar carries the generic `:token` tag; we add the SHA tag on
load. Throughout this doc, **`<NEW>`** = the new build's short SHA, **`<PREV>`** = the currently-running one.

> Files are delivered by IT to `C:\temp` on the prod host, e.g. `C:\temp\assessment-webapp-<NEW>.tar`.
> Inside WSL that path is `/mnt/c/temp/assessment-webapp-<NEW>.tar`.

---

## 0. Build & deliver the image (dev side)

On the build machine, from `webapp/`:

```bash
podman build -t assessment-webapp:token .
podman save -o /c/Git-Repos/assessment-webapp-<NEW>.tar assessment-webapp:token
```

Hand `assessment-webapp-<NEW>.tar` to IT to place in `C:\temp` on the prod host.

## 1. Pre-flight (nothing changes yet)

Run in **PowerShell as Administrator** on the prod host:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman secret ls && podman inspect aw --format 'current image: {{.Image}} ({{.ImageName}})'"
```

Confirm: the three secrets (`aw_auth_secret`, `aw_login_secret`, `aw_wh_secret`) exist, and note the
current image — that's your rollback target (`:<PREV>`). Secrets live in Podman's store independent of
the container, so recreating `aw` reuses them; no re-import.

## 2. Load the new image

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman load -i /mnt/c/temp/assessment-webapp-<NEW>.tar && podman images assessment-webapp"
```

Ends with `Loaded image: localhost/assessment-webapp:token`. `skipped: already exists` lines are shared
base layers being reused (normal). Note the new image ID in the listing. **This step is non-disruptive** —
the running container is untouched.

## 3. Tag the new image with its SHA

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman tag localhost/assessment-webapp:token localhost/assessment-webapp:<NEW>"
```

(`podman tag` prints nothing on success.)

## 4. Swap the container  ← brief outage (~seconds of HTTP 502)

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman stop aw && podman rm aw && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 127.0.0.1:3000:3000 localhost/assessment-webapp:<NEW>"
```

Output: `aw` (stopped), `aw` (removed), then a 64-char container ID (new container started).

## 5. Verify

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman ps --format '{{.Names}}  {{.Image}}  {{.Status}}'"
wsl -u appuser curl -i http://127.0.0.1:3000/api/health
```

Expect `aw  localhost/assessment-webapp:<NEW>  Up …` and `HTTP/1.1 200 OK` with `{"status":"ok"}`.
Then open **https://data.tcrce.ca**, sign in with Microsoft Entra, and click into a data screen
(e.g. Students) to confirm real data renders on the new build.

## 6. Update the disaster-recovery runbook

IT's "container missing" relaunch command pins the image by reference. Update its final image argument
to the **new** SHA tag, or a future full relaunch will revert the deploy:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 127.0.0.1:3000:3000 localhost/assessment-webapp:<NEW>"
```

Everything else in the DR runbook (IIS check, `podman start aw`, `/api/health`) is unchanged.

---

## Rollback

The previous image stays on the host, so rollback is a re-run against `:<PREV>`:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman stop aw && podman rm aw && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 127.0.0.1:3000:3000 localhost/assessment-webapp:<PREV>"
```

If `:<PREV>` was pruned, reload it first: `podman load -i /mnt/c/temp/assessment-webapp-<PREV>.tar`.

## Cleanup (optional, once the new build is proven)

Old images accumulate. To remove a superseded one:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman image rm localhost/assessment-webapp:<OLD>"
```

Keep at least the immediately-previous image for rollback.

## Notes

- **The image carries no secrets** — they're always supplied at run time via the env-file + podman
  secrets, so the same tar is safe to move between machines.
- **Reboot recovery is separate** from a deploy: a Windows reboot stops WSL2 and rootless containers.
  Bringing them back (`Start-Service W3SVC`, `podman start aw`) is covered in IT's server-recovery doc,
  not here.
- The `:token` tag always points at the most-recently-loaded image; treat it as transient and deploy /
  roll back by **SHA tag**, never by `:token`.
