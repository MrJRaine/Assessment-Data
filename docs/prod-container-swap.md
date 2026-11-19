# Production Image Swap — `aw` container

> **Currently live: `assessment-webapp:1.4.0`** (deployed 2026-11-18; git tag `v1.4.0`).
> This is the version production should be running, and the version the
> [disaster-recovery relaunch command](#5-disaster-recovery--relaunch-the-container) brings back.
> It is updated in the release commit every time a new version goes live — if this line and the
> newest release in [`CHANGELOG.md`](../CHANGELOG.md) disagree, trust neither and check the host
> (step 1's `podman inspect`).
>
> **Previous version (rollback target): `assessment-webapp:1.3.0`** (live 2026-10-27 to 2026-11-18).

How to deploy a new web-app image to the production server (`data.tcrce.ca`) by swapping the
running Podman container for a new one, and how to bring the container back if it stops or goes
missing (section 5). Most recent cutover: `1.3.0` → `1.4.0` on 2026-11-18.

Two things every cutover has to respect, both learned on the `1.0.0` cutover (2026-10-02): some
releases **require live SQL first** (see the prerequisite section below), and the port binding must be
`-p 0.0.0.0:3000:3000` because of how WSL forwards traffic (see the Troubleshooting section).

## Streaming / response-buffering settings (must persist — re-apply on any IIS/host rebuild)

Roster pages stream a loading shell then fill in (Suspense). For that to reach the browser, NOTHING in
the chain may buffer the response. Three settings work together — all three are required:
- **App:** `next.config.ts` `compress: false` (Next's default gzip buffers to compress — the origin
  buffer that broke streaming behind the proxy). Baked into the image as of `0.6.1`.
- **IIS ARR:** `responseBufferLimit = 0` on `system.webServer/proxy` (disable ARR response buffering).
  Set with `appcmd set config -section:system.webServer/proxy /responseBufferLimit:"0" /commit:apphost`.
- **IIS:** dynamic compression **OFF** (`doDynamicCompression:"False"`) — else IIS re-gzips + re-buffers
  the now-uncompressed HTML. `appcmd set config -section:system.webServer/urlCompression /doDynamicCompression:"False" /commit:apphost`.

The two IIS settings live in `applicationHost.config` and survive reboots + container swaps; they only
need re-applying if IIS/ARR is reinstalled or the config is rebuilt.

## Environment facts

- **Prod host:** Windows Server; IIS (`W3SVC`) reverse-proxies `https://data.tcrce.ca` → `127.0.0.1:3000`.
- **Access:** the project lead has **direct Windows Remote Desktop access** to the prod host — copy the tar to `C:\temp` and run the swap yourself; IT is NOT in the deploy loop.
- **Container:** name `aw`, **rootless** Podman running inside WSL2 as user **`appuser`** (uid 1001).
  - Every podman command is wrapped: `wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && <cmd>"`.
- **Env / secrets:** non-secret config from `--env-file /mnt/c/temp/.env.live`; three credentials come
  from **podman secrets** via the `*_FILE` convention (the image's `load-secrets.cjs` reads them at boot):
  - `aw_auth_secret` → `AUTH_SECRET_FILE`
  - `aw_login_secret` → `AUTH_ENTRA_CLIENT_SECRET_FILE`
  - `aw_wh_secret` → `ENTRA_CLIENT_SECRET_FILE`
- **Port binding:** `-p 0.0.0.0:3000:3000` (bind the port on ALL interfaces *inside the WSL VM*).
  **Do NOT use `127.0.0.1` here** — see the WSL networking section below. Still host-only: the VM's
  `eth0` sits on WSL's private NAT network, unreachable from the LAN; IIS (443) remains the only public
  door, and the Windows Firewall blocks inbound 3000.
- **Restart policy:** `--restart=unless-stopped`.
- **Health endpoint:** `GET /api/health` → `200 {"status":"ok"}`.

## Image naming convention

As of `0.3.0`, each build is tagged with its **semver release version** (e.g. `:0.3.0`) — the same
version recorded in [`CHANGELOG.md`](../CHANGELOG.md), `webapp/package.json`, and the `v0.3.0` git tag —
so prod history is legible and rollback is unambiguous. The tar carries the version tag directly
(no more generic `:token` tag, and no retag-on-load step). Throughout this doc, **`<NEW>`** = the new
build's version (e.g. `0.3.0`), **`<PREV>`** = the currently-running one.

> Builds before `0.3.0` were tagged by short commit SHA (`:c30095b`, …); those tars/images stay valid
> for rollback and are still referenced by SHA.

> Copy the tar to `C:\temp` on the prod host over RDP, e.g. `C:\temp\assessment-webapp-<NEW>.tar`.
> Inside WSL that path is `/mnt/c/temp/assessment-webapp-<NEW>.tar`.

---

## 0. Build & deliver the image (dev side)

On the build machine, from `webapp/` (with `webapp/package.json` `version` already bumped to `<NEW>`):

```bash
podman build -t assessment-webapp:<NEW> .
podman save -o /c/Git-Repos/assessment-webapp-<NEW>.tar assessment-webapp:<NEW>
```

Copy `assessment-webapp-<NEW>.tar` to `C:\temp` on the prod host over RDP.

## ⚠ Release SQL prerequisite

Some releases require **warehouse SQL to be deployed to the LIVE `Assessment_Warehouse` first** —
if the new container calls views/TVFs/procs that reference schema the live warehouse doesn't have yet,
it will error on those screens. Check the release's **SQL** section in [`CHANGELOG.md`](../CHANGELOG.md)
and run any listed scripts against live **before** swapping the container.

- **`0.3.0`** requires (in order): `sql/scripts/migrate_DimStudent_add_GroupKey.sql` →
  `sql/procedures/usp_MergeStudent.sql` → `sql/scripts/deploy_groupkey_tvfs_live.sql`. Then run one
  ingest so `GroupKey` is populated for existing students (or the backfill in the migrate script covers
  the current set).
- **`0.6.2`** requires (in order, against live `Assessment_Warehouse`, under maintenance mode): the two
  membership tables `sql/security/SectionRosterMembership.sql` + `sql/security/TeacherRosterMembership.sql`,
  then `sql/procedures/usp_RebuildRosterMembership.sql` + `sql/procedures/usp_RunFullIngestCycle.sql`,
  then `EXEC dbo.usp_RebuildRosterMembership` (verify both tables return > 0), then the four roster TVFs
  `sql/security/tvf_TeacherRoster.sql` / `tvf_TeacherRosterOwn.sql` / `tvf_TeacherRosterWriting.sql` /
  `tvf_TeacherRosterMath.sql`. The tables/proc are inert until the TVFs read them, so they can go in
  before the window; keep the TVF swap + container swap inside it.

## 1. Pre-flight (nothing changes yet)

Run on the prod host **as Administrator** — these `wsl -u appuser bash -c "…"` lines are just calls to
`wsl.exe`, so they run identically in **Command Prompt (cmd)** or PowerShell; use whichever you keep the
runbook in. (Only PowerShell-specific redirects like `Out-File` differ — in cmd redirect with `>`.)

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

Ends with `Loaded image: localhost/assessment-webapp:<NEW>` (the tar carries the version tag, so it lands
ready to run — no retag step). `skipped: already exists` lines are shared base layers being reused
(normal). **This step is non-disruptive** — the running container is untouched.

## 3. Swap the container  ← brief outage (~seconds of HTTP 502)

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman stop aw && podman rm aw && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 0.0.0.0:3000:3000 localhost/assessment-webapp:<NEW>"
```

Output: `aw` (stopped), `aw` (removed), then a 64-char container ID (new container started).

## 4. Verify

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman ps --format '{{.Names}}  {{.Image}}  {{.Status}}'"
wsl -u appuser curl -i http://127.0.0.1:3000/api/health
```

Expect `aw  localhost/assessment-webapp:<NEW>  Up …` and `HTTP/1.1 200 OK` with `{"status":"ok"}`.
Then open **https://data.tcrce.ca**, sign in with Microsoft Entra, and click into a data screen
(e.g. Students) to confirm real data renders on the new build.

## 5. Disaster recovery — relaunch the container

**This section is the disaster-recovery runbook.** There is no separate copy to keep in step: the
commands below carry the real live version, not a placeholder, and are updated with every release.

Use it when the site is down and the `aw` container is the problem. First see what state it is in
(run on the prod host as Administrator):

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman ps -a --format '{{.Names}}  {{.Image}}  {{.Status}}'"
```

**A. `aw` is listed but not `Up` (stopped / exited)** — start it; do not recreate it:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman start aw"
```

If that fails with `Failed to get rootless runtime dir … /run/user/1001`, the host was rebooted or WSL
was shut down — recreate the runtime dir first (see **Troubleshooting** below), then start it.

**B. `aw` is not listed at all (container missing)** — relaunch it on the live version:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 0.0.0.0:3000:3000 localhost/assessment-webapp:1.4.0"
```

If that fails because the image is not on the host (`image not known`), load it from the release tar
first, then run the command above again:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman load -i /mnt/c/temp/assessment-webapp-1.4.0.tar"
```

If the three secrets are missing (`podman secret ls` shows none of `aw_auth_secret`,
`aw_login_secret`, `aw_wh_secret`), stop and contact the project lead — the secrets are not in this
repo and the container cannot start without them.

**Then verify** exactly as in step 4: `podman ps` shows `aw  localhost/assessment-webapp:1.4.0  Up …`,
`/api/health` returns `200 {"status":"ok"}`, and https://data.tcrce.ca loads after sign-in. A 502 from
IIS while the container is healthy is the WSL relay issue in **Troubleshooting**, not the image.

> **Release step (keeps this section true).** When a new version goes live, the release commit changes
> the version everywhere it is written out in this file: the **Currently live** and **Previous
> version** lines and the "Most recent cutover" sentence at the top; in this section the relaunch
> command in **B**, the tar name under it, and the verify line; and the rollback image named in the
> **Rollback** section. (Search the file for both version numbers — `<NEW>` / `<PREV>` placeholders
> elsewhere stay as they are.)
> A relaunch with a stale version would silently put production back on an old build.

---

## Troubleshooting: 502 after the swap (WSL networking — learned the hard way 2026-10-02)

The prod container runs under **rootless Podman inside a WSL2 VM**, and that adds two failure modes that
look like the app is broken but aren't. Both bit us during the 1.0.0 cutover.

**Symptom: IIS shows 502, but the container is healthy.** Diagnose by hitting the backend directly from
the prod host (bypassing IIS), both from Windows and from inside WSL:
```
curl -i http://127.0.0.1:3000/api/health
wsl -u appuser bash -c "curl -i http://127.0.0.1:3000/api/health"
```
- **WSL returns 200, Windows is `curl: (56) Recv failure: Connection was reset`** → the container is fine;
  the **Windows→WSL loopback relay** didn't re-attach after the swap's socket teardown. This is why the
  port binding is `-p 0.0.0.0:3000:3000`, **not** `127.0.0.1`: WSL2 forwards Windows `localhost:3000` to
  the VM's `eth0` interface, so a container that only published on the VM's **loopback** is unreachable
  from Windows (hence IIS 502) even though it answers inside WSL. Publishing on `0.0.0.0` makes the
  container listen on `eth0` too, so the forwarded connection lands. If an old container is still on
  `127.0.0.1`, re-run it with `-p 0.0.0.0:3000:3000` (step 3 command) and Windows-side curl flips to 200.
- Do **NOT** roll back the image for this — rollback is another stop/rm/run through the same relay, same
  result. The image is not the cause.

**`wsl --shutdown` leaves the container unable to start** (`Failed to get rootless runtime dir … /run/user/1001:
no such file or directory`, `mkdir /run/user/1001: permission denied`). The per-user runtime dir is created
by systemd-logind at login — and on this host **systemd isn't starting because `/etc/wsl.conf` is malformed**
(`wsl: Expected ' ' or '\n' in /etc/wsl.conf:1`). Until that's fixed, after any `wsl --shutdown`/reboot
recreate the dir as root, then start as appuser:
```
wsl -u root bash -c "install -d -o appuser -g appuser -m 700 /run/user/1001"
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman start aw"
```
**Proper fix (do when there's time):** repair `/etc/wsl.conf` so systemd runs (then logind recreates
`/run/user/1001` and the loopback relay behaves on boot). `wsl -u root bash -c "cat -A /etc/wsl.conf"` to
see the offending line. `0.0.0.0` publishing is the resilient standard regardless.

**NAT vs mirrored caveat:** `0.0.0.0` is host-only under WSL2's **default NAT** networking (VM `eth0` on a
private, non-LAN-routable network). If this host is ever switched to **mirrored** networking mode,
`0.0.0.0` binds the host's real interfaces — then rely on the Windows Firewall to block inbound 3000.

## Rollback

The previous image stays on the host, so rollback is a re-run against `:<PREV>`:

```powershell
wsl -u appuser bash -c "export XDG_RUNTIME_DIR=/run/user/1001 && podman stop aw && podman rm aw && podman run -d --name aw --restart=unless-stopped --env-file /mnt/c/temp/.env.live --secret aw_auth_secret -e AUTH_SECRET_FILE=/run/secrets/aw_auth_secret --secret aw_login_secret -e AUTH_ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_login_secret --secret aw_wh_secret -e ENTRA_CLIENT_SECRET_FILE=/run/secrets/aw_wh_secret -p 0.0.0.0:3000:3000 localhost/assessment-webapp:<PREV>"
```

If `:<PREV>` was pruned, reload it first: `podman load -i /mnt/c/temp/assessment-webapp-<PREV>.tar`.
`<PREV>` is the **Previous version** named at the top of this file (`1.3.0` while `1.4.0` is live), so
today's rollback image is `localhost/assessment-webapp:1.3.0` and its tar is
`assessment-webapp-1.3.0.tar`. Check the release's notes in [`CHANGELOG.md`](../CHANGELOG.md) before
rolling back: if the release deployed live SQL, the older app may not match the warehouse any more.

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
  Bringing them back is in this file: make sure IIS is running (`Start-Service W3SVC` in an
  Administrator PowerShell), then follow **section 5, case A** to start `aw` — including the
  runtime-dir fix in **Troubleshooting** that this host needs after every reboot or `wsl --shutdown`.
- Deploy and roll back by **version tag** (e.g. `:0.3.0`), which matches the release in `CHANGELOG.md`.
  The legacy `:token` tag is retired as of `0.3.0`; SHA-tagged builds before `0.3.0` remain valid
  rollback references (`:c30095b`, …).
