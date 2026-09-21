---
name: feedback_select_clear_all_labels
description: App-wide UX standard — every bulk select/deselect control uses the exact labels "Select all" / "Clear all". Review existing pages for compliance later.
metadata:
  type: feedback
---

Standardized 2026-09-03: any **bulk select/deselect control** in the web app uses the exact
button text **"Select all"** and **"Clear all"** — never "Clear", "None", "all / none",
"Deselect all", "Reset", etc.

**Why:** consistency across the app. Set while building the Math roster-entry UX
([[project_math_assessment_model]]) where the student picker, the grade-level task bar, and each
unit's task controls all needed the same verbs; the user asked to make it an app-wide standard.

**How to apply:** use these two labels verbatim for every new multi-select bulk action.
**TODO (later):** review existing pages for compliance and align any that differ — the `/students`
cohort filters, `/enter` reading/writing grids, `/ipp`, and `/cycles`. Not urgent; do it as a pass
before full rollout.
