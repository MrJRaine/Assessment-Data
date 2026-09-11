---
name: project_group_display_redesign
description: "DESIGN DECIDED 2026-09-08, NOT YET BUILT — how the Data Entry \"choose a group\" page should resolve groups per role (teacher vs above-teacher), incl. homeroom/section toggle, P-RG span, grade+school filters. Supersedes the current AccessLevel-only dispatch."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-08T18:43:41.981Z
---

**Redesign of the Data Entry "choose a group" screen (`/enter/[windowId]`, tvf_TeacherGroups
+ the roster TVFs). DECIDED 2026-09-08, not started — begin here next session.**

Root problem found this session: group resolution is a single **mutually-exclusive dispatch on
`AccessLevel`** (Teacher `IS NULL` → own sections; Administrator/SpecialistTeacher → whole-school
sections; RegionalAnalyst → region-wide sections). Current grade boundary: `GradeOrder <= 9` →
homeroom key, `>= 10` → `SEC:`+SectionID. Two consequences:
- A **dual-role user** (e.g. a VP who also teaches 50%) has `AccessLevel='Administrator'`, so they
  NEVER get the teacher branch — their own classes vanish into a school-wide "one card per every
  section any in-scope student sits in" dump, each card showing only the few overlapping students.
- 7/8/9 stay on the homeroom path and that is CORRECT — those grades are cohorted and travel
  class-to-class with their homerooms. Do NOT move the 7-9 boundary. The work is all about the
  senior-high (10-RG) section path and the role dispatch.

**Target behaviour:**

- **Teachers (`AccessLevel IS NULL`):** P-9 **Homerooms** they teach students in + **only the
  high-school sections they teach**. (Their own associations only — already true for the teacher
  branch; the fix is making dual-role users also get this.)

- **Above teacher (Administrator / SpecialistTeacher / RegionalAnalyst):** offer BOTH a **Homeroom
  view** and a **Section view** (a toggle), each spanning the full **P-RG** range — i.e. decouple
  homeroom-vs-section from grade (HS students have an admin homeroom too; show them in both lenses).
  Add a **grade filter on top of the existing school filter** on the page. So the above-teacher
  choose-a-group page = [Homeroom | Section] toggle + grade filter + school filter (the collapsible
  school filter shipped in v0.3.0 is the model to extend).

This refines the earlier "role toggle" framing: the toggle is **Homeroom view ⟷ Section view for
above-teacher roles**, not a "my classes / school oversight" switch. A dual-role person's *own
teaching* should surface via the teacher rule regardless of their admin AccessLevel.

**Deployment-state caveat:** the **live `/cycles` page cannot break cycles up by subject** (per-subject
grade ranges) — that form capability is **dev/feat-only, not deployed to live**. The live grade
splits (Reading P-8 / Writing P-RG / Math P-6) were applied by SQL
(`set_cycle_grade_ranges_by_subject.sql`), confirmed present on live 2026-09-08. Don't assume the
live UI can manage split cycles yet.

Implementation will touch tvf_TeacherGroups + tvf_TeacherRoster/Writing/Math (return both homeroom
and section resolutions, or a `viewAs`/mode param), plus the web group-select page (toggle + grade
filter). See [[project_section_undercapture_bug]] (must be fixed too — sections are under-counting)
and [[project_math_assessment_model]] (7-RG requirement origin). Grade boundary facts in
[[project_assessment_platform]].
