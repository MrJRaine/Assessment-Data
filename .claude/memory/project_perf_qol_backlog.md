---
name: project_perf_qol_backlog
description: "POST-v1.1 QoL backlog — efficiency items that cut server + Fabric load (cache reference lookups, batch the per-student save loop, parallelise roster awaits, stop polling hidden tabs). Nice-to-have, NOT blocking launch. Pool max already raised to 20."
metadata:
  node_type: memory
  type: project
---

**Performance / load QoL backlog — scheduled POST-v1.1** (user, 2026-09-18). None of these are
launch-blocking; they're "nice to have." Identified while characterising server load ahead of the
capacity-sizing study.

**Already DONE (not backlog):** connection pool max raised 10 → **20** in `webapp/src/lib/db.ts`
(2026-09-18) so real concurrency reaches Fabric and the Capacity Metrics reading isn't suppressed by
in-app queueing — see [[project_capacity_rightsizing_intent]].

## The backlog items (rough value order)
1. **Batch the per-student save loop.** The entry save actions call the upsert proc **once per
   student** (`for (const e of entries) await execProc(...)`), plus a scope-gate roster re-query first —
   a 30-student roster save is ~31 sequential round-trips. Biggest single write win, and Fabric
   Warehouse specifically dislikes frequent small writes (parquet churn).
2. **Cache the static reference lookups.** `getScaleLevels` (DimReadingScale, 59 rows) and
   `getAchievementLevels` (DimAchievementLevel, 4 rows) are re-queried on **every** roster page load
   even though they're static config. Removes ~2 of the ~4 queries per roster load.
3. **Parallelise the sequential `await`s** on the roster page (`/enter/<cycle>/<group>`) with
   `Promise.all` — they're independent but run serially today.
4. **Stop polling on hidden tabs** (Page Visibility API) in `MaintenanceProvider`. Every open tab polls
   `/api/status` every 8s forever; ~200 teachers with a tab open ≈ 25 req/s of pure background floor.
   The DB is already protected (4s in-process cache) so this is Node/TLS load, not Fabric load.

## Load context (why these and not others)
The app is **I/O-bound, not CPU-bound** — the container mostly waits on Fabric. Every page is
`force-dynamic` (nothing cached), and `layout.tsx`/AppShell adds an auth + capabilities query to
**every** navigation. Heaviest paths: the reading roster (`tvf_TeacherRoster`, 11 CTEs) and the
`/students` cohort (whole-region result set for an analyst).

**All DB access is server-side** (`import 'server-only'` in db.ts; client components import types only;
writes go through server actions) — so the container is the single funnel, and the pool is the
throughput knob. Pools are **per-process**, so horizontal scaling DOES multiply connections; the
ceiling then moves to the Fabric capacity SKU.

## Timing — relaxed (user, 2026-09-18)
There is **runway until April** (~7 months from the Sept 2026 launch), so these do NOT need to land
before launch to protect the capacity study. Preferred: measure the shipped shape through the first
real cycles, then apply these, then re-measure — the before/after pair is *more* useful for sizing than
a single reading, and the pool ceiling gets dialled in over the same window. Just record which build a
given measurement came from.

Related: [[project_capacity_rightsizing_intent]], [[project_prelaunch_queue]], [[project_dark_mode]] (other post-1.0 QoL).
