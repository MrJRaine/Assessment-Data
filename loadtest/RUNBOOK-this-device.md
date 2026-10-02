# Load-test runbook - SINGLE DEVICE (this Windows box)

Adaptation of [`RUNBOOK.md`](RUNBOOK.md) for running the whole test from **one machine**: the app
in podman on loopback, and Locust natively on the same box. No staging VM, no Proxmox, no k3s/Pi
cluster. Everything talks over `http://127.0.0.1:3001`.

Image: `localhost/assessment-webapp:0.7.0-loadtest` (built from the `loadtest` worktree).
> Note: the canonical `RUNBOOK.md`/`LOADTEST_HANDBACK.md` say `0.7.1-loadtest`, but the branch's
> `package.json` is `0.7.0` - so the real tag is `0.7.0-loadtest`. Same build, one-patch doc drift.

---

## Read this first - single-device caveats (they change how you read results)

- **The load generator competes with the app for this box's CPU.** Locust + the Next server run on
  the same cores, so "Node/VM CPU high" readings are muddied - you can't cleanly separate
  *app-is-the-wall* from *generator-starved-the-box*. Keep user counts modest, and watch that Locust
  itself isn't pinning the CPU (its own console shows generator CPU warnings). This box sizes the
  **pool ceiling** well; it does **not** substitute for the staging-VM sizing run.
- **Fabric is still remote and shared.** The dev warehouse (`..._Dev`) sits on the same **F8**
  capacity as everyone else's dev work - a heavy run consumes CU and can affect other dev users.
  Run outside busy hours; watch the Fabric Capacity Metrics App.
- **Loopback only.** `127.0.0.1:3001` - nothing is exposed on the LAN or internet, so the firewall/
  VLAN steps in the main runbook don't apply. Port 3000 (awlive) and 3001 (awdev) conventions still
  hold - **stop awdev first** so 3001 is free (or run the loadtest container on another port).

---

## 0. Pre-flight (this device)

- [x] Load-test image built: `assessment-webapp:0.7.0-loadtest`.
- [x] `.env.loadtest` scaffolded at `webapp/.env.loadtest` (AUTH_SECRET + LOADTEST_KEY generated).
- [ ] **Finish `webapp/.env.loadtest`** (two gaps left on purpose):
      1. Copy the **5 warehouse/SP lines** from `C:\git-repos\Assessment-Data\webapp\.env.dev`
         (`FABRIC_SQL_SERVER`, `FABRIC_SQL_DATABASE` [must end `_Dev`], `ENTRA_TENANT_ID`,
         `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`) into the marked block.
      2. Set `LOADTEST_USERS` from the identities query (next item).
- [ ] **Identities**: run [`../sql/scripts/list_loadtest_identities.sql`](../sql/scripts/list_loadtest_identities.sql)
      on **dev** (you run all SQL), pick ~2 analysts / 2 admins / 16 teachers, and paste the
      `upn:role` list into `LOADTEST_USERS`.
- [ ] **Representative dev data**: the dev warehouse must hold realistic-volume synthetic data - tiny
      dev data makes per-request cost unrealistic. Reseed/scale if it's thin.
- [ ] **Python + Locust** installed on this box (`locust --version` works). See step 4.
- [ ] Port **3001** free: `podman rm -f awdev` (or stop it) before starting `awlt`.

## 1. Start the app (load-test build)

```powershell
podman rm -f awdev 2>$null   # free 3001
podman run -d --name awlt --restart unless-stopped `
  -p 127.0.0.1:3001:3000 `
  --env-file "C:\git-repos\Assessment-Data-loadtest\webapp\.env.loadtest" `
  localhost/assessment-webapp:0.7.0-loadtest
```

If the guard rejects the config the container **exits** - `podman logs awlt` prints **REFUSING TO
START** and the reason (non-`_Dev` warehouse / live host / `AUTH_MODE`!=dev / missing `LOADTEST_KEY`).

## 2. Verify guard + gate (safety net)

```powershell
podman logs awlt | Select-String "BYPASS IS ACTIVE"                         # banner + "_Dev"
curl.exe -s http://127.0.0.1:3001/api/health                                # {"status":"ok"}
curl.exe -s -o NUL -w "%{http_code}`n" http://127.0.0.1:3001/reports        # 401 (no key)
# keyed seed for one user (replace <upn> with one from LOADTEST_USERS):
curl.exe -s -H "x-loadtest-key: morC4ZjsWTLwd0xVJ/AGDf9pMFsiwx/HgdzRS4r2Zz0=" `
             -H "x-loadtest-user: <upn>" http://127.0.0.1:3001/api/loadtest/seed
```
(The `LOADTEST_KEY` above is the one generated into `.env.loadtest`.)

## 3. Baseline (idle)

```powershell
curl.exe -s -H "x-loadtest-key: morC4ZjsWTLwd0xVJ/AGDf9pMFsiwx/HgdzRS4r2Zz0=" http://127.0.0.1:3001/api/debug/pool
```
Expect zeros (`borrowed:0, pending:0`). Note Task Manager idle CPU for this box.

## 4. Install the load generator (one-time)

```powershell
winget install --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements
# new shell (PATH refresh), then:
python -m pip install --upgrade pip
python -m pip install locust
locust --version
```

## 5. Run - step load + pool sweep

Set the key + users once per shell (PowerShell):
```powershell
$env:LOADTEST_KEY = "morC4ZjsWTLwd0xVJ/AGDf9pMFsiwx/HgdzRS4r2Zz0="
$env:LOADTEST_USERS = "<paste the same list as in .env.loadtest>"
cd "C:\git-repos\Assessment-Data-loadtest\loadtest"
```

Web UI (watch live at http://localhost:8089):
```powershell
locust -f locustfile.py --host http://127.0.0.1:3001
```
Headless step load (hold each ~3-5 min; step the knee):
```powershell
locust -f locustfile.py --host http://127.0.0.1:3001 --headless -u 25 -r 5 -t 5m
#                                                              -u 50, 100, 150 ...
```
**Pool sweep:** at the knee, restart `awlt` with a higher ceiling and re-run:
```powershell
podman rm -f awlt
podman run -d --name awlt -p 127.0.0.1:3001:3000 `
  --env-file "C:\git-repos\Assessment-Data-loadtest\webapp\.env.loadtest" `
  -e FABRIC_POOL_MAX=40 localhost/assessment-webapp:0.7.0-loadtest   # then 60
```

## 6. Watch the pool during a run

`watch_pool.sh` is bash - run it from **Git Bash**, or use this PowerShell poll:
```powershell
while ($true) {
  curl.exe -s -H "x-loadtest-key: morC4ZjsWTLwd0xVJ/AGDf9pMFsiwx/HgdzRS4r2Zz0=" http://127.0.0.1:3001/api/debug/pool
  "`n"; Start-Sleep 3
}
```
Reading it (same as the main runbook):
- `pending > 0` while `borrowed == max` -> **pool is the wall** -> raise `FABRIC_POOL_MAX`, re-run.
- `eventLoop.p99Ms` climbing with this box's CPU high -> **Node/box is the wall** (muddied here - see caveats).
- Neither moves but latency climbs, and Fabric CU throttles -> **Fabric F8** is the wall (Capacity Metrics App).

## 7. Teardown

```powershell
# stop Locust (Ctrl+C in its window)
podman stop awlt; podman rm awlt
```
Read-only script - **no data cleanup needed**. Nothing touches live or production.

---

Record per step: users, RPS, p50/p95/p99, error %, pool max/borrowed/pending, eventLoop p99,
this-box CPU/mem, Fabric CU %.
