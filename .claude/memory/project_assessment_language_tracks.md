---
name: project_assessment_language_tracks
description: "Dual-language literacy is CONFIG-DRIVEN via cycle INSTANCES (shipped 0.5.0) — reading scale/language and who's assessed come from the instance a student's program-scope+grade lands them in, NEVER a hardcoded per-student rule. Claude keeps relapsing into hardcoding; do NOT."
metadata:
  node_type: memory
  type: project
  originSessionId: 41a845c2-822d-46c3-bb5a-20d4a608b8a9
  modified: 2026-10-16T20:07:50.276Z
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

**Write path aligned 2026-10-06:** the reads were config-driven since 2026-09-18 but the WRITE proc was left
behind — `usp_UpsertReadingAssessment`'s **51014** scale check still hardcoded family→scale (FI→FR_Reading),
so a late-immersion student was BLOCKED from saving an English reading level even though the roster correctly
showed EN_Reading (display right, save rejected). Fixed to validate against the cycle instance:
`@ExpectedScaleSystem = COALESCE(@WindowScaleSystem, program-family fallback)`, mirroring the roster. Decided
NOT to add a ProgramScope write-guard (roster is the sole feeder + already filters it; re-deriving the
scope-bucket logic in the proc would be a second source of truth that can drift — grade net 51016 stays
because it's a trivial scalar). SQL-only (no app change); redeploy the proc dev→live.

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

## Dual-language READING — it IS supported in the data (corrected 2026-10-16; was mis-noted as "single-language")
Reading language is per result via `FactAssessmentReading.ReadingScaleID → DimReadingScale.ScaleSystem`
(EN_Reading/FR_Reading — the scale IS the language; there is NO AssessmentLanguage column on the reading
fact, unlike writing). **A reading result's scale is the one the ENTRY INSTANCE/WINDOW carries.** Entry is
course-scoped (the group picker routes a section to its cycle instance), and `usp_UpsertReadingAssessment`
validates the saved scale against that instance's `ScaleSystem` (51014). So when a cycle has BOTH an
`EN_Reading` and an `FR_Reading` instance, a student in both an ELA and an FLA section is entered in both
windows and gets **two reading results — one EN, one FR.** Dual-language reading therefore EXISTS at the
data level with no entry-side work (user, 2026-10-16); it's just not yet common practice.
- The old "single-language per student" claim was WRONG / conditional: it only holds for a cycle that has
  NO language-scoped reading instance, where the roster falls back to `COALESCE(window.ScaleSystem,
  per-student family)`. With the reconciled instance set (separate EN/FR reading windows), the scale does
  track the section's language through the chosen window.
- **The gap being fixed in the 1.3.0 reports rebuild:** the cohort read `tvf_StudentCohort` collapses a
  student's reading to ONE latest row (`PARTITION BY StudentNumber` only), silently dropping the other
  language. The new oversight roll-up TVF (`tvf_StudentCohortReadingAll`) derives language per result from
  `ScaleSystem` and keeps per-(StudentNumber, ScaleSystem) rows, so distinct-student vs results-per-language
  counting works. Writing already carries `AssessmentLanguage` on its fact; reading derives it from the scale.
- Possible companion (see [[project_math_split_pacing_model]] self-containment ethos): freeze `ScaleSystem`
  directly on `FactAssessmentReading` for clean export, rather than resolving via ReadingScaleID.

Related: [[project_prelaunch_queue]], [[project_reading_scale_design]].
