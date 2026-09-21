---
name: project_math_split_pacing_model
description: Split-grade math pacing design — default month on the task + composition exceptions resolved as effective-month; surrogate keys only; P-6 math roster by homeroom. Converged 2026-09-21, NOT yet built.
metadata:
  type: project
---

Design converged with the user 2026-09-21 (talk-through, nothing built yet). Sits under
[[project_math_assessment_model]]; the split-grade-pacing line in [[project_prelaunch_queue]] points here.

**Problem.** A math task has a fixed grade level, but *when* a student meets it (which SCoR) depends on
the **homeroom composition**: a grade-2 task is tackled in SCoR 2 for a straight-2 or 1/2 split, but not
until SCoR 3 in a 2/3 split. PowerSchool carries NO split-grade flag — the only signal is the set of
grades present in the homeroom section.

**Pacing is authored in WEEKS of the school year** (user 2026-09-21); we translate week → month → SCoR to
line tasks up with the cycle benchmark. So the *source* grain is the school-year week; month and SCoR are
both downstream derivations via the calendar. SCoR is always derived — do NOT store placement as a SCoR
slot. OPEN storage-grain decision (see below): store the WEEK (source-faithful/self-contained, derive
month & SCoR at read time via DimCalendar/window) vs keep translating to a stored MONTH (simpler, but
lossy/baked-in). Leaning store-the-week per the user's self-containment preference (cf. the self-contained
FactAssessment rows work). If we store week, the resolution below becomes effectiveWeek → window rather
than effectiveMonth → dominant month.

**Multiple units per SCoR** (confirmed against the user's SCoR-1 sheet). So `UnitOrder`/`DisplayOrder`
are within-cycle display sorts only — NEVER keys.

**The model — default + exceptions (deviations only):**
- The task keeps its **default month** right on `DimMathTask`, exactly as today ("contained like it is now").
- A thin **exceptions** table holds only deviations: its own `IDENTITY` PK, FK `MathTaskKey`, the
  composition, and an **override month**. Most tasks have zero exception rows.
- **Resolution:** `effectiveMonth(task, composition) = COALESCE(exception override for that composition,
  task default)`. The entry grid shows tasks whose effectiveMonth = the open cycle's dominant month.
- This single resolved value gives BOTH behaviours for free: omit-from-old-cycle (it no longer equals the
  old month) and add-to-new-cycle (it now equals the new one). So we **never store the task's "normal
  month"** in the exception → there is **no sync coupling**: editing a task's default month touches
  nothing in the exceptions table; non-excepted compositions follow the new default automatically.

**Fallback (no guide) = student's straight-grade default.** ~13 authored guides = 7 straight (P–6) + 6
adjacent pairs (P/1 … 5/6). Triples (1/2/3) and any unauthored combo are rare and get NO guide → they
match no exception → fall through to the default. The fallback is not special-cased; "no exception found"
IS the fallback. Per [[feedback_never_silently_omit]] the UI must SHOW a visible "no split guide —
straight-grade pacing" note so it's never a silent guess.

**Roster grouping.** P-6 math must group by **homeroom** (revert the section-first grouping for THAT
subject only) so the homeroom's grade-composition is computable. Composition = the set of distinct grades
in the homeroom section.

**Keys — surrogate only (project Rule #1).** month, unit, order, question label are all things the future
leadership GUI may edit, so none can be identity. `DimMathTask.MathTaskKey` (existing `IDENTITY`) is the
stable anchor; `FactAssessmentMath` references it, so any attribute can change without breaking a stored
result. Same discipline for the exceptions table and the coming carry-forward link table.

**Rollup is preserved throughout** because it is always the same `MathTaskKey` whether the student met the
task in its default cycle or an exception cycle — an exception changes *which cycle it shows in*, never
*which task it is*.

**OPEN (not yet decided):**
- **Placement storage grain — WEEK vs MONTH.** Guides authored in school-year weeks; store the week
  (source-faithful, derive month/SCoR via calendar) or keep translating to a stored month (simpler,
  lossy). Leaning week. Whichever we pick, the exception override is the SAME grain.
- **`TaskCode`** — a stable, immutable business code carried on the seed sheet so a sheet RELOAD matches by
  it, not by the mutable composite `(grade,month,unit,question)` the loader uses today. Protects reload once
  the GUI can edit attributes. Cheap to add now; user has NOT decided add-now vs defer-to-GUI.
- **Exception grain** — per-unit (whole unit moves together, fewer rows) vs per-task. Leaning unit; unconfirmed.
- **How the homeroom is identified in PS** — a section flagged homeroom vs a field on enrollment. Needed to
  compute composition. Unconfirmed.
- **0.5.0 scope** — ship split-pacing *behaviour* in 0.5.0, or lay down the framework tables now and
  implement resolution + the leadership GUI post-1.0? Undecided.
- Whether an exception is ever more than a clean MOVE (a task in two cycles for one composition, or added
  out-of-grade). User: "don't see a world" for multi-cycle, but wants cheap future-proofing — the
  row-based exception table already allows a second row, so it's future-proofed at ~zero cost.

**Post-1.0 GUI (user's plan).** Math leadership view/edit tasks, enable/disable them (`ActiveFlag` exists),
author composition exceptions (only the deviations), and link tasks to carry successful results forward —
that carry-forward/linking piece is the SIBLING table and the NEXT design discussion.
