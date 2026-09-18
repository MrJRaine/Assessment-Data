---
name: capacity-rightsizing-intent
description: "F8 was bought DELIBERATELY as a high ceiling so real usage runs UNRESTRICTED and can be measured — then the right SKU is purchased at renewal. Do NOT design as if F2 were the target; that suppresses the very number we're trying to measure."
metadata: 
  node_type: memory
  type: project
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

The F8 Fabric capacity ($964 CAD/month) was purchased with a one-time grant to fund MVP build and pilot. Starting the **2026-2027 academic year**, the capacity cost shifts to TCRCE internal budget. The user's stated intent: use the MVP+pilot period to gather actual usage data so the platform can be **right-sized to the smallest viable SKU** before that handoff.

**Why:** Every step down the F-SKU ladder saves real money. F8 → F4 = $482/month savings = ~$5800/year. F8 → F2 = $723/month savings = ~$8700/year. At ~6000 students, ~200 teachers, and 10 analytics users, the actual workload is plausibly an F4 or even F2 — but only empirical capacity-metrics data over a real pilot will prove it.

**How to apply (cross-cutting — affects every architecture decision from here forward):**

1. **F8 is a deliberate MEASURING ceiling — do NOT design as if F2 were the target** (corrected by the user 2026-09-18; the original wording said to model for F2 and that was wrong). The whole point of buying F8 is that the workload runs **unrestricted**, so the Capacity Metrics reading reflects *real* demand and the renewal purchase is sized on evidence. Artificially throttling the app to fit an assumed F2 would suppress the very number the study exists to capture, and risks **under-buying** at renewal.
   - Still avoid genuine *waste* (redundant queries, needless polling, N+1 writes) — that's just good engineering and it makes the metrics interpretable.
   - But never trade correctness, UX, or a feature for speculative capacity savings. Measure first, buy right, optimise on evidence.
   - **Timing matters:** land efficiency fixes BEFORE the measurement period so the numbers reflect the shipped product, not a pre-optimisation shape you'll never run.

2. **Minimize background / scheduled workloads.** Pipeline polling cadences, scheduled refreshes, capacity-warming jobs — set them to match real need, not "every 15 min year-round just in case." A tight schedule from day one keeps the Capacity Metrics readings interpretable.

3. **Use Fabric Capacity Metrics app to observe.** Install if not already present (Workspace → Get apps → "Microsoft Fabric Capacity Metrics"). Quarterly check-ins through pilot + Sep 2025 rollout will inform the SKU decision.

4. **Architectural choices with capacity implications worth flagging at decision time:**
   - Direct Lake mode (lighter than Import for refreshes)
   - Semantic model refresh schedule (incremental + rare beats nightly full)
   - Pipeline frequency (poll only when uploads plausibly happen — weekday business hours)
   - Spark workloads (avoid for ~6k-student volume — captured already in original design)
   - Warehouse query patterns (analyst-driven; teachers' Power Apps reads are tiny)

5. **Right-size review timing — deadline is APRIL** (user, 2026-09-18): roughly **7 months of measurement
   runway** from the Sept 2026 launch. That's generous, and it changes the strategy: there is NO need to
   freeze the app to protect a single clean reading. Preferred approach is **iterative** — measure the
   shipped shape through the first real cycles, apply the efficiency items ([[project_perf_qol_backlog]]),
   re-measure, and compare. A before/after pair is *more* informative for sizing than one reading, and
   the pool ceiling can be dialled in over the same period.
   *(The original line here read "April-May 2026" — stale, that date has passed; this project has a known
   history of year typos in planning docs.)*

Related: [[project_assessment_platform]] (cost summary section is now incomplete — should reference this memory). [[feedback_no_live_ps_connection]] (the materialization preference also aligns with right-sizing — pre-materialized data is cheaper to query at runtime).
