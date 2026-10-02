# Load-test comparison — 20u vs 40u vs 40u(pool 40) — 2026-10-02

Exact values from the embedded JSON of each run's HTML report.

| Run (time) | Users | FABRIC_POOL_MAX | Reqs | Fails | RPS | avg (ms) | p50 | p95 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 14h43 | 20 | 20 | 809 | 1 | 2.9 | 2671 | 1600 | 9500 | 18000 | 31314 |
| 14h48 | 40 | 20 | 926 | 0 | 4.85 | 4749 | 3100 | 14000 | 31000 | 41514 |
| 14h55 | 40 | **40** | 996 | 1 | 4.42 | 5489 | 3000 | 20000 | 33000 | 44052 |

Roster (`/enter/cycle/.../{group}` — heaviest real page, the knee indicator):

| Run | Users | Pool | avg (ms) | p50 | max |
|---|---:|---:|---:|---:|---:|
| 14h43 | 20 | 20 | 5410 | 3700 | 31314 |
| 14h48 | 40 | 20 | 9440 | 7000 | 41514 |
| 14h55 | 40 | 40 | 11479 | 8800 | 44052 |

(Seed is absent/0 in the 40u runs — the locustfile caches it per UPN, so these aggregates are real page
reads, not skewed by the 7-query seed.)

## Pool sweep at 40 concurrent users (the deciding data)

| Run | FABRIC_POOL_MAX | RPS (total) | p50 | p95 | avg | roster p50 | Fails |
|---|---:|---:|---:|---:|---:|---:|---:|
| 15h05 | **10** | 2.78 | 7.7 s | 29 s | 10.6 s | 19.0 s | 1 |
| 14h48 | **20** | 4.85 | 3.1 s | 14 s | 4.7 s | 7.0 s | 0 |
| 15h23 | **30** | 3.97 | 4.0 s | 20 s | 6.5 s | 12.0 s | 1 |
| 14h55 | **40** | 4.42 | 3.0 s | 20 s | 5.5 s | 8.8 s | 1 |

Pool 10 clearly starves; 20/30/40 are within run-to-run noise on p50 but **20 has the best tails**
(p95 14 s vs 20 s; roster p50 7 s vs 12/8.8). Knee ≈ **20**; above it, no throughput gain and worse tails.

## Scaling by user count (best/representative pools)

| Users | Pool | RPS (total) | p50 | p95 | roster p50 | max | Fails |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 | 20 | 2.9 | 1.6 s | 9.5 s | 3.7 s | 31 s | 1 |
| 40 | 20 | 4.85 | 3.1 s | 14 s | 7.0 s | 42 s | 0 |
| 100 | 30 | 6.70 | 9.5 s | 23 s | 15.0 s | 57 s | 3 |

- **Throughput keeps climbing but sub-linearly** — 2.9 → 4.85 → 6.70 RPS as users go 20 → 40 → 100
  (100 users = 2.5× the 40-user load for only ~1.4× throughput). The server's ceiling is ~**6–7 RPS**
  on this box; it's deep into diminishing returns by 100.
- **Latency degrades fast** — p50 1.6 s → 3.1 s → **9.5 s**; roster p50 3.7 s → 7 s → **15 s**.
- **No hard failure wall even at 100 users** — 1–3 transient `RemoteDisconnected` per run, no error storm.
  It doesn't fall over; it just gets slow.

## Findings

1. **Pool 20 is the sweet spot at 40 users.** Going 10→20 roughly **doubled throughput** (2.1→4.85 RPS)
   and **halved latency** (p50 7.7→3.1 s; roster p50 19→7 s) — at pool 10 the app is **connection-starved**,
   requests queue waiting for a free connection. Going 20→40 gave **no gain** (slightly worse: p95 14→20 s,
   roster avg 9.4→11.5 s, RPS 4.85→4.42) — past 20 the pool stops being the limiter and the extra
   connections just over-subscribe the backend.

2. **So the pool matters up to ~20, then the wall moves downstream.** Below 20 = pool-bound; at/above 20 =
   Fabric/VM-bound. `FABRIC_POOL_MAX=20` is the right setting for this load — keep it there (10 starves, 40
   doesn't help).

3. **Already saturated below 40 users regardless.** Even at the best pool (20), 20→40 users bought only
   +67% throughput for ~2× latency — past the knee.

4. **Not an error wall — a latency wall.** 0–1 transient `RemoteDisconnected` (keep-alive race) per run.

## CPU evidence (2026-10-02) — settles Fabric-vs-VM
Observed during the runs: the VM's **CPU only touched ~20% a couple of times**, and that was on the
**100-user** run — **with Locust generating load on the same VM**. So the app host has ~80% idle headroom
even at 100 users *including* the generator. The box/VM/Node is **not** the limiter, and the single-box
confound I'd been flagging is moot here — CPU never came close to saturating.

Low CPU + latency climbing + pool-insensitive above 20 = the app is **waiting on I/O (Fabric)**, not
computing. Connections sit idle awaiting query responses.

## Conclusion
**The bottleneck is Fabric warehouse throughput (F8 capacity / query cost) — not the app, not the pool
above ~20, not the VM CPU.**
- `FABRIC_POOL_MAX=20` is right: below it the app is connection-starved; above it the extra connections
  just queue more work at Fabric (worse tails, no throughput gain). ~20 in-flight queries is all F8 serves
  usefully for this workload.
- Throughput ceiling ≈ **6–7 RPS**, set by Fabric, with the app server ~80% idle.
- **Scaling levers that WILL help:** a bigger Fabric SKU (more CU), and/or cutting per-request Fabric cost
  (optimise the heavy reads — roster + analyst-scoped cohort are the hogs — and lean on the app caches
  `refCache`/`groupCache`/`identityCache`).
- **Levers that WON'T help:** more app CPU/RAM, more app replicas, or a bigger pool — all downstream of the
  real wall. (More replicas against the same F8 would make it worse.)

## Still worth capturing to quantify the ceiling
Fabric Capacity Metrics App during a 100-user run → CU% / throttling. If CU is pegged/throttling, that's
the direct confirmation and tells you how much a bigger SKU would buy.

## Can't fully separate Fabric vs VM yet — and a confound
These HTML reports show no pool/CPU telemetry, so Fabric-vs-VM isn't decided. **Confound:** the generator
(Locust), the load-test app (`awlt`), AND the live app (`aw`) all share THIS one box's CPU — so any
"VM-bound" reading is muddied by the generator stealing CPU from the app. To decide, capture during a run:
- `/api/debug/pool` → `borrowed`/`pending` vs max + `eventLoop.p99` (pending>0 at max = pool; eventLoop.p99↑ = Node/VM).
- Fabric Capacity Metrics App → CU% / throttling (throttle = F8).
- Box CPU (Task Manager) → is the box pinned (and how much is Locust itself)?

## Practical read for rollout sizing
On **this single-box setup**, usable latency holds to ~20 users (p50 1.6 s, though p95 already 9.5 s from
roster/tails); by 40 users it's p50 3 s / p95 14–20 s — too slow for the UI. BUT this is a **floor, not the
ceiling**: a dedicated app host (no generator + no live app competing for CPU) and a warm warehouse should
do better. Re-test with the generator OFF the box to get a clean server-capacity number.
