---
name: capacity-rightsizing-intent
description: "F8 is grant-funded for MVP. Internal budget takes over the 2026-2027 academic year, so the MVP period must double as a sizing study to justify the smallest viable SKU at handoff."
metadata: 
  node_type: memory
  type: project
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

The F8 Fabric capacity ($964 CAD/month) was purchased with a one-time grant to fund MVP build and pilot. Starting the **2026-2027 academic year**, the capacity cost shifts to TCRCE internal budget. The user's stated intent: use the MVP+pilot period to gather actual usage data so the platform can be **right-sized to the smallest viable SKU** before that handoff.

**Why:** Every step down the F-SKU ladder saves real money. F8 → F4 = $482/month savings = ~$5800/year. F8 → F2 = $723/month savings = ~$8700/year. At ~6000 students, ~200 teachers, and 10 analytics users, the actual workload is plausibly an F4 or even F2 — but only empirical capacity-metrics data over a real pilot will prove it.

**How to apply (cross-cutting — affects every architecture decision from here forward):**

1. **Avoid "it's free, so be liberal" reasoning.** Capacity is free *for now*. Future-Jeffrey is paying. Default to modeling decisions as if F2 were the target.

2. **Minimize background / scheduled workloads.** Pipeline polling cadences, scheduled refreshes, capacity-warming jobs — set them to match real need, not "every 15 min year-round just in case." A tight schedule from day one keeps the Capacity Metrics readings interpretable.

3. **Use Fabric Capacity Metrics app to observe.** Install if not already present (Workspace → Get apps → "Microsoft Fabric Capacity Metrics"). Quarterly check-ins through pilot + Sep 2025 rollout will inform the SKU decision.

4. **Architectural choices with capacity implications worth flagging at decision time:**
   - Direct Lake mode (lighter than Import for refreshes)
   - Semantic model refresh schedule (incremental + rare beats nightly full)
   - Pipeline frequency (poll only when uploads plausibly happen — weekday business hours)
   - Spark workloads (avoid for ~6k-student volume — captured already in original design)
   - Warehouse query patterns (analyst-driven; teachers' Power Apps reads are tiny)

5. **Right-size review timing:** plan a capacity utilization review **April-May 2026** (after full school year of pilot + September rollout data), so SKU decision can be made before the budget cycle starts.

Related: [[project_assessment_platform]] (cost summary section is now incomplete — should reference this memory). [[feedback_no_live_ps_connection]] (the materialization preference also aligns with right-sizing — pre-materialized data is cheaper to query at runtime).
