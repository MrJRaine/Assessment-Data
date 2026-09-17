# Changelog

Version history for the Short Cycles of Response App (web app + Fabric warehouse
deploys to **data.tcrce.ca** / `Assessment_Warehouse`).

Format follows [Keep a Changelog](https://keepachangelog.com/); this project uses
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`, pre-1.0).
Each release lists the **web** changes shipped in the container and any **SQL**
that must be deployed to the live warehouse alongside it.

Entries before `0.3.0` are reconstructed retroactively — formal tracking starts
with `0.3.0`, so earlier detail is approximate.

## [Unreleased] — 0.5.0-dev

Staged on the `dev` branch, not yet released to live. Maintained as changes land (not just at
release). Headline: **Math P–6 task-based short cycles**, the **Programming (IPP + Adaptations)
makeover**, a redesigned **group picker**, and **maintenance mode**.

### Added
- **Math Short Cycles (Primary–grade 6).** Task-based binary mastery (can-do/not-yet per student per
  task); by-task proportion heatmap + by-student 4-tier achievement level; bilingual `DimMathTask`;
  data layer + entry matrix. (`tvf_TeacherRosterMath`, `usp_UpsertMathAssessment`, `DimMathTask`, …)
- **Programming (IPP + Adaptations) makeover.** `/ipp` → `/programming` (old path redirects). Two
  rosters (IPP, Adaptations) as a student × Reading|Writing|Math grid with an adaptive cell
  (No/Yes; FI grade-3+ literacy = No/FLA-Only/ELA-Only/Both; Math No/Yes). Non-teachers get a
  window-less card picker first; a per-cell "needs confirmation" cue + a red/yellow/green
  confirmation-progress chip on the picker and each roster.
  SQL: `FactStudentAdaptation`, `usp_UpsertStudentAdaptation`, `tvf_StudentAdaptation`,
  `tvf_ProgrammingGroups`, `tvf_ProgrammingRoster`, `usp_MergeStudent` Step-6 seeding.
- **Group picker redesign (shared by Data Entry + Programming).** `tvf_TeacherGroups` rewritten to
  two scopes — `Taught` (your own homerooms/sections via FactSectionTeachers, for any role — fixes a
  teaching-admin being dumped into the school-wide list) and `Oversight` (Homeroom / Section /
  **Grade** lenses over full P–RG). Grade-span-aware grade filter (split/combined classes surface
  under each of their grades). Filters persist for the tab session.
- **Maintenance mode.** Sysadmin can schedule a graceful lockout before an emergency container swap:
  `AppMaintenance` row + `usp_Set/ClearMaintenanceWindow`, `/api/status`, a staged countdown banner
  (warn → lock-after-next-save → full lock → quiet auto-save → "we'll be right back" overlay), a
  sysadmin `/admin/maintenance` page, and one-click Clear + sign-in on the lockdown screen.

### Changed
- **Roster `@GroupKey` resolution is lens-agnostic** — a student resolves by homeroom key OR (HS)
  section key OR a `GRADE:<SchoolID>:<Grade>` cohort key, so oversight cards resolve correctly.
- `/students` cohort filters now persist for the tab session.
- **App version footer now reads `package.json`** (single source; no drift), and the in-app
  "What's new" popup lists the current minor line **plus the previous one** (e.g. 0.5.x shows all
  0.5.x + 0.4.x).

### Fixed
- **Group card titles were missing the space** ("HomeroomPA", "Grade1"). Fabric's `+` operator
  trims a string literal's trailing space when concatenated with a real VARCHAR column
  (`'Grade ' + s.Grade` → `Grade1`); rebuilt the labels with `CONCAT(...)` in `tvf_TeacherGroups`
  and `tvf_ProgrammingGroups`. **Redeploy both TVFs.**
- **Grade-8 reading benchmarks** seeded (Grade-6-June carry-over) so grade-8 reading shows a
  delta/band. (`seed_DimReadingBenchmark_grade8.sql`; also shipped with v0.4.0.)
- **Capability-gated nav no longer needs a refresh on first load** — `getCallerCapabilities` retries
  the cold-pool transient server-side, and a caps error no longer flips the user to signed-out.

### SQL to deploy to live at the 0.5.0 release
Programming Phase 0 (`FactStudentAdaptation.sql` → `usp_MergeStudent.sql` →
`usp_UpsertStudentAdaptation.sql` → `tvf_StudentAdaptation.sql`), the group/roster TVFs
(`deploy_groupkey_tvfs.sql` + `tvf_ProgrammingGroups.sql` + `tvf_ProgrammingRoster.sql`),
maintenance (`AppMaintenance.sql` + `usp_Set/ClearMaintenanceWindow.sql`), then re-run
`grant_webapp_sp.sql`.

## [0.4.1] — 2026-09-11

### Added
- **Version footer + "What's new" popup.** The app version now shows right-aligned in a footer on
  every page; clicking it opens a plain-language popup of the changes in the current minor line (the
  `.0` release plus any hotfixes — e.g. all of `0.4.x`). Notes are curated for teachers, maintained
  in `webapp/src/lib/patchNotes.ts` (kept in sync with this changelog at each release).

### Fixed
- **"Diff from Prev Cycle" was blank on the first cycle of the year.** The point-to-point diff
  compares a student's current level to the immediately-preceding cycle; on the first cycle there
  is no in-year predecessor, so it now falls back to the prior-year anchor (Prev June) — the same
  starting point "Since June" measures from. On cycle 1 the two columns therefore read the same
  value, as intended; from cycle 2 on they diverge (cumulative vs point-to-point). Display-only
  fix in the reading roster — **no warehouse SQL change**.

## [0.4.0] — 2026-09-10

### Added
- **Prior-year "starting point" on the reading roster.** Each student's June (previous
  school year) reading level plus a **cumulative Δ since June** (levels gained/lost, by
  `DimReadingScale.LevelOrder`) now show in a "Since June" column, so teachers see where a
  student began and how far they've moved.

### SQL (deploy to warehouse before / with the container)
1. `sql/facts/PriorYearBaseline.sql` + `sql/scripts/load_prior_year_baseline.sql` — the
   2025-2026 baseline table + load (already on live from 2026-09-09).
2. `sql/security/vw_StudentReadingStartingPoint.sql` — the starting-point read
   (`COALESCE(latest prior-year FactAssessmentReading, PriorYearBaseline seed)`; auto-flips
   to in-system facts from Sept 2027).
3. `sql/security/tvf_TeacherRoster.sql` — returns `JuneReadingLevel` + `ReadingSinceJune`.

## [0.3.0] — 2026-09-08

First release under formal version tracking. Ships to the live container as
`assessment-webapp:0.3.0`.

### Fixed
- **Homerooms containing `/` returned 404 on their roster route.** PowerSchool
  homeroom names with a slash (e.g. `5/6`) put a `/` into the URL path; IIS blocks
  `%2F` (`allowDoubleEscaping=false`), so the roster page could not be reached.
  Root fix is a materialized, URL-safe group key rather than URL encoding.

### Added
- **`DimStudent.GroupKey`** — a school-qualified, slash-free group key
  (`<SchoolAbbrev>-<cleanedHomeroom>`) computed at ingest in `usp_MergeStudent`.
  Being school-qualified, it also resolves cross-school homeroom-name collisions.
  Cards and roster headers still display the real homeroom name + school; the key
  is used only in the URL.
- **Small-group roster filter** on the Reading and Writing roster pages (ported
  from dev): collapsible picker to narrow a large roster to a subset of students.
- **Collapsible school filter** on the choose-a-group screen for staff who span
  multiple schools (admins / regional analysts): filters the group cards by school,
  hidden for single-school teachers.

### SQL (deploy to LIVE warehouse before / with the container)
1. `sql/scripts/migrate_DimStudent_add_GroupKey.sql` — add `GroupKey` column + backfill.
2. `sql/procedures/usp_MergeStudent.sql` — compute `GroupKey` on every ingest.
3. `sql/scripts/deploy_groupkey_tvfs_live.sql` — group/roster TVFs read & match on `GroupKey`.

## [0.2.0] — 2026-09 (retroactive)

Prior live release. Detailed change history predates this changelog. Broadly, the
live platform at this point covered Reading + Writing short cycles on the monthly
cycle model, teacher/cohort/individual pages, ingest + SCD merge pipeline, and
user-facing wording moved from "window" to "cycle". (Math P–6 remains dev-only on
`feat/math-p6-entry` and is **not** in this line.)

## [0.1.0] — 2026-06 (retroactive)

Initial web-app baseline — Fabric warehouse connectivity proven via `mssql`/tedious 19
(tag `webapp-v0.1-tedious-baseline`).
