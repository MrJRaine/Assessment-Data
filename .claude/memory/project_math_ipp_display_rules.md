---
name: math-ipp-display-rules
description: "Ruled 2026-11-17 — math IPP banding/aggregation model: uniform 80%-of-ALL-tasks threshold (deleted outcomes count the denominator); earned levels count everywhere; unresolved = unmeasured."
metadata:
  node_type: memory
  type: project
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-11-17T15:31:38.584Z
---

Math IPP display model, ruled by the user 2026-11-17 (dev commits `3bce521`→`2dda329`; entry grid
`unitBand` + shared report `unitStat` carry ONE rule):

- **Threshold is uniform per grade × scope**: a unit bands when ≥80% of the grade's FULL task list
  is marked — an IPP's deleted outcomes COUNT the denominator (same total for every student, so
  levels are comparable evidence of ≥80% of the known tasks).
- **Confirmed IPP**: deleted outcomes drop from the numerator/average only. At/above threshold →
  a real level that counts EVERYWHERE a level counts (row, unit bars, tree %, cohort means, donut —
  the donut's old blanket confirmed-IPP exclusion was removed). Below threshold → **'IPP' badge,
  not 'Incomplete'** (the shortfall is the plan's deletions). 'IPP' in tallies/hovers = badge state.
- **Unresolved IPP** (flagged, unconfirmed): unmeasured everywhere — marks visible, no band, no
  aggregates (matches Reading/Writing). Distinguished via `IsChartEligibleMath` in
  tvf_StudentCohortMath + tvf_StudentCohortMathAll (MathIPPStatus NULL is ambiguous); run on dev
  2026-11-17, live pending 1.4.0.
- Non-IPP students unchanged: below 80% = 'Incomplete'.
- RWM untouched by design (excludes confirmed-IPP-in-any, scores the rest uniformly).

See [[consult-entry-semantics-for-reports]] for the process rule this settled.
