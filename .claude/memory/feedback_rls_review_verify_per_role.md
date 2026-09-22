---
name: feedback_rls_review_verify_per_role
description: "When reviewing or reasoning about RLS / access control, verify EACH role branch's scoping against the documented design across the WHOLE surface — never assert an access claim without checking, and never double down when challenged."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-22T14:08:03.272Z
---

A foundational RLS bug sat in the codebase through multiple security reviews and I missed it, then
gave the user a confident wrong answer and pushed back when challenged: **RegionalAnalyst was built
region-wide** (no `StaffSchoolAccess` gate) in every user-scoped TVF, contradicting the documented
design (`DimRole`: "board scope via StaffSchoolAccess"; `StaffSchoolAccess` is materialized from
`CanChangeSchool`). Any analyst could read all ~6000 students regardless of assigned schools.

**Why it happened:** I read one code path, treated "what the code does" as the intended design, and
didn't cross-check each role branch against `DimRole` / `StaffSchoolAccess`. When the user said it
should be scoped, I asked "are you sure?" instead of verifying. I also *assumed* a data-config
semantic (that the `'0'` marker meant "all schools") — it's actually just the regional-office
building code.

**How to apply:**
- For any RLS object (a view/TVF filtered by `@UPN`/`CURRENT_USER`), enumerate EVERY role branch
  (Teacher / Administrator / SpecialistTeacher / RegionalAnalyst) and confirm each one's scoping join
  matches the documented intent — build a role×scoping matrix, don't eyeball one branch. Do it across
  the WHOLE surface, not per-object; the same gap usually repeats in every consumer.
- A **region-wide / ungated branch is a red flag**: it must be justified against the design, not
  assumed correct because it runs and returns data.
- **Never assert an access-control claim without verifying it in the code AND against the design**
  (`DimRole`, `StaffSchoolAccess`, the RLS memory/skill). When the user challenges a security claim,
  RE-VERIFY immediately — treat a challenge as "go check," never as a prompt to defend.
- **Don't assume data-config semantics** (what a marker/code/flag means) — verify against how it's
  built/consumed, or ask. Verify the prerequisites a fix rests on (e.g. does `StaffSchoolAccess`
  actually contain rows for this role?) before editing.

The correct model (fixed 2026-09-22, `deploy_analyst_rls_scoping.sql`): RegionalAnalyst is
`StaffSchoolAccess`-gated exactly like Administrator/SpecialistTeacher; "sees everything" = every
building listed in their `CanChangeSchool`. See [[feedback_sql_write_authorization]] (I write, user
runs) and [[project_dev_live_environment_split]].
