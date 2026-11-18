---
name: consult-entry-semantics-for-reports
description: "Before stating, assuming, recording, asking or proposing ANYTHING about how data is counted/excluded/coloured, READ how the app already handles it (entry grid, existing report code, the subject's ruling memory) — entry defines the semantics; never describe an existing rule from recall. Three misses in 48h (2026-11-17/18)."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95b469e7-1d0c-487e-bcab-9f5c26d0c5b6
  modified: 2026-11-17T17:19:24.289Z
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
A SWEEP of a subject's display surfaces INCLUDES its entry grid — "clean" means the
report surfaces agree with ENTRY, not merely with each other. (Second miss 2026-11-17:
declared writing clean comparing reports to reports/reading, while writing's entry Avg
cell already showed IPP-not-number — the divergence the sweep existed to find.)

**THIRD miss, 2026-11-18 — the rule is WIDER than "report changes".** While only RECORDING the
user's rulings for a new Math homeroom report, I (a) wrote "omit every Math-IPP student = the
existing rule" without opening [[math-ipp-display-rules]] (wrong on both halves), (b) assumed task
cells use the unit band cut-offs (they use the entry grid's `heatClass` task cut-offs), and
(c) parked "how do Blanks affect the task %" as an open question when the existing class view
already answers it. User: *"third time in 48hrs I'm reminding you that you should be looking at the
way we're already handling things to see how to handle data."*

**So, applies at EVERY stage, not just implementation:** before I state, assume, record, ask or
propose ANYTHING about how data is counted, excluded, coloured or labelled — in a backlog note, a
question to the user, a 50-ft proposal, or a summary — I first READ how the app already handles
that exact thing (the entry grid/upsert proc, the existing report code, and the ruling memory for
that subject) and quote it with its file/function. An "open question" is only legitimate AFTER that
read shows the existing surfaces don't answer it or disagree with what the user just said; then the
question names both behaviours. Never describe an "existing rule" from recall.
