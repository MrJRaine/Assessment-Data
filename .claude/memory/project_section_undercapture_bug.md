---
name: project_section_undercapture_bug
description: "OPEN BUG (found 2026-09-08, on LIVE) — high-school section cards appear to under-count enrolled students. Drumlin English 10 shows 4 students but should be ~15. Root-cause + fix next session."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-08T18:43:54.969Z
---

**Open bug, found 2026-09-08 on LIVE, not yet diagnosed.** Senior-high **section** groups appear
to be **missing students** — the section roster/count does not capture everyone enrolled.

Concrete reproduction: **Drumlin's English 10 section on live shows 4 students; it should be ~15.**

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
