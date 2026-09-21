---
name: feedback_never_silently_omit
description: "UX is paramount — it drives staff adoption. NEVER let a teacher wonder why something isn't showing. Anything filtered, dropped or unavailable must say so, name who/what is affected, and say what to do. Silent omission is a bug, even when the filtering is 'correct'."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-18T15:07:24.080Z
---

**The primary goal for everything is that it works and reads intuitively.** The user, 2026-09-18:
*"we shouldn't have any cases where teachers may be left scratching their heads wondering why they
don't see something"* and *"UX is paramount for reducing any adoption resistance from staff."*

**Why:** ~200 teachers have to adopt this voluntarily, and a teacher who opens their class and sees
the wrong thing — with no explanation — doesn't file a bug, they lose trust and stop using it.
Adoption resistance is the real risk, not a crash. Worse, silent omission in an ENTRY screen means
missing assessment data nobody knows is missing.

**A silent omission is a defect even when the filter is correct.** The trigger case: the math roster
INNER JOINed DimMathTask, so a student whose grade had no tasks for that month vanished — a class of
4 opened as 1, while the card still said 0/4. Nothing was "wrong" by the query's own logic; the
teacher simply had no way to know three children were missing or why.

**How to apply:**
- Never drop a row/group/section quietly. Show it with the reason. Prefer `LEFT JOIN` + an explicit
  note over `INNER JOIN` + disappearance.
- Name the affected people/items: "These 3 students can't be marked until tasks are loaded for
  Grade 2: A, B, C" beats "Some students are unavailable."
- Say what to do next ("ask your administrator to load the task list"), not just what is wrong.
- COUNTS MUST AGREE with what opens. A card saying 0/4 that opens showing 1 is a bug in itself —
  either fix the filter or explain the difference on the roster.
- Empty states must explain WHY this particular user sees nothing (grade/program scope, no roster,
  not the teacher of record), never a bare "No results".
- When I catch myself writing a comment like "silently dropped" or "skip these", that is the smell —
  stop and surface it instead.
- Applies to filters, scope rules, permissions, and incomplete reference data alike. Same principle
  as [[feedback_ingest_surface_missing_data]] (ingest must surface excluded rows + reason), applied
  to the teacher-facing UI.

Related: [[feedback_ingest_surface_missing_data]], [[feedback_loading_states]],
[[feedback_avoid_assessment_term]], [[feedback_select_clear_all_labels]].
