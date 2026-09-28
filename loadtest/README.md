# Locust load test — SCoR Dashboard

Drives the **load-test build** (Entra bypass, dev warehouse, `loadtest` branch) to size the VM and find
the connection-pool ceiling. Canonical source lives here; copy `locustfile.py` into the k3s ConfigMap/image.

## Prerequisites

- The app running as the load-test build on staging, host port **3001** (see `docs/LOADTEST_HANDBACK.md`).
- `pip install locust`
- Two env vars (same values the app was started with):
  - `LOADTEST_KEY` — the `X-Loadtest-Key` the app expects.
  - `LOADTEST_USERS` — comma-separated `upn[:role]`, role ∈ `teacher|admin|analyst`. Compose the intended
    mix (e.g. **16 teachers + 2 admins + 2 analysts**); identities are assigned round-robin, so the
    population mirrors this list. Fill the UPNs from `sql/scripts/list_loadtest_identities.sql`.

## Run

```bash
export LOADTEST_KEY='...'
export LOADTEST_USERS='t1@tcrce.ca:teacher,...,a1@tcrce.ca:admin,an1@tcrce.ca:analyst'

# single process, headless: 50 users, spawn 5/s, 10 min
locust -f locustfile.py --host http://<staging-ip>:3001 --headless -u 50 -r 5 -t 10m

# with the web UI (watch live): drop --headless, open http://localhost:8089
locust -f locustfile.py --host http://<staging-ip>:3001
```

Distributed (k3s: 1 master + N workers) — **same file, same env on every pod**:

```bash
locust -f locustfile.py --master --host http://<staging-ip>:3001
locust -f locustfile.py --worker --master-host=<master-ip>   # ×N
```

k3s sketch: `locustfile.py` → ConfigMap; `LOADTEST_KEY` → Secret; `LOADTEST_USERS` → ConfigMap/Secret;
one master Deployment + a workers Deployment (scale replicas), all in the `loadtest` namespace, on the
VLAN that can reach `<staging-ip>:3001`.

## Watch the pool during a run

In another shell, poll the telemetry endpoint (this is the whole point):

```bash
./watch_pool.sh http://<staging-ip>:3001 "$LOADTEST_KEY"
```

Reading it:
- `pending > 0` while `borrowed == max` → **connection pool is the wall**. Restart the app with a higher
  `FABRIC_POOL_MAX` and re-run; if throughput rises, keep going until it stops scaling.
- `eventLoop.p99Ms` climbing (with VM CPU high in Proxmox) → **Node/VM is the wall** → resize the VM or add a replica.
- Neither moves but latency still climbs → **Fabric F8** is the wall (confirm in the Fabric Capacity Metrics App) → SKU, not the VM.

## Method

Step-load to find the knee: e.g. `-u 25`, then 50, 100, 150, 200 (`-r` = spawn rate), holding each a few
minutes. Repeat the sweet-spot run at `FABRIC_POOL_MAX` 20 → 40 → 60 to separate pool-bound from VM/Fabric-bound.
Reads only (this script issues no writes), which is the pool/serving bottleneck anyway.
