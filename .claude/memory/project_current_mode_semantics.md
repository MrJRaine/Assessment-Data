---
name: project_current_mode_semantics
description: "Reports \"Current\" mode = each student's most recent evidence EVER (lifetime, prior years included), NOT this-school-year-only; tvf_StudentCohort is the spec."
metadata:
  node_type: memory
  type: project
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-11-12T19:34:17.038Z
---

**"Current" on the Reports pages = the most current evidence available for every student — lifetime, prior school years included.** User ruling 2026-11-12: "The stated goal for 'current' is and has always been the most current evidence available for all students." `tvf_StudentCohort` (the flat Student list, `@CycleGroupID IS NULL` → no window restriction at all) is ON SPEC and is the reference implementation. The oversight roll-up TVFs' this-year-only Current mode was the defect, as was a "Most recent result so far this year" tooltip I added to the CycleSelector Current chip without surfacing it (fixed same day).

**Why:** divergent Current semantics made the summary donut and the Student list donut disagree; I proposed "fixing" the list to match the summary and had the direction exactly backwards.

**How to apply:** any new report feed's no-cycle mode picks each student's latest result with NO school-year restriction; never reintroduce a CurYear/SchoolYear gate on the latest-pick in Current mode (grade-span/population gates may stay current-year). Open question flagged 2026-11-12: whether Math / RWM Current should also go lifetime (math is task×month×grade-bound, so lifetime is murkier). See [[feedback_no_unilateral_scope_decisions]].
