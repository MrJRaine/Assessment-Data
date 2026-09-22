---
name: project_assessment_language_tracks
description: "Dual-language literacy is CONFIG-DRIVEN via cycle INSTANCES (shipped 0.5.0) — reading scale/language and who's assessed come from the instance a student's program-scope+grade lands them in, NEVER a hardcoded per-student rule. Claude keeps relapsing into hardcoding; do NOT."
metadata:
  type: project
---

## BINDING RULE — the instances are the levers. Do NOT hardcode.
Which grades / programs / languages are assessed how is configured at the **APP LEVEL as cycle
INSTANCES**, never hardcoded in a TVF/proc. Claude has relapsed into hardcoding this **many times**
(grade-3 threshold, "reading is single-language per student", `ProgramCode <> 'J020'`) and been corrected
each time — STOP. If the answer ever sounds like "the rule is FI→FR_Reading / J020→English," that is the
relapse. The rule is: **the student reads/writes in whichever INSTANCE their (program-scope bucket ×
grade) lands them in, and the instance's Language sets the scale.** See [[feedback_no_unilateral_scope_decisions]].

## What a CORRECT cycle looks like — dev SCoR 1 (user confirmed correct 2026-09-21)
A SCoR = a header (`DimShortCycle`) + a set of scoped **instances** (`DimAssessmentWindow` rows sharing
`CycleGroupID`). Each instance = **Subject × Language × ProgramScope × GradeBand**. Dev SCoR 1's instances:
- Writing · English · Late Immersion/Early Immersion · 7–RG
- Reading · English · Late Immersion · 7–8
- Writing · French · Late Immersion · 7–RG
- Writing · French · Early Immersion · P–RG
- Math · English/Late Immersion/Early Immersion · P–6
- Writing · English · English · P–RG
- Reading · French · Early Immersion · P–8
- Reading · English · English · P–8

Early immersion reads FRENCH because a `Reading·French·Early Immersion·P–8` instance EXISTS and scopes
them there — not because any code says "FI→French." Late immersion reads English via `Reading·English·
Late Immersion·7–8`. It's all instances.

## The config levers (set on /cycles → usp_UpsertShortCycle, stored on DimAssessmentWindow)
- `AssessmentLanguage` 'English' | 'French' | NULL(Both) — for reading, the instance's language SETS the scale.
- `ProgramScope` — multi-select of buckets {English, Early Immersion, Late Immersion} (`DimProgram.ScopeBucket`;
  non-immersion incl. FSL → English; FI name-'Late' → Late; other FI → Early). NULL = all.
- Grade band `MinGrade`/`MaxGrade`.
`tvf_TeacherRoster` HONORS the instance: membership filters on `ProgramScope` + `AssessmentLanguage`;
reading scale = `COALESCE(wed.ScaleSystem, <family fallback>)`. The family-fallback CASE fires ONLY when a
cycle has NO ScaleSystem — a properly-scoped reading instance never hits it. (The old `ProgramCode <> 'J020'`
hardcode was REMOVED 2026-09-18; config is the single source of truth.)

## Course-scoped ENTRY (shipped 0.5.0)
Entry language comes from the COURSE the teacher teaches, via `DimCourseAssessment` (ELA / Immersion-ELA →
English literacy; FLA → French; Math → Math). Group picker = the caller's mapped-course sections, grouped
under language headings, multi-select within ONE language. Oversight keeps broad scope over mapped-course
sections; above-teacher cards show the section teacher's name. Seeds: `seed_DimCourseAssessment_dev/live.sql`.

## The immersion-showing-English-reading issue (2026-09-21) — NOT a rule bug
The LIVE cycles don't yet have the correct instance structure (the dev SCoR-1 set). With no
`Reading·French·Early Immersion` instance, early-immersion students have no French reading instance to land
in, so they fall into the English reading instance (or the fallback CASE) and show English levels. **Fix =
build the correctly-scoped instances on live to match dev — never touch a "rule."** "Better way to migrate
cycles" = reproduce the dev instance set per live cycle instead of hand-rebuilding each on /cycles.

**RESOLVED 2026-09-22.** Live reconciled to the canonical 8 (`reconcile_cycle_instances.sql`). The SCoR-1
reading results immersion students had entered on the old generic (now Reading·English·English) window were
repointed to Reading·French·Early Immersion — `migrate_mislocated_immersion_reading.sql` (all 14 were
already `FR_Reading`, so a clean window repoint; 3 English results on that window were correct, left alone).
Also fixed the `/enter` oversight COUNT: the ADMIN + ANALYST branches of `tvf_UserAssessmentWindows` counted
straight off DimStudent by grade+scope (the 2026-09-18 rework course-scoped only the TEACHER branch), so an
oversight user's card overcounted (students with no literacy section) and read English-only. Now all three
branches resolve through mapped-course sections language-matched to the instance (like `tvf_TeacherGroups`),
and `EnteredStudentCount` counts a result on ANY instance of the cycle. Card == sum of the group cards.

## The one genuinely-structural fact
J020 (late immersion) has no French reading benchmarks yet, so it reads English — but that too is expressed
by ProgramScope (J020 is in the Late Immersion bucket), not by hardcoding its program code.

## FUTURE — dual-track reading cleanup (user flagged 2026-09-21; harmless now, fix before dual-track reading)
Reading is captured per result via `FactAssessmentReading.ReadingScaleID → DimReadingScale.ScaleSystem`
(EN_Reading/FR_Reading — the scale IS the language) + the instance's `AssessmentWindowID`. BUT the ROSTER
resolves the scale from the **window** (`COALESCE(window.ScaleSystem, per-student family fallback)`), **not
from the SECTION's course language.** So a student in BOTH an ELA and an FLA section sees the SAME reading
scale in both (whatever the window/family gives), even though the group-select page bins them into the
correct section by course language. Writing already routes by the section's language; reading does not.
- **Today it's cosmetic** — reading is effectively single-language per student, so the duplicate/same-scale
  view causes no wrong data.
- **To make reading dual-track:** route the reading result to the instance matching the SECTION'S course
  language (the way writing does), so an ELA section → `EN_Reading` and an FLA section → `FR_Reading`, and a
  student's English and French reading split into the two instances' windows. Reading already has NO grain
  collision (two windows), so this is roster-routing work, not a fact-schema change.
- Possible companion (see [[project_math_split_pacing_model]] self-containment ethos): freeze `ScaleSystem`
  directly on `FactAssessmentReading` for clean export, rather than resolving via ReadingScaleID.

Related: [[project_prelaunch_queue]], [[project_reading_scale_design]].
