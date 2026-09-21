---
name: project_subject_course_dim
description: "QoL feature (NOT built): a reference Dim mapping course codes → assessment subject (Language Arts = Reading+Writing; Math), used to filter non-teacher group-picker section cards to only subject-relevant sections, and later to scope data ENTRY to those section teachers (view stays open). 1.0 wishlist, likely first to slip to 1.1."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-11T13:44:33.862Z
---

**QoL feature — subject↔course mapping Dim. Requested 2026-09-11; NOT built.**

**What:** a reference/seed Dim (e.g. `DimCourseAssessmentSubject`) listing which **course codes** belong
to each assessment subject family — **Language Arts** (ELA + FLA course codes) → the Reading + Writing
subjects; **Math** course codes → Math. Seeded from the known NS course codes (user will supply the
code lists; likely split ELA vs FLA, and a Math set). One curated reference table, like the other
seeded reference dims ([[project_assessment_platform]] "Reference dimensions").

**Why (two uses):**
1. **Declutter the non-teacher group picker.** The shared picker's HS (10-12) **section cards**
   currently surface EVERY section a student sits in — most irrelevant to a reading/writing (or math)
   short cycle. Filter those cards to only sections whose **course is a subject-relevant LA/Math
   course**, so an admin/analyst picking a group for Reading sees only the Language-Arts sections, etc.
   Big clutter reduction at full-school scale. Hooks into the same section-resolution logic as the
   shared picker ([[project_group_display_redesign]], [[project_programming_makeover]]).
2. **Scope data ENTRY to the right teachers (view stays open).** Use the same mapping to limit WRITE
   access for a subject's short cycle to teachers **of those subject-relevant sections** (the actual
   LA / Math teachers), while still letting other teachers **VIEW** the student data. A write-narrowing
   layered on top of the existing RLS; reads unchanged.

**Priority:** wanted for **1.0**, but it's **the end of the feature list** — the user expects it to be
**one of the first things to slip from 1.0 → 1.1** under any time pressure. Build the earlier
Programming/picker work so this can bolt on (the section-card filter + an entry write-gate are the
integration points) without needing a rebuild.
