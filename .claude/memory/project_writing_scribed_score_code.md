---
name: project_writing_scribed_score_code
description: "PLANNED writing-model change — add score code \"SCR\" (Scribed), selectable ONLY for the Conventions and Organization traits, and OMITTED from all calculations (average / achievement band computed over the remaining scored traits)."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-09T18:42:26.686Z
---

**Planned addition to the writing assessment model (requested 2026-09-09, not built).**

Add a score code **`SCR` = "Scribed"** for writing entry, available **only on the
Conventions and Organization** traits (NOT Ideas, NOT Language). When a student's writing
is scribed (someone else physically writes for them), conventions and organization aren't
the student's own production, so scoring them would be invalid.

**`SCR` is OMITTED from every calculation.** The 4-trait average (and therefore the
achievement band: ≥3.50 Exceeding / ≥2.75 Meeting / ≥1.75 Approaching / else Not Yet
Meeting) must be computed over the **scored traits only** — i.e. `SUM(scored) / COUNT(scored)`,
not always `/4`. If Conventions and/or Organization are `SCR`, they drop out of both the
numerator and the denominator (a student with both scribed averages over Ideas + Language
only).

**Why:** scoring conventions/organization on scribed work would penalize (or credit) the
student for something they didn't produce; excluding those traits keeps the achievement
level reflective of only what the student is responsible for.

**Related NON-NUMERIC score codes (all omitted from calculations, same as SCR):**
- **Going forward (live entry): only `SCR`** (Scribed).
- **Historical data** (appears in the 2025-2026 prior-year baseline sheets, and possibly
  on reading levels too): **`ABS`** (Absent), **`INS`** (Insufficient evidence), **`EAL`**
  (English as an Additional Language Learner). These are legacy — not entered going forward.
- Storage rule everywhere: writing trait columns (and the reading level) are **VARCHAR**,
  hold `'1'`–`'4'` (writing) / a scale code (reading) OR one of these codes verbatim.
- **Averaging rule: a code becomes NULL, never 0.** Convert any non-numeric code to NULL
  before averaging so it drops out of BOTH the numerator and the denominator (SQL `AVG`/`SUM`
  ignore NULLs) — the average is over the scored traits only. Counting a code as `0` is WRONG
  (it would wrongly depress the score). If ALL four traits are codes, the average is NULL (no
  writing score / no writing starting point). Same rule for the cumulative Δ vs the June anchor.

**How to apply (touch points):**
- **Writing entry UI** (`WritingRosterEntry`): allow `SCR` as a selectable value on the
  **Conventions** and **Organization** inputs only.
- **Storage** (`FactAssessmentWriting` + `usp_UpsertWritingAssessment`): the trait columns
  are currently 1-4 ints; `SCR` is non-numeric, so it needs a representation (e.g. store NULL
  with an accompanying code/flag, or a sentinel) + validation that only Conventions/
  Organization may be `SCR`.
- **All writing reads** (`tvf_TeacherRosterWriting`, cohort/history writing TVFs): recompute
  the average as sum/count over non-`SCR` traits, and guard the low-denominator case.
- Achievement-band mapping is by the average code (see [[project_assessment_platform]] writing
  model), so it follows automatically once the average excludes `SCR`.
