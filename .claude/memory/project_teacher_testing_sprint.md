---
name: project_teacher_testing_sprint
description: "Deadline-driven sprint (set 2026-09-09) toward TEACHER TESTING the week of 2026-09-14. Time-boxed daily goals — prior-year baseline display, IPP+Adaptations makeover, then test/clean + Math."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-09T18:51:13.326Z
---

**Hard target: everything teacher-test-ready by end of Friday 2026-09-11, for teacher testing
the week of 2026-09-14.** Set by the user 2026-09-09. Work is time-boxed — move efficiently.

- **Thu 2026-09-10:**
  1. **First few hours — NAIL the prior-year baseline display (v0.4.0).** Not open-ended; build
     it efficiently against the locked spec in [[project_prior_year_baseline]] (starting-point read
     with the Sept-2027 year-flip abstraction; roster row = June level + cumulative Δ vs June;
     codes→NULL). Branch `feature/prior-year-baseline` (off `main`) is already staged with the
     baseline SQL. Ship as v0.4.0 minor.
  2. **By end of day — the "IPP + Adaptations makeover."** A rework of how IPPs and Adaptations are
     handled/shown (scope to confirm at the top of that task; relates to `FactStudentIPP`, the IPP
     confirm flow [[project_ipp_type_labelling]], and the "Current Adaptations" attribute).
- **Fri 2026-09-11:** TEST + CLEAN the IPP/Adaptations makeover AND **Math** (Math P-6 is on
  `feat/math-p6-entry`, [[project_math_assessment_model]]) → get them teacher-test-ready.
- **Week of 2026-09-14:** teacher testing.

**How to apply:** at session start tomorrow, don't sprawl — the baseline display is a first-few-hours
job, then pivot to the IPP/Adaptations makeover. Prune this memory once the sprint is past.
