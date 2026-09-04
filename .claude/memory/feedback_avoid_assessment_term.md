---
name: Avoid the term "assessment"
description: App is the "Short Cycles of Response App"; avoid the word "assessment" in user-facing text (UI labels, docs, wording) as much as possible.
metadata:
  type: feedback
---

The product is being (re)named the **"Short Cycles of Response App"** and the word **"assessment" is being phased out of user-facing wording** — UI labels, page copy, user guides, everything a teacher or admin reads. Prefer "results", "Short Cycle", "record results", "Data Entry", etc.

**Why:** naming/branding decision by the user (2026-09-04). "Assessment" carries baggage they want off the surface; the app is framed around *Short Cycles of Response*, not "assessments".

**How to apply:**
- In new UI copy and docs, do not introduce "assessment". Use "results" / "Short Cycle" / subject names.
- Internal identifiers stay as-is — `AssessmentType`, `DimAssessmentWindow`, `FactAssessment*`, `AssessmentWindowID`, `assessmentType` — renaming those is out of scope and risky. This rule is about **visible text only**.
- Known survivors still in the live UI (flag when touched, offer to rename): the student-detail heading **"Assessment history"** and the cohort donut center label **"ASSESSED"**. A rename there is a code change the user can approve.
- The subtitle/brand line on the user guides is "Short Cycles of Response App", not "Assessment Data Platform".

Related: [[feedback_file_links_in_instructions]]. The 7 ASD-STE100 user guides (`docs/user-guides/*.docx`) were reworded to this rule on 2026-09-04.
