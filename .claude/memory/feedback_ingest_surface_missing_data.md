---
name: feedback_ingest_surface_missing_data
description: Ingest merges must SURFACE excluded/unresolved source rows actionably to the operator running the files — never silently drop on a resolution failure. Silent skip preserves DB integrity but hides missing data and surfaces later as user access complaints.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-09T13:37:48.364Z
---

**The ingest must not silently drop a source row when a resolution fails** (blank
teacher email, unresolved teacher / section / student, etc.). It must **surface the
specific missing data to the person updating the files**, actionably, so they can fix
the source.

**Why:** database integrity ≠ operator awareness. A silent (or merely count-in-the-
audit) exclusion looks like a clean ingest, but the dropped data reappears downstream
as "this teacher can't access the system" / "they can't see their students" — and the
operator has no breadcrumb pointing at the source problem. The person maintaining the
PS exports is exactly who needs the alert.

**How to apply:**
- When a merge excludes rows, don't stop at an opaque count in `FactSubmissionAudit`
  ("N sections excluded — teacher did not resolve"). Emit the **specific items and the
  specific reason** — e.g. SectionID + course + "BLANK teacher email" vs "teacher email
  not found in DimStaff" — somewhere the operator sees per run (a rejects/exceptions
  table or per-run exception report), distinguishing **blank source data** from a
  **lookup miss**.
- Never add exclusion logic without a matching visible, actionable alert.
- Revisit whether structurally-unlandable rows should be landable at all — e.g.
  `DimSection.TeacherStaffKey` is `NOT NULL`, so a teacherless section can't land; decide
  nullable/sentinel-teacher vs. keep dropping-but-loudly.

**Origin (2026-09-09):** 12 `Sections.csv` rows had a **blank teacher email** →
`usp_MergeSection`'s `INNER JOIN DimStaff` dropped each whole section (can't hold a
teacherless section, `TeacherStaffKey NOT NULL`) → **281 enrollments orphaned**, those
students absent from those section rosters. The only signal was an opaque count in the
audit message. Diagnosed with `sql/scripts/diag_unresolved_enrollment_sections_live.sql`
+ `diag_unresolved_section_teachers_live.sql`. Related merge procs: `usp_MergeSection`,
`usp_MergeEnrollment`. See [[project_assessment_platform]] (ingest conventions).
