---
name: consult-entry-semantics-for-reports
description: "Before changing how a REPORT interprets data, consult the data-entry surface that authors it — entry defines the semantics; reports follow or escalate."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-11-17T15:18:54.805Z
---

When changing how a report/summary interprets stored data (bands, exclusions, eligibility,
averages), FIRST read the data-entry surface for that data — it is the authoritative
interpretation of what a stored value means. Mirror it, or surface the divergence as a
question; never redesign report-side semantics from an analogy to another subject.

**Why:** 2026-11-17 — ruled "math should match Reading/Writing" on unresolved IPPs, and I
applied R/W's blanket no-band rule to the whole math report without checking the math ENTRY
grid, which deliberately bands a confirmed-IPP student when ≥80% of their non-IPP tasks are
scored (per-task exclusion + partial flag). Had to amend: confirmed IPP = entry-style
personal-progress band on the row, excluded from all aggregates; unresolved = unmeasured.
Same session also missed sweeping all IPP display surfaces before fixing one
([[rls-review-verify-per-role]] pattern: verify the WHOLE surface).

**How to apply:** Any report change touching interpretation: (1) locate the entry
grid/upsert proc for that data; (2) diff its rules against the planned report rule;
(3) differences go to the user as a question with both behaviours named. A user analogy
("match X") is scoped to the defect raised, not a license to rewrite the subject's model.
