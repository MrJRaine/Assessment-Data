# Surrogate-Key Stranding Sweep

*Read-only static analysis of the Fabric Warehouse T-SQL surface. 2026-10-13. No code changed; nothing executed against any warehouse.*

## The pattern being hunted

The SCD Type 2 dimensions (`DimStudent`, `DimSection`, `DimStaff`) mint a **new surrogate key**
(`StudentKey` / `SectionKey` / `StaffKey`) every time a row re-versions, while the **business key**
(`StudentNumber`, `SectionID`, `Email`) is stable forever. Fact/bridge rows get their surrogate links
*re-pointed to the current version* on each ingest for **active** rows, but **frozen** for closed/inactive
rows. The recurring defect is any **read or rebuild that links a *current* entity to data by a *mutable
surrogate key*** — or that **resolves one side at a past effective date while the other is re-pointed to
current**. When the dimension re-versions the two sides stop matching and rows "strand" (roster/results/
status go missing or reset). This has bitten three times already (all now fixed — see the reference section).

A second, closely related shape appears in the **data-entry card layer**: a window's sections are resolved to
the single `DimSection` version *in force on the window `EndDate`*, then joined to `FactEnrollment` **by that
version's `SectionKey`**. For a *closed* window that past-date pick no longer equals the current `SectionKey`
that live enrolment is re-pointed to — this is exactly bug #2, and it is **still present in the card TVFs**
even though the roster body was fixed on 2026-10-13.

---

## Summary table

| # | Location (file · object) | Surrogate key | What re-versions | Can it strand? | Severity | Stable-key fix |
|---|---|---|---|---|---|---|
| A | `tvf_TeacherGroups` (VisibleSections→SectionStudents) · `tvf_UserAssessmentWindows` (TeacherStudents / AdminStudents) | `SectionKey` (via as-of-`EndDate` section pick) | `DimSection` (EnrollmentCount / teacher churn) | **Yes** | **High** | Resolve section to **current** version; match `FactEnrollment` by stable **`SectionID`** across all versions (mirror the 2026-10-13 roster fix) |
| B | `usp_RebuildRosterMembership` step 2 · `tvf_TeacherRoster` / `…Writing` / `…Math` · `tvf_TeacherGroups` (Taught) · `tvf_UserAssessmentWindows` | *(none — `FactSectionTeachers` is business-keyed)* but teacher resolved **as-of window `EndDate`** | `FactSectionTeachers` (teacher reassignment) | **Yes** | **High** | Gate teacher membership on the **current** assignment (`fst.IsCurrent = 1`) by stable `SectionID` + `Email`, not the past-date `BETWEEN` *(product call: see finding)* |
| C | `usp_MergeStudent` step 6a–6d · `usp_UpsertStudentIPP` / `…Adaptation` · 15 IPP/Adaptation read objects | `StudentKey` on `FactStudentIPP` / `FactStudentAdaptation` | `DimStudent` (any of 14 fields) | **Likely** (status **reset**, not blank read) | **High / Med** | Carry **`StudentNumber`** on both facts; key the reconcile + upserts + reads on `StudentNumber` (mirror the assessment-fact fix) |
| D | Legacy Power Apps `vw_*` (`vw_StudentCohort`, `vw_StudentAssessmentHistory`, `vw_TeacherRoster`, `vw_TeacherGroups`, `bridge_views`, `vw_StudentIPP`, `vw_StudentCohortTeachers`) | `StudentKey` / `SectionKey` | all of the above | **No** (unused by web app) | **Low** | Convert or delete before any reuse — they still carry bug #1 and the as-of-date patterns |
| — | `FactAssessmentReading/Writing/Math` reads | `StudentKey` → now `StudentNumber` | `DimStudent` | **Already fixed** 2026-10-13 | — | done |
| — | `usp_RebuildRosterMembership` base (section axis) | `SectionKey` → now `SectionID` | `DimSection` | **Already fixed** 2026-10-13 | — | done |
| — | `FactEnrollment.ActiveFlag` freeze | `SectionKey` | `DimSection` | **Already fixed** 2026-09-09 | — | done |

---

## OPEN findings (most severe first)

### Finding A — Closed-cycle entry cards strand students on a stale `SectionKey` (the un-fixed half of bug #2) — HIGH

The 2026-10-13 section-stable fix was applied to the roster **body** (`SectionRosterMembership` via
`usp_RebuildRosterMembership`) but **not** to the two TVFs that build the data-entry **cards and counts**.
Both still resolve a window's sections to the `DimSection` version in force on the window `EndDate` and then
join `FactEnrollment` by *that version's* `SectionKey`.

**`sql/security/tvf_TeacherGroups.sql`** — `VisibleSections` picks the as-of-`EndDate` section version:

```sql
-- line 104-106 (Taught) / 124-126 (Oversight)
INNER JOIN DimSection sec
        ON sec.SectionID = fst.SectionID
       AND win.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
```

…and `SectionStudents` then joins enrolment by that frozen key:

```sql
-- line 156-159
INNER JOIN FactEnrollment e
        ON e.SectionKey  = vs.SectionKey
       AND e.StartDate  <= win.WindowEndDate
       AND (e.EndDate IS NULL OR e.EndDate >= win.WindowStartDate)
```

Here `win.EffectiveDate = CASE WHEN Today > EndDate THEN EndDate ELSE Today END` (line 84) — i.e. the window
`EndDate` for any closed cycle.

**`sql/security/tvf_UserAssessmentWindows.sql`** — same shape in both `TeacherStudents` (lines 87-91) and
`AdminStudents` (lines 126-135):

```sql
-- line 87-91
INNER JOIN DimSection sec
        ON sec.SectionID = fst.SectionID
       AND wed.EffectiveDate BETWEEN sec.EffectiveStartDate AND COALESCE(sec.EffectiveEndDate, '9999-12-31')
INNER JOIN FactEnrollment e
        ON e.SectionKey  = sec.SectionKey
       AND e.StartDate  <= wed.EndDate
       AND (e.EndDate IS NULL OR e.EndDate >= wed.StartDate)
```

**Stranding scenario.** SCoR-1 (Reading) closes Nov 30. Through December a section's `EnrollmentCount` shifts
on the PS export, so `DimSection` re-versions → new `SectionKey`; `usp_MergeEnrollment` re-points the section's
**active** enrolments to that new current `SectionKey`. When a teacher (or admin) later opens the closed SCoR-1
cycle in the grace period or to review, `win.EffectiveDate = Nov 30` resolves the section to its *old* version,
whose `SectionKey` no longer matches the re-pointed enrolments → the card's `ApplicableStudentCount` /
`EnteredStudentCount` / `DoneStudentCount` under-count, and in `tvf_TeacherGroups` a section whose students all
strand drops out of `SectionStudents` entirely so **the group card disappears**. This is the identical symptom
(CHES SC1 "1 of 18") that the roster-body fix was deployed to kill — it still lives in the card layer. The gap
widens as a cycle ages (more re-versions accumulate after its `EndDate`).

**Fix.** Mirror the `usp_RebuildRosterMembership` 2026-10-13 change into both TVFs: take the section from its
**current** version (`sec.IsCurrent = 1`) and match `FactEnrollment` by the stable **`SectionID`** across all
section versions (window-date overlap unchanged), rather than resolving the section at `EndDate` and joining by
`SectionKey`. Reuse the exact subquery from the rebuild proc so the card counts and the roster body stay in
lockstep.

---

### Finding B — Teacher resolved as-of the window `EndDate`; a teacher reassigned after a cycle closes strands off that cycle (teacher axis — the SUSPECTED one, CONFIRMED) — HIGH

`FactSectionTeachers` is correctly business-keyed (`SectionID`, `TeacherEmail`), so this is **not** a mutable-
surrogate join — it is the *effective-date* variant of the same family: the teacher membership is resolved **as
of the window `EndDate`** for closed cycles, while sections/students are (now) resolved current. The teacher
predicate is identical across the roster/card surface:

```sql
-- tvf_TeacherRoster.sql:105-109 (StudentGroups access predicate)
OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
           WHERE fst.SectionID = m.SectionID
             AND LOWER(fst.TeacherEmail) = c.Email
             AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                           AND COALESCE(fst.EffectiveEndDate, '9999-12-31'))
```

`m.WindowEffectiveDate` is `MIN(rebuild day, window EndDate)` (`SectionRosterMembership` column, written by
`usp_RebuildRosterMembership` line 74) = the window `EndDate` for a closed cycle. Same predicate at:

- `sql/procedures/usp_RebuildRosterMembership.sql:140` — step 2 builds `TeacherRosterMembership` (the fast-path
  table read by `tvf_TeacherRosterOwn`), so the strand is baked into the materialized teacher table.
- `sql/security/tvf_TeacherRoster.sql:108`
- `sql/security/tvf_TeacherRosterWriting.sql:77`
- `sql/security/tvf_TeacherRosterMath.sql:86`
- `sql/security/tvf_TeacherGroups.sql:103` (Taught scope — `win.EffectiveDate BETWEEN fst…`)
- `sql/security/tvf_UserAssessmentWindows.sql:86` (`TeacherStudents` — `wed.EffectiveDate BETWEEN fst…`)

**Stranding scenario.** Teacher B takes over Section X from Teacher A on Jan 15. SCoR-1 (Reading) closed Nov 30.
`FactSectionTeachers`: A `[Sep 1 – Jan 14]`, B `[Jan 15 – open]`. For the closed cycle,
`WindowEffectiveDate = Nov 30`; `Nov 30` is **not** between `Jan 15` and open → **Teacher B (the current teacher)
cannot see or enter the SCoR-1 card for Section X**, while Teacher A (departed) keeps it. If the intent — per the
roster fix's own rationale ("the teacher may still have paper results to enter") — is that the current teacher can
finish a closed cycle, this is a stranding. The reverse (A keeps a cycle they taught) may be desirable, so the two
directions are a product decision.

**Fix.** Gate the teacher predicate on the **current** assignment (`fst.IsCurrent = 1` / `EffectiveEndDate IS NULL`)
matched by the already-stable `SectionID` + `Email`, instead of the past-date `BETWEEN`. If both "current teacher"
and "teacher during the cycle" should see the card, use the union of `fst.IsCurrent = 1` **OR** the as-of-`EndDate`
range. This is a **scope/methodology call for the user** (who should own a closed cycle's roster) — surface it, do
not pick unilaterally. Whatever is chosen, apply it identically to `usp_RebuildRosterMembership` step 2 so the
fast-path table and the live TVFs agree.

---

### Finding C — IPP / Adaptation keyed on the mutable `StudentKey`: resolved status silently **resets** on student re-version — HIGH / MED

`FactStudentIPP` and `FactStudentAdaptation` store only `StudentKey` (no `StudentNumber` — see
`sql/facts/FactStudentIPP.sql:56-67`, `FactStudentAdaptation.sql`). The project fact-SCD memory left these "out of
scope, revisit only if they ever strand." They do **not** blank-out a read (the merge re-homes current rows to the
new key in the same run), but the **reconcile keyed on `StudentKey` destroys the teacher-entered value** on every
re-version.

`sql/procedures/usp_MergeStudent.sql` builds `ExpectedIPP` from the **current** `DimStudent` (new `StudentKey`)
and then:

```sql
-- step 6a (lines 385-396): close any current IPP row whose triple is "no longer expected"
UPDATE fsi SET EffectiveEndDate = DATEADD(DAY,-1,@EffectiveDate), IsCurrent = 0 …
FROM FactStudentIPP fsi
WHERE fsi.IsCurrent = 1
  AND NOT EXISTS (SELECT 1 FROM ExpectedIPP e
                  WHERE e.StudentKey = fsi.StudentKey AND e.Subject = fsi.Subject
                    AND e.ProgramFamily = fsi.ProgramFamily);
-- step 6b (lines 453-467): insert the expected triples lacking a current row, IsIPP = NULL
```

**Scenario.** A student with a resolved `FactStudentIPP (StudentKey=100, Reading, English, IsIPP=1)` re-versions on
an ingest (grade / school / homeroom / program / name — any of the 14 Type-2 fields). Steps 2–3 mint
`StudentKey=200`. `ExpectedIPP` now holds `(200, Reading, English)`; the existing `(100, …)` row is **not** in it →
step 6a closes it; step 6b inserts a fresh `(200, Reading, English, IsIPP = NULL)`. The confirmed `IsIPP = 1` is
gone; the current row is back to the **unresolved NULL gate**. Identical logic for Adaptations in steps 6c/6d
(lines 523-534, 590-604). Downstream this silently flips:

- `tvf_StudentCohort` → `IPPStatus_Reading = 'Unresolved'`, `IsChartEligibleReading = 0` (student drops out of charts/aggregates).
- `tvf_StudentCohortRWM` `AnyIPP` (line 215) → a previously IPP-excluded student **re-enters** the RWM benchmark cohort.
- The entry roster re-shows the "Confirmation Required" gate (`ReadingIPPNeedsConfirmation` etc.), forcing the teacher to re-confirm.

The reads themselves all match current-student↔current-fact on `StudentKey`, so they are consistent **at rest**
(not blank) — the harm is the reset, not a missing row. Read sites that would also need to move to `StudentNumber`
if the facts carry it (all join IPP/Adaptation by `StudentKey`):

`tvf_StudentIPP.sql:40` · `tvf_StudentAdaptation.sql:45` · `tvf_StudentCohort.sql:126-127` ·
`tvf_StudentCohortWriting.sql:119-121` · `tvf_StudentCohortMath.sql:125` · `tvf_StudentCohortMathAll.sql:90` ·
`tvf_StudentCohortRWM.sql:215` · `tvf_StudentAssessmentHistory.sql:89-90` · `tvf_StudentAssessmentHistoryWriting.sql:94` ·
`tvf_ProgrammingGroups.sql:49,53-54` · `tvf_ProgrammingRoster.sql:45-46,107,110` · `tvf_TeacherRoster.sql:201-209` ·
`tvf_TeacherRosterOwn.sql:139-147` · `tvf_TeacherRosterWriting.sql:154-158` · `tvf_TeacherRosterMath.sql:144-148`.
Also the upsert procs `usp_UpsertStudentIPP.sql` / `usp_UpsertStudentAdaptation.sql` operate entirely by
`@StudentKey`.

**Fix.** The decisive change is in the **merge + upserts**, not the reads: add `StudentNumber BIGINT` to both facts
(as was done for the assessment facts), key the reconcile (6a–6d) and the upserts on `StudentNumber` so a re-version
carries the resolved value forward instead of closing-and-recreating a NULL, and switch the reads to match
current student ↔ fact on `StudentNumber`. (Switching only the reads would not help — the merge would still have
reset the value to NULL.)

*Uncertainty flagged:* I did not execute anything, so I cannot measure how often students re-version in practice.
The reset is driven by any Type-2 field change; grade/homeroom/program moves make it routine over a school year.
The claim "reads don't strand" rests on the merge re-homing current IPP rows to the new `StudentKey` in the same
run — true for every re-version path in `usp_MergeStudent` (steps 2b/2c preserve `StudentKey`; only steps 2+3 mint
a new one, and step 6 always follows in the same proc).

---

### Finding D — Legacy Power Apps `vw_*` still carry bug #1 and the as-of-date patterns (latent, unused) — LOW

The pre-web-app Power Apps views were deliberately **not** converted (the web app reads the `tvf_*` / bridge
surface; see `project_assessment_fact_scd_policy`). They still join assessment facts to the current student by
`StudentKey` (the original bug #1) and resolve sections/teachers as-of a past date:

`vw_StudentCohort.sql:141` (`lr.StudentKey = s.StudentKey`) · `vw_StudentAssessmentHistory.sql:92` ·
`bridge_views.sql:181,355,543` · `vw_TeacherRoster.sql:240` · `vw_TeacherGroups.sql:113,250` ·
`vw_StudentIPP.sql:70` · `vw_StudentCohortTeachers.sql:56`.

Not an active defect while nothing reads them. Flagged so they are converted or dropped before any reuse, not
resurrected as-is.

---

## Already fixed (for reference — do not re-report as open)

1. **Assessment facts stored only `StudentKey`** → current-state reads missed pre-re-version rows. Fixed
   2026-10-13: `StudentNumber` added to `FactAssessmentReading/Writing/Math`; the 15 read objects now match the
   current student by `StudentNumber`. (`project_assessment_fact_scd_policy`,
   `sql/deploy/live_1.2.0/deploy_studentnumber_durable_fix_2026-10-13.sql`.)
2. **`usp_RebuildRosterMembership` resolved sections as-of the window `EndDate` and joined enrolment by that
   version's `SectionKey`** → closed-cycle rosters collapsed. Fixed 2026-10-13 (base/section axis): sections now
   resolve to the current version and enrolment matches by stable `SectionID`. (`project_roster_materialization`,
   `sql/deploy/live_1.2.0/deploy_rostermembership_section_stable_2026-10-13.sql`.) **Note:** the teacher axis of the
   same proc is **not** fixed — see Finding B; and the card TVFs that duplicate the old section logic are **not**
   fixed — see Finding A.
3. **`FactEnrollment.ActiveFlag` froze every `SectionKey`** (PS always fills `DateLeft`), stranding re-versioned
   sections. Fixed 2026-09-09 in `usp_MergeEnrollment`'s ActiveFlag compute. (`project_section_undercapture_bug`.)

## Not findings (verified consistent)

- **`usp_MergeEnrollment`** re-points `StudentKey`/`SectionKey` while active, freezes when closed (deliberate Type-1
  policy); the current-roster teacher/enrolment access gates (`e.ActiveFlag = 1`, `sec.IsCurrent = 1`,
  `s.IsCurrent = 1`) are all current-to-current.
- **`usp_MergeStaff` / `FactStaffAssignment`** self-heal across a `StaffKey` re-version (step 5b closes the old-key
  row, 5c re-inserts under the new key); `StaffSchoolAccess` is rebuilt from current `DimStaff`.
- **`usp_MergeSectionTeachers` / `FactSectionTeachers`** key on business keys only — no surrogate dependency.
- **Assessment upserts** (`usp_UpsertReadingAssessment` etc.) resolve `StudentKey` at insert via an effective-date
  join on `StudentNumber` + `AssessmentDate` and persist `StudentNumber` — correct point-in-time freeze.
