---
name: project_user_authored_is_auditable
description: Any data a user authors or edits IN THE APP must be trackable — who created it and who changed/removed it — so changes are traceable and a stable state is revertible. App-wide design rule.
metadata:
  type: project
---

Standing rule (user, 2026-09-21): **"Anything that's user-authored in the app should be trackable."** Applies to
every feature, not just math. When a person creates, edits, enables/disables, or deletes data through the app,
the change must be attributable (WHO) and recoverable (revert to a stable set).

**How to apply, by table type:**
- **SCD Type 2 tables** (config with a state history): each version carries `CreatedByStaffKey` (who opened it)
  AND `EndedByStaffKey NULL` (who closed it). The ended-by is essential — a DELETE closes a version without
  opening a successor, so a single "changed-by" column would miss who deleted something. Gives full who-did-what
  + as-of-date state to revert to. Examples: `MathTaskLink`, `MathTaskPacingException`.
- **Append-only / reference tables**: a `CreatedByStaffKey NULL` (null = system/ingest-created, set = person).
  Example: `DimHomeroomComposition` (ingest discovers configs; the GUI "new configuration" path is user-authored).
- **Type-1 dimensions that users edit but that CAN'T be SCD** (a Type-2 re-version would mint a new surrogate key
  and break downstream FKs) → a **separate append-only audit-log table** (who, which row, field, old→new, when).
  Example: `DimMathTask` (must stay Type 1 for stable `MathTaskKey`; a task-edit audit log arrives with the
  post-1.0 leadership GUI). See [[project_math_split_pacing_model]].
- **Facts** already do this via the entered-by column (`FactAssessmentMath.EnteredByStaffKey`, etc.).

Actor = `DimStaff.StaffKey` (same convention as the fact entered-by columns). The web app authenticates as the
`StudentDataAssessment` SP but passes `@UPN`; resolve that to the acting `StaffKey` at write time.

**Flagged for SOON (user, 2026-09-21, not now):** extend audit logging to **operational** actions too —
maintenance windows (set/clear), ingest runs, and Short Cycle operations — so who triggered an op, when, and its
outcome are traceable, not just who edited config rows. Design when we pick it up; not part of the math footprint.
