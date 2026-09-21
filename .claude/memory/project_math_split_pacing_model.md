---
name: project_math_split_pacing_model
description: Split-grade math pacing + task carry-forward linking — design talk-through 2026-09-21. Default month on task + SCD composition exceptions; carry-forward via edge links with per-record provenance; DimHomeroom SCD from ingest. Structural footprint agreed; NOT yet built. One open item (link SCD).
metadata:
  type: project
---

Design worked through with the user 2026-09-21 (talk-through; nothing built). Sits under
[[project_math_assessment_model]]; the split-pacing + carry-forward lines in [[project_prelaunch_queue]]
point here. GOAL: get the DB STRUCTURE right now (before large data volume needs migrating) so the actual
features are later just TVF/USP + client, per the user. The leadership GUI + resolution logic are post-1.0.

## Split-grade pacing

**Problem.** A math task has a fixed grade level, but *when* a student meets it (which SCoR) depends on the
**homeroom composition**: a grade-2 task is tackled in SCoR 2 for a straight-2 or 1/2 split, but not until
SCoR 3 in a 2/3 split. PowerSchool has NO split-grade flag — the only signal is the grade set in the homeroom.

**Placement grain = MONTH. Established design, not up for debate.** Tasks bin by month
(`DimMathTask.AssessmentMonth`) to coincide with the benchmark; SCoR is derived by matching that month to
the cycle's dominant month. Guides are *authored* in school-year weeks and translated to month — that
translation is the existing design (do NOT store weeks; do NOT store a SCoR slot).

**Multiple units per SCoR** (confirmed vs the SCoR-1 sheet). `UnitOrder` sorts UNITS within the SCoR;
`DisplayOrder` sorts TASKS within a unit (verified in MathRosterEntry.tsx). Both display-only — never keys.

**Model = default + exceptions (deviations only).** The task keeps its default month on `DimMathTask`
(unchanged). A separate **`MathTaskPacingException`** holds only deviations. Resolution:
`effectiveMonth(task, composition) = COALESCE(exception override, task default)`; the grid shows tasks whose
effectiveMonth = the open cycle's dominant month. One resolved value gives omit-from-old AND add-to-new for
free, so the exception NEVER stores the task's normal month → no sync coupling (editing a default month
touches no exception rows).

**Composition = `DimHomeroomComposition` (Option C encoding).** A tiny catalog: `CompositionKey` PK,
`CompositionGrades VARCHAR` = a **canonical grade-ORDER enumerated string** (e.g. `"P,1"`, `"1,3"`), UNIQUE,
+ optional `DisplayName`. Enumerated (not a range/pair-label) so non-contiguous edge cases like grades 1 & 3
with no 2 are exact. Ordering just makes it a single unique string to match whole (not filter grade-by-grade);
grade-order (P first, via `DimGrade.GradeOrder`) is readability. GUI: dropdown of known configs from the Dim
+ a reveal-on-"new" multiselect that builds a new canonical string / Dim row. Exceptions FK to `CompositionKey`.

**`MathTaskPacingException` = SCD Type 2** (user, 2026-09-21). Version PK, `MathTaskKey` FK, `CompositionKey`
FK, `OverrideMonth INT`, `EffectiveStartDate/EndDate`, `IsCurrent`; natural key `(MathTaskKey, CompositionKey)`.
WHY SCD: pacing guides / cycle dates change across years; without versioning, editing an override month would
retro-change the historical context of past cycles. Clean SCD because nothing FKs an exception row (facts/links
reference `MathTaskKey`), so Type 2 breaks no keys — unlike `DimMathTask`. Exception grain is per-task rows
(a whole-unit move = one exception row per task in the unit). Resolution: live reads `IsCurrent=1`, history by
effective date.

**Fallback (no guide) = the student's straight-grade default.** No matching exception row → falls through to
the task default. Not special-cased; "no exception" IS the fallback. Triples (1/2/3) and any unauthored combo
land here. Per [[feedback_never_silently_omit]] the UI must SHOW a "no split guide — straight-grade pacing" note.

**Roster grouping / homeroom identity (RESOLVED).** Homeroom is `DimStudent.Homeroom` (a FIELD, PS `Home_Room`),
already selected by tvf_TeacherRosterMath, and it IS Type-2 tracked in `DimStudent` (all business attrs version;
verified DimStudent.sql). So a mid-year composition change (e.g. the 1,2,3 class whose two grade-3s leave → ends
as 1,2) is preserved at the source and reconstructs as-of-date. The P-6 math roster is a post-1.0 TVF change:
scope to teachers of approved math courses (governed by `DimCourseAssessment`) → their students → bin by the
homeroom field. Composition is the FULL homeroom membership (not just the course roster).

**`DimHomeroom` = SCD Type 2, built in the INGEST script (user chose Option 2, 2026-09-21).** Materializes each
homeroom's composition with effective dates, rebuilt/versioned every ingest from `DimStudent` so it can't drift;
the same step upserts new composition strings into `DimHomeroomComposition`. **Natural key = `(SchoolID, Homeroom)`**
— school-qualified so identically-named homerooms across schools don't collide (matches the existing school-qualified
`DimStudent.GroupKey`). ONE code path — live reads
`IsCurrent=1`, historical reads by effective date (rejected the current-only variant: it split the same question
across two code paths). It's a controlled denormalization for perf/consistency; because it's regenerated each
ingest it holds no precious volume, so it's a post-1.0 build, not a pre-deploy migration risk.

## Carry-forward / task linking

**`MathTaskLink` — explicit predecessor→successor links within a grade.** Edge-based (`PredecessorMathTaskKey`,
`SuccessorMathTaskKey`), which covers pairs, linear chains, and transitivity with no sequence column. Chains are
LINEAR (user). Links are authored via the post-1.0 GUI (picks live `MathTaskKey`s — moots any TaskCode-for-linking).

**Behaviour (TVF/client, post-1.0).** If a student succeeded on a predecessor, the successor's SCoR opens
**pre-filled met** and is written as a real `FactAssessmentMath` record on the teacher's FIRST save of that cycle
(persisted, teacher can override before saving). Transitivity is a **domino**: each cycle's first save materializes
the next link, so the resolver only ever reads the IMMEDIATE predecessor's saved result. Walk-back rule (user):
skip BLANK predecessors and keep walking back; the first NON-blank decides — a **1 pre-fills success**, a **0 stops
the walk and pre-fills nothing** (the most-recent 0 is standing evidence). Only success carries; failure never does.
IPP: an IPP predecessor also stops the chain; it's already the default for an IPP student's cells; an IPP student's
explicit success DOES carry. IPP is per-student in `FactStudentIPP` (Subject='Math'), not a fact value — verified.

## FactAssessmentMath provenance (self-containment)

**ALTER ADD** (the only change to a live-bound fact): `CarriedFromMathTaskKey BIGINT NULL`, `CarriedFromMonth INT
NULL` (source task + readable source month — carry LINEAGE, not derivable from this row), `OutcomeCode VARCHAR(20)
NULL` (frozen at entry). All null = directly assessed.
- WHY OutcomeCode: it lives on Type-1 `DimMathTask`, so a later outcome recode would retro-change what a past
  result was "for." Freezing it self-contains the row.
- NOT effective-month: **redundant** — the fact already carries `AssessmentWindowID`, and a window fixes the
  month/SCoR a result was recorded in (a cycle-date change next year mints a NEW window, never rewrites one). So a
  recorded result's month context is already immutable; do NOT add a month column (Claude proposed it, corrected).

**Governing principle (Claude ↔ user, 2026-09-21):** SCD/version the thing whose history has NO other home
(pacing exceptions; likely links). Don't version a DERIVATION of already-versioned data — EXCEPT the user chose to
materialize `DimHomeroom` as SCD anyway, for perf + single-path consistency, made safe by rebuilding it from
`DimStudent` each ingest. For a recorded result's own context, prefer freezing on the fact (window already covers
month; OutcomeCode frozen) over dimension SCD (which would break `DimMathTask`'s stable key).

## Pre-deploy structural footprint (additive; the "get it right before volume" batch)

1. `DimHomeroomComposition` — CompositionKey IDENTITY PK, `CompositionGrades VARCHAR(50)` UNIQUE, `DisplayName VARCHAR(100) NULL`, LastUpdated.
2. `MathTaskPacingException` (SCD T2) — PacingExceptionKey PK, MathTaskKey FK, CompositionKey FK, OverrideMonth INT, EffectiveStartDate/EndDate, IsCurrent, LastUpdated.
3. `MathTaskLink` — MathTaskLinkKey PK, PredecessorMathTaskKey, SuccessorMathTaskKey, LastUpdated. **SCD? = OPEN (below).**
4. `FactAssessmentMath` ALTER ADD `CarriedFromMathTaskKey`, `CarriedFromMonth`, `OutcomeCode` (separate migration; GO after ALTER — Fabric).

Post-1.0 (TVF/USP/client, no pre-deploy structure): pacing resolution, the carry-forward domino, the P-6 homeroom
re-grouping, `DimHomeroom` + its ingest step, the leadership GUI.

## OPEN (only one left)

- **`MathTaskLink` SCD?** By the governing principle, link *config* history has no other home → SCD Type 2 (pair as
  natural key + effective dates). Counter: per-record carry lineage is already frozen on the fact, so recorded
  results are safe regardless — only the link TOPOLOGY audit needs versioning. User has NOT decided.

## Verified facts (checked in code this session — don't re-assert to the user as findings)

- `DimStudent.Homeroom` exists and is a Type-2 SCD trigger (all business attrs version).
- Math IPP = per-student `FactStudentIPP` (Subject='Math'); `FactAssessmentMath.Result` is BIT 0/1 only.
- `DimMathTask` = SCD Type 1 (+ `ActiveFlag` soft-retire); MUST stay Type 1 (Type 2 mints a new `MathTaskKey`,
  breaking links/rollup/provenance).
- `usp_LoadMathTasks` seeds tasks from CSV (incremental, upsert on natural key); `OutcomeCode` already loaded.
