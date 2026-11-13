# 1.4.0 Testing Plan — items not yet signed off

Written 2026-11-12 (evening), for the 2026-11-13 morning test pass. Everything in the
Unreleased 1.4.0 release that has not had an explicit sign-off, with concrete checks.
(Renamed from 1.3.1 on 2026-11-13 — the Missing results report + filter sections are
new features, so this ships as a minor release.)
Test on **awdev-impersonation (127.0.0.1:3002)** for role switching; awdev (:3001) for
plain Entra behaviour.

## Preconditions (do these first)

- [x] Run on **Assessment_Warehouse_Dev**:
      [sql/scripts/deploy_summary_filter_demographics_2026-11-10.sql](../sql/scripts/deploy_summary_filter_demographics_2026-11-10.sql)
      — **rerun even if an earlier revision already ran** (now carries demographics +
      expected-language + lifetime-Current/IPP changes; idempotent).
- [x] Run on dev: [sql/scripts/deploy_missing_results_2026-11-12.sql](../sql/scripts/deploy_missing_results_2026-11-12.sql)
      (the Missing results page errors until this is in).
- [x] Containers up on the 1.4.0 images (`podman ps`: awdev-impersonation :3002 on
      `1.4.0-imp`, awdev :3001 on `1.4.0-dev`).

## 0. Version surfaces (verify before deployment)

- [x] Footer bottom-right reads **1.4.0** (no `-dev` suffix — user call 2026-11-13: the
      signed-off image IS the shipped artifact; at cutover it's retagged + tarred, never rebuilt).
      ✓ 2026-11-13
- [X] Clicking the footer version opens **What's New** showing the five 1.4.0 entries
      (Missing results · filter sections/Collapse all · charts follow filters ·
      Current = most recent on record + IPP exclusion · math entry names/sort), with the
      1.3.0 entries still listed below them (popup shows current + previous minor line).
      ✓ 2026-11-13, incl. the revised Missing-results wording.
- [X] [CHANGELOG.md](../CHANGELOG.md) Unreleased section is headed **1.4.0 candidate** and
      covers everything in this plan.

## 1. Missing results report (new — Admin/RA only)

- [X] **Visibility**: as Administrator and as Regional Analyst the "Missing results" tab
      shows on all report pages; as Teacher AND as Specialist Teacher it does not, and
      `/reports/missing` directly gives the 404 page.
- [X] **Cycle selector**: no "Current" chip — cycles only, with the newest started cycle
      preselected on first load.
- [X] **Tree shape**: TCRCE row (RA only) → schools → lead teachers → sections; opening a
      section lists the students still needing data, grouped per student with subject pills.
- [X] **Historic teacher attribution** (rev b, 2026-11-13 — rerun
      [deploy_missing_results_2026-11-12.sql](../sql/scripts/deploy_missing_results_2026-11-12.sql)
      first): a section lists under the Primary teacher it had DURING the selected cycle (most
      recent within the cycle on a handover, named even if since departed), never today's
      teacher. Dev has no natural handover — run
      [seed_teacher_handover_fixture_dev.sql](../sql/scripts/seed_teacher_handover_fixture_dev.sql)
      (self-reverts on the next dev ingest), then at school 0079: **ELA-45-EN** under
      Morgan Hazel on the Sep cycle but Rowan Aspen on the Nov cycle; **MAT-45-EN** under
      "No lead teacher" on every cycle (this doubles as the No-lead check below).
- [X] **Counts**: Reading / Writing / Math / Total columns; a student missing in two
      sections counts ONCE at teacher/school/TCRCE level; section rows count raw.
- [X] **% column + row colours** (by % REPORTED): <50% red · 50–74% yellow · 75–99% light
      green · 100% dark green. Spot-check one row's % against its counts.
      NOTE: ticked against the original "% missing" column; the displayed % FLIPPED to
      **% reported** (user call 2026-11-13, colours unchanged) — one re-glance after the
      next rebuild. % is per data point (student × subject), not per student: an ELA
      section fully done in Reading but not Writing sits at ~50%.
- [X] **IPP exclusion**: a student with a CONFIRMED IPP in a subject is not expected in that
      subject anywhere; a flagged-but-unconfirmed IPP still counts as expected.
      (Open design point: the exclusion is subject-only, not per-language — a confirmed
      Reading IPP removes Reading expectations in both languages. Say if that's wrong.)
- [X] **Math 80% rule**: a student with ≥80% of the grade's configured benchmark-month tasks
      recorded counts as reported; below that, missing. A grade with NO configured tasks for
      the cycle's math month contributes no math expectations at all.
- [X] **No lead teacher**: a section with NO Primary teacher on record for the cycle appears
      under a visible "No lead teacher" node (sorted last), never silently dropped. NOTE
      (ruled 2026-11-13): this is a DEFENSIVE surface — ingest can't produce a lead-less
      section (teacher-less sections don't ingest; FST rows close, never delete; mid-year
      sections ingest on their start day and have no earlier-cycle roster). Verified via the
      synthetic MAT-45-EN fixture.
- [X] A fully-complete section's drill says everyone has results, instead of an empty box.

## 2. "Current" = lifetime (Reading/Writing summary vs Student list)

- [ ] On **Current**, the summary donut's ASSESSED total **equals** the Student list
      donut's total (same filters). This was the original discrepancy.
- [ ] A student whose only result is from last school year shows that result on the summary
      tree/drill (with its Expected range), not "No data".
- [ ] Current chip tooltip reads "Each student's most recent result on record".
- [ ] With a specific cycle selected, summary and list still agree.

## 3. IPP students out of the achievement maths (summary trees)

- [ ] An IPP student's result shows in the drill with level/traits but **"IPP"** in the
      Achievement column and no Diff from Expected.
- [ ] They are absent from the donut count, the donut slices, the by-cycle bars, and the
      % Meeting/Exceeding — but still counted in the Students column.

## 4. Language of Assessment filter keeps expected-but-unassessed students

- [ ] Filter a summary tree to French: students expected in French with no French result
      stay in the grade/homeroom counts (as "no result") and appear in the drill as "—"
      rows. Same for English. % and Results counts unchanged by their presence.

## 5. Filter sections on the summary trees

- [ ] **Reading/Writing trees**: Show filters → Grade / Gender / Self-ID African / Self-ID
      Indigenous / Language; everything (node counts, charts, drills) trims together;
      Reset restores. Gender/Self-ID groups appear only after the SQL bundle runs.
- [ ] **RWM tree**: same section plus the two scoring toggles moved in — **Math blanks**
      (Excluded vs Count-as-0 re-scores the 0–3) and **All 3 areas only**. Reset leaves the
      Math-blanks mode alone (it's a scoring mode, not a filter).

## 6. Math name/display fixes

- [ ] **Entry grid**: student columns show first name over full last name (two lines),
      columns stay narrow, long names ellipsize with full name on hover; the picker chips
      and "can't be marked" notes use full names. Two classmates with the same first name +
      last initial are now distinguishable.
- [ ] **Sort**: math summary drill, class view, and entry grid order students by LAST name.
- [ ] **Math summary drill**: scrollbars are visible on screen when the student list
      overflows (previously rendered past the right edge).
- [ ] Math reports students-down views show "Last, First".

## 7. Earlier 1.4.0 items (if not already satisfied)

- [ ] Student-list view charts follow every filter chip (and language chip exists there).
- [ ] RWM colours = the standard four achievement colours everywhere in that report.
- [ ] "Collapse all" closes every open branch on Reading/Writing/Math trees.

## Known/parked

- Math report + RWM's math component remain current-year in Current mode (task×grade×month
  model — deliberate until ruled otherwise). RWM reading/writing were already lifetime.
- Missing-report IPP exclusion is subject-only (see §1) — flag if per-language wanted.
