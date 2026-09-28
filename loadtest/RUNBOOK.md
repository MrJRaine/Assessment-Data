# Load-test runbook — SCoR Dashboard

End-to-end: everything that must be in place, how to configure it, how to run, watch, interpret, and
tear down. Goal: size the staging VM and find the connection-pool ceiling **without touching production**.

Companion docs: [`README.md`](README.md) (Locust usage), [`../docs/LOADTEST_HANDBACK.md`](../docs/LOADTEST_HANDBACK.md)
(app contract), [`../LOADTEST_BRANCH.md`](../LOADTEST_BRANCH.md) (never-merge). App build = `loadtest` branch,
image `assessment-webapp:0.7.1-loadtest`.

---

## 0. Pre-flight checklist (must all be true before you start)

**App / server**
- [ ] Staging VM (Proxmox) reachable on the LAN/VLAN; `podman` installed.
- [ ] Load-test image on the box: `assessment-webapp-0.7.1-loadtest.tar` copied over and `podman load`ed.
- [ ] **Dev** Fabric warehouse (`Assessment_Warehouse_Dev`) reachable from the VM, and seeded with
      **representative-volume synthetic data** (tiny dev data ⇒ unrealistic per-request cost — reseed/scale first).
- [ ] Host port **3001** free (only **3000** is IIS-reverse-proxied to the internet; 3001 is not).
- [ ] Firewall: VLAN → `staging:3001` **allowed**; `3001` **blocked from the internet**.

**Secrets / config (3 to supply)**
- [ ] `AUTH_SECRET` — `openssl rand -base64 32` (any value; NextAuth init).
- [ ] `ENTRA_CLIENT_SECRET` — the **dev** data-SP secret (reads the dev warehouse; a dev credential).
- [ ] `LOADTEST_KEY` — the shared `X-Loadtest-Key` (same value app-side and cluster-side).

**Identities**
- [ ] Ran [`../sql/scripts/list_loadtest_identities.sql`](../sql/scripts/list_loadtest_identities.sql) on **dev** and chose
      ~**2 regional analysts, 2 admins, 16 teachers** (varied class loads) → the `LOADTEST_USERS` list.

**Load generator**
- [ ] 4-Pi k3s cluster up; `loadtest` namespace; Locust master+workers deployable; pods can reach `staging:3001`.

**Monitoring**
- [ ] Access to the **Fabric Capacity Metrics App** (to rule Fabric F8 in/out).
- [ ] Proxmox per-VM **CPU/mem/net** graphs open for the staging VM.

---

## 1. Prepare identities → `LOADTEST_USERS`

Run the identities query on dev; copy chosen emails into a comma-separated `upn:role` string
(`role` ∈ `teacher|admin|analyst`), e.g.:

```
LOADTEST_USERS='t1@tcrce.ca:teacher,t2@tcrce.ca:teacher,...(16)...,adm1@tcrce.ca:admin,adm2@tcrce.ca:admin,an1@tcrce.ca:analyst,an2@tcrce.ca:analyst'
```

The population mirrors this list (round-robin), so put the real mix in it.

## 2. Deploy the app load-test build (staging VM)

1. Fill `webapp/.env.loadtest` (already carries the dev-warehouse config): set the 3 blanks
   (`AUTH_SECRET`, `ENTRA_CLIENT_SECRET`, `LOADTEST_KEY`), `AUTH_URL=http://<lan-ip>:3001`, and `LOADTEST_USERS`.
2. Load + run (pin the publish to the **LAN interface** so 3001 isn't on any public NIC):

```bash
podman load -i assessment-webapp-0.7.1-loadtest.tar
podman run -d --name awlt --restart=unless-stopped \
  -p <lan-ip>:3001:3000 \
  --env-file webapp/.env.loadtest \
  localhost/assessment-webapp:0.7.1-loadtest
```

3. **Verify the guard + gate** (these are your safety net):

```bash
podman logs awlt | grep "BYPASS IS ACTIVE"                 # banner + "Warehouse: ..._Dev"
curl -s http://<lan-ip>:3001/api/health                    # {"status":"ok"}
curl -s -o /dev/null -w '%{http_code}\n' http://<lan-ip>:3001/reports   # 401 (no key)
curl -s -H "x-loadtest-key: $LOADTEST_KEY" -H "x-loadtest-user: <one-upn>" \
     http://<lan-ip>:3001/api/loadtest/seed | head -c 300  # real paths JSON
```

If the container exited instead of serving, `podman logs awlt` will say **REFUSING TO START** and why
(non-`_Dev` warehouse / live host / `AUTH_MODE`≠dev / missing key) — fix and re-run.

## 3. Configure the Locust cluster (k3s)

- `locustfile.py` → **ConfigMap**; `LOADTEST_KEY` → **Secret**; `LOADTEST_USERS` → ConfigMap/Secret env.
- One **master** Deployment + a **workers** Deployment (scale replicas across the 4 Pis), all in the
  `loadtest` namespace, all with the same env and `--host http://<staging-ip>:3001`.
- If addressing staging by name, pin the IP via `hostAliases`. Confirm reachability from a pod:
  `kubectl -n loadtest exec <pod> -- curl -s http://<staging-ip>:3001/api/health`.

## 4. Baseline (before load)

- `curl -s -H "x-loadtest-key: $LOADTEST_KEY" http://<ip>:3001/api/debug/pool` → expect zeros (idle).
- Note Proxmox idle CPU/mem for the VM. (If prod also runs on this box, capture its baseline too.)

## 5. Run — step load + pool sweep

Step the user count to find the knee, holding each step ~3–5 min:

```bash
locust -f locustfile.py --host http://<staging-ip>:3001 --headless -u 25  -r 5 -t 5m
#                                                                  -u 50, 100, 150, 200 ...
```

In parallel, watch the pool/VM:

```bash
./watch_pool.sh http://<staging-ip>:3001 "$LOADTEST_KEY"   # borrowed/pending vs max, event-loop p99
```
…plus the **Fabric Capacity Metrics App** and the **Proxmox** VM graphs.

**Pool sweep:** at the knee, re-run at `FABRIC_POOL_MAX` 20 → 40 → 60. Change it by **restarting the app**
with the new value (`-e FABRIC_POOL_MAX=40` or edit `.env.loadtest`), then repeat the run.

## 6. Interpret

| Symptom during load | Bottleneck | Fix |
|---|---|---|
| `pending > 0` while `borrowed == max`; VM CPU low | **App pool** | raise `FABRIC_POOL_MAX`, re-run; if RPS scales, keep going |
| `eventLoop.p99` ↑ **and** Proxmox VM CPU high | **VM / Node** | resize the VM (Proxmox) or add an app replica behind a balancer |
| Latency ↑ but pool not maxed **and** Fabric CU throttling | **Fabric F8** | bigger SKU — **not** the VM (more replicas make it worse) |
| 401s under load | **Config** | `X-Loadtest-Key` mismatch — fix `LOADTEST_KEY` on both sides |

Record per step: users, RPS, p50/p95/p99, error %, pool max/borrowed/pending, event-loop p99, VM CPU/mem, Fabric CU %.

## 7. Teardown

- Stop Locust (workers + master).
- `podman stop awlt && podman rm awlt` on staging.
- **No data cleanup needed** — this script is **read-only**. (If you later add writes: dev warehouse only,
  then reset it via the full-reset truncate flow.)
- The `loadtest` image/build never goes near production; nothing to revert there.

---

## Config reference

**App container env** (`webapp/.env.loadtest`): `AUTH_MODE=dev`, `ALLOW_DEV_AUTH=true`, `DEV_FAKE_UPN`,
`AUTH_URL=http://<lan-ip>:3001`, `AUTH_SECRET`, `FABRIC_SQL_SERVER`, `FABRIC_SQL_DATABASE=…_Dev`,
`ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`, `FABRIC_POOL_MAX`, `DATA_REGION`,
`LOADTEST_AUTH_BYPASS=true`, `LOADTEST_KEY`, `LOADTEST_USERS`, `LOADTEST_ALLOWED_CIDRS` (optional).

**Locust env** (every pod): `LOADTEST_KEY`, `LOADTEST_USERS`; target via `--host http://<staging-ip>:3001`.

**Headers on every request:** `X-Loadtest-Key: <LOADTEST_KEY>`, `X-Loadtest-User: <upn>`.

**Ports:** app host **3001** (container 3000). **Endpoints:** `/api/health` (public), `/api/debug/pool` +
`/api/loadtest/seed` (key-gated), protected pages under `/enter`,`/reports`,`/programming`,`/cycles`,`/admin`.
