---
name: project_math_report_blank_roster_bug
description: "OPEN live bug (0.7.0): the Math report matrix shows 'No students in this group' for some homerooms while the picker card counts students (seen at Carleton Consolidated / Homeroom Doucette, 23 students). Likely tvf_StudentCohortMath's INNER JOIN Tasks dropping students whose grades have no seeded math tasks. Diagnostic written; not yet fixed."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-25T12:38:54.477Z
---

**Reported 2026-09-25 (0.7.0 live).** On the Math report, some schools render the roster matrix
fine, but at least one homeroom shows the empty state **"No students in this group"** while its
**picker card says "23 students"** (Carleton Consolidated Elementary School · Homeroom Doucette).

**Leading hypothesis:** `tvf_StudentCohortMath` ends with
`FROM GroupStudents gs INNER JOIN Tasks t ON t.GradeCode = gs.Grade`, where `Tasks` = active
`DimMathTask` for the group's grades **at the current-year math benchmark months**. If those grades
have **no active tasks configured on live** (only Primary may be seeded — see the entry grid's
"task list for {grade} is still being finalised" note), the INNER JOIN drops **every** student → 0
rows → the page's `rows.length === 0` empty state. The **picker** (`tvf_MathCohortGroups`) counts
students regardless of tasks, so the card still shows 23. Net: a homeroom in grades without seeded
math tasks = full card count, blank matrix. Consistent with "some schools fine, one blank."

**Diagnostic (user runs — I never touch live):**
[diag_math_report_blank_roster.sql](sql/scripts/diag_math_report_blank_roster.sql) — read-only;
shows the homeroom's students by grade vs active task count per grade, plus the full task universe.
If the affected grades show `ActiveMathTasksForGrade = 0`, the hypothesis holds.

**CONFIRMED 2026-10-02:** Homeroom Doucette is a **grade 4/5** class and grades 4/5 have **no math
tasks seeded yet** (still being authored) — so the INNER JOIN drops all 23. Hypothesis holds.

**📌 TODO (USER) — pull the latest math tasks from the shared authoring doc** and check whether new
grades (esp. 4/5+) have been added. If so, seed them (grade CSVs → `usp_LoadMathTasks`) — that both
populates those grades' matrices AND shrinks this bug's footprint. Tracks the "full P-6 seed" TODO in
[[project_math_assessment_model]].

**Fix direction (NOT built — candidate 0.7.1):** mirror the entry grid, which does NOT hide these
students — it shows them under a "Math tasks for {grade} aren't available yet" note. So either
LEFT JOIN the tasks (keep the students, render a per-grade "no tasks yet" note) or make the page's
empty state distinguish "no students" from "students present but no tasks configured for their
grades." The current message is also just wrong ("No students" when there ARE students). This is the
app-side safety net regardless of seeding progress. Relates to [[project_math_assessment_model]].
