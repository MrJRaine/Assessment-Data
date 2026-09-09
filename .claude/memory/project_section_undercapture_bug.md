---
name: project_section_undercapture_bug
description: "RESOLVED 2026-09-09 — HS section under-count root cause was the FactEnrollment.ActiveFlag bug (all rows inactive → SectionKey freeze), NOT the TVFs. Fixing ActiveFlag + re-merge snapped rosters to current (Drumlin ENG10 4→16)."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-09T18:44:17.964Z
---

**RESOLVED 2026-09-09.** Root cause was NOT the TVFs — it was the `FactEnrollment.ActiveFlag`
bug (see [[project_assessment_platform]] deployment state / the 2026-09-09 archive entry). PowerSchool
always fills `DateLeft` with the scheduled term-end, so the old `usp_MergeEnrollment` ActiveFlag logic
marked EVERY enrollment inactive. Its Step 2 only re-resolves an enrollment's `SectionKey` to the
current `DimSection` version when the row is active, else it FREEZES the key — so with everything
"inactive," every `SectionKey` froze, and when a section re-versioned (EnrollmentCount churn), the
enrollments stranded on stale versions → the roster (which joins the current version) under-counted.
Fixing ActiveFlag + re-running the merge re-resolved them: **Drumlin ENG10 141513 4→16, 141512 0→18.**
No TVF change needed. Original symptom below for history.

Concrete reproduction (original): **Drumlin's English 10 section on live showed 4 students; should be ~16.**

Where to look (all in the section path of tvf_TeacherGroups / tvf_TeacherRoster*, and the enrollment
model): the enrollment→section join (`FactEnrollment.SectionKey = DimSection.SectionKey`), the
effective-date filters on DimSection / FactEnrollment / FactSectionTeachers (an SCD version whose
window doesn't overlap the cycle would silently drop enrolments), the window overlap predicate
(`e.StartDate <= WindowEndDate AND (e.EndDate IS NULL OR e.EndDate >= WindowStartDate)`), and whether
the ingest is even landing all section enrolments for HS. Could share a root cause with the
"fragmented sections" symptom (many sections, few students each).

Constraint: this is LIVE, so per the live-PII boundary do NOT run row-level student queries against
live — diagnose on schema + synthetic (dev), and use aggregate counts only if querying live. Seed dev
with a comparable HS section first if dev lacks one.

Chase this alongside [[project_group_display_redesign]] next session.
