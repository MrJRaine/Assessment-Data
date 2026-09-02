---
name: project_homeroom_chips_unwieldy
description: UX issue — the Homeroom list rendered as smart chips is unwieldy for analysts at full-dataset scale; needs a denser picker (search/filter/dropdown) before full rollout.
metadata:
  type: project
---

Observed 2026-09-02 during the first real PowerSchool ingest / analyst view: the
Homeroom list rendered as smart chips is a little unwieldy once the FULL dataset
is loaded. A RegionalAnalyst sees region-wide homerooms, so the chip list grows
far past what chips are comfortable for (chips suit a short, bounded set).

**Why:** Smart chips were fine at pilot/synthetic scale (few homerooms) but don't
scale to the ~200-teacher / all-schools roster an analyst sees. Not a blocker for
the analyst data-visibility fix ([[project_webapp_fabric_connection]]), just a
UX rough edge surfaced by real-data volume.

**How to apply:** Before full rollout, swap the chip layout for a denser
homeroom picker — searchable/filterable dropdown or a scoped (school-first) list —
for the analyst/region-wide path. Scope-narrow first (pick school → then homeroom)
rather than showing every homeroom flat. Revisit when polishing the `/students`
(analyst) screen; low priority relative to the cutover verification.
