---
name: No Live PowerSchool Connection
description: Architecture decisions in this project must account for batch-only PS ingest — there is no live connection to PowerSchool, so "live view" freshness arguments are invalid
type: feedback
originSessionId: 99c423bc-bf8e-47e1-9e2c-2e979ea586d6
---
This project has **no live connection to PowerSchool**. All PS data lands via manual CSV uploads followed by ingest pipelines. DimStaff, DimStudent, DimSection, FactEnrollment, and FactStaffAssignment only change when an ingest runs.

**Why:** User flagged this 2026-04-29 after I argued in favor of `vw_StaffSchoolAccess` as a view (instead of a materialized table) on the grounds it would stay "live." That reasoning was wrong — the view computes against DimStaff/FactStaffAssignment, which themselves are stale until the next ingest. View vs. materialized table = same staleness, just different compute timing.

**How to apply:**
- Don't argue for query-time computation on freshness grounds — there's no upstream signal that arrives between ingests.
- Materialization on ingest is generally preferable for any RLS / lookup / pre-aggregation use case here, because:
  - Same staleness as a view
  - Faster queries (Power Apps will hit RLS predicates frequently)
  - Lower Fabric capacity utilization
- The "no manual RLS entries" principle (from project memory) is preserved by EITHER approach — the bar is "derivable from authoritative staff export," not "computed at query time."
- When evaluating any caching / materialization trade-off in this project, the freshness column is essentially constant. The real axes are: query cost, storage cost, complexity, drift across re-runs of the same data.

**Other implications of the manual-upload model:**
- Power Apps writes (assessment entries) DO hit the warehouse live — those are the only "live" data path. PS-sourced data is always batch.
- Year-end close-outs, mid-year transfers, role changes, etc., all reflect on the next manual ingest, not in real-time.
- Any "should we cache this?" question should default to YES (cache/materialize) unless there's a specific reason to recompute.
