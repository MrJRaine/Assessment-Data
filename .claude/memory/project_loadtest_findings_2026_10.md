---
name: project_loadtest_findings_2026_10
description: "Load-test results (2026-10-02): the web app is Fabric-bound, not app/VM/pool-bound. F8 throughput ceiling ~6-7 RPS; VM CPU ~20% at 100 users; connection-pool knee at FABRIC_POOL_MAX=20. Scale via Fabric SKU / cheaper queries, NOT app replicas/CPU/pool."
metadata:
  node_type: memory
  type: project
---

First real load test of the Phase-3b web app — 2026-10-02, single box (prod host: rootless Podman in
WSL), `0.7.1-loadtest` image (Entra-bypass build) against the **dev** warehouse, Locust generating load
from the same VM. Feeds [[project_capacity_rightsizing_intent]].

## Findings (durable)
- **The app is FABRIC-BOUND, not app/VM/pool-bound.** VM CPU peaked at only **~20%** at 100 concurrent
  users *with the generator on the same box* — ~80% idle. Latency climbs because connections **wait on
  Fabric query responses**, not CPU.
- **F8 throughput ceiling ≈ 6–7 RPS** for this (analyst-weighted) workload.
- **Connection-pool knee = `FABRIC_POOL_MAX=20`.** 10 starves (throughput halves); 20 is the sweet spot;
  30/40 give no gain and worse tails. Keep it at 20.
- **Latency vs concurrency** (pool 20): 20u → p50 1.6 s; 40u → p50 3.1 s; 100u → p50 9.5 s (roster p50 15 s).
  Usable interactive latency holds to ~20 concurrent on this setup; past that it slows but **does not
  error** (only 1–3 transient keep-alive `RemoteDisconnected` per run — no error wall).
- **Heaviest reads:** the roster grid and analyst-scoped cohort. Analysts (region-wide RLS) are the
  expensive identities; the Locust mix over-weights them, so real teacher-dominated traffic is lighter and
  true usable concurrency is likely higher.

## What this means for scaling
- **Helps:** bigger Fabric SKU (more CU); cheaper heavy queries (roster + cohort); the app caches
  (`refCache`/`groupCache`/`identityCache`).
- **Does NOT help:** more app CPU/RAM, more app replicas, or a bigger pool — all downstream of the Fabric
  wall (more replicas vs the same F8 make it worse).

## Still open
- Quantify the ceiling with the **Fabric Capacity Metrics App** during a 100-user run (CU% / throttling) —
  not yet captured.
- **Load-test build bug:** `webapp/src/lib/loadtest.ts` `allowedLoadtestUsers()` doesn't strip the `:role`
  suffix, so the container's `LOADTEST_USERS` must be **bare UPNs** while Locust's must be `upn:role`. Fix =
  strip `:role` so one string works both sides.

## Where the detail lives
Everything (runbook, results, raw HTML reports, full gotchas) is on the **`loadtest` branch** (never merged):
`loadtest/HANDOVER-2026-10-02.md`, `loadtest/results/*.md`, `loadtest/Locust_2026-10-02-*.html`. How to run
it on a Windows/WSL box: `loadtest/RUNBOOK-this-device.md`.
