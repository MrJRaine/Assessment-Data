# Changelog

Version history for the Short Cycles of Response App (web app + Fabric warehouse
deploys to **data.tcrce.ca** / `Assessment_Warehouse`).

Format follows [Keep a Changelog](https://keepachangelog.com/); this project uses
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`, pre-1.0).
Each release lists the **web** changes shipped in the container and any **SQL**
that must be deployed to the live warehouse alongside it.

Entries before `0.3.0` are reconstructed retroactively — formal tracking starts
with `0.3.0`, so earlier detail is approximate.

## [0.6.1] — 2026-09-23

### Fixed
- **Opening a class no longer hangs on live (streaming behind IIS).** Next's built-in gzip
  (`compress: true`, the default) buffers the response to compress it — an origin-side buffer
  *upstream* of IIS that defeated the roster Suspense streaming behind the reverse proxy: the loading
  shell never flushed, so a click looked like a dead hang before the whole page dropped in at once.
  `responseBufferLimit=0` and disabling IIS dynamic compression couldn't fix it because both are
  downstream of Next's own compression. Set **`compress: false`** in `next.config.ts` so streamed
  responses go out uncompressed + chunked and flush immediately. Web-only, ships as
  `assessment-webapp:0.6.1`. **Deploy note:** IIS **dynamic compression must stay OFF** and ARR
  `responseBufferLimit` must stay `0`, or IIS re-gzips/re-buffers the now-uncompressed HTML.

## [0.6.0] — 2026-09-22

The **French answer key** in Math Short Cycles, plus the security + data fixes that landed through the
session. Some SQL below was already deployed to live as it was fixed (noted per item); the container
ships as `assessment-webapp:0.6.0`.

### Changed
- Placeholder headers replaced. Web-only (`AppShell.tsx`, `page.tsx`, `layout.tsx`,
  `maintenance/MaintenanceProvider.tsx`).
- Programming loading text “Loading IPP cells” → “Loading cells…” (grid covers IPP + Adaptations).
  Web-only (`programming/loading.tsx`).

### Added
- **French answer key in Math Short Cycles.** For a French-Immersion section, the answer key now
  follows the task’s language: the FR answer key shows beside the FR task text
  (`COALESCE(AnswerKeyFR, AnswerKey)`), matching the existing task-description switch.
  **SQL to deploy with this release:** `sql/security/tvf_TeacherRosterMath.sql` (live + dev).
- **`AnswerKeyFR` on the math task bank** + `AnswerKey` widened to `VARCHAR(500)`. Lets the math team
  supply a separate French answer key per task. SQL already applied live + dev this session
  (`DimMathTask.sql`, `Stg_MathTask.sql`, `usp_LoadMathTasks.sql`,
  `sql/scripts/migrate_MathTask_add_AnswerKeyFR_live.sql`).

### Fixed
- **RegionalAnalyst access is now scoped by building, not region-wide (security).** The RegionalAnalyst
  role was reading across **every** school in all 13 user-scoped TVFs, contradicting the documented
  design — it must be gated by the analyst’s `StaffSchoolAccess` (their `CanChangeSchool` buildings),
  exactly like an Admin. Folded RegionalAnalyst into the `StaffSchoolAccess`-gated branch across all 13
  TVFs. **Already deployed live + dev** this session (`sql/scripts/deploy_analyst_rls_scoping.sql`).
- **Reading cycle cards counted English only.** The assessment-type cards on the data-entry picker
  counted just the English reading instance instead of all language instances of a cycle. Corrected the
  admin/analyst branches to be course-scoped and count entered-any-instance. **Already deployed live +
  dev** (`sql/security/tvf_UserAssessmentWindows.sql`).
- **14 immersion reading results** were sitting in the wrong assessment window; migrated to the
  French · Early-Immersion window. Data fix, applied live this session.

### Removed
- **Dev-only sysadmin impersonation** was stripped from `main` entirely (it never belonged on live).
  The full feature is preserved on the `dev-impersonation` branch for dev/awdev testing only.

## [0.5.1] — 2026-09-21

### Fixed
- **Opening a roster no longer looks like a dead click.** The group cards link to `force-dynamic`
  pages that are deliberately *not* prefetched (prefetching warmed the warehouse queries on every
  hover/scroll across ~200 teachers). The catch that shipped with that: without a prefetch, Next
  doesn't render `loading.tsx` on click, and the roster page `await`ed **every** roster query before
  returning any markup — so a click hung for a few seconds and then dropped the whole page in at once,
  training multi-clicks. The roster route now renders its shell (the Back link) + a “Loading roster…”
  fallback from an in-page `<Suspense>` boundary **immediately** and **streams** the roster in when its
  queries resolve, so the click gives instant feedback. No warehouse SQL — web-only
  (`enter/cycle/[cycleGroupId]/[subject]/[groupKey]/page.tsx`). Ships as `assessment-webapp:0.5.1`.

## [0.5.0] — 2026-09-21

Released to live 2026-09-21 (warehouse SQL + `assessment-webapp:0.5.0` container swap). Headline:
**Math P–6 task-based short cycles**, the **Programming (IPP + Adaptations) makeover**, a redesigned
**group picker**, **dual-language literacy + per-cycle scoping**, **Students → Reports**, and
**maintenance mode**.

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
- **Cycle header + scoped instances.** A Short Cycle is now a **header** (`DimShortCycle`: distinct key
  + display name + date range, set once) plus a list of **scoped instances** — each a
  `DimAssessmentWindow` row with its own Subject · Language · Program scope · grade band, all sharing
  the header's dates. The `/cycles` page is a two-part builder (create the cycle, then add instances);
  editing the header's dates re-propagates to every instance. Because results tie to the header's key
  (via the instance window → `CycleGroupID`), a repeated name like "SCoR 1" each year stays separate
  for roll-up. SQL: `DimShortCycle`, `usp_UpsertShortCycleHeader`, `backfill_DimShortCycle_headers.sql`.
- **Dual-language literacy + app-level cycle scoping.** Reading and writing can be assessed in English
  and/or French, and **which grades/programs/language a cycle covers is configured on `/cycles`** — not
  hardcoded. Each cycle carries a **program scope** (multi-select of English / Early Immersion / Late
  Immersion; non-immersion incl. FSL folds into English) + a **language** (Both / English / French) +
  the existing grade band. Writing "Both" cycles show an EN/FR toggle on the entry roster and store the
  language on the result (`FactAssessmentWriting.AssessmentLanguage`, so a student can hold an English
  and a French result per cycle); a language-scoped cycle fixes the language. Reading language is the
  cycle's (sets the scale). Only structural rule kept in code: French literacy = French Immersion
  (reading excludes **J020** late immersion — reads in English, no French reading benchmarks).
  SQL: `DimProgram.ScopeBucket`, `DimAssessmentWindow.AssessmentLanguage` + `ProgramScope`,
  `FactAssessmentWriting.AssessmentLanguage`, `usp_UpsertShortCycle`, `usp_UpsertWritingAssessment`,
  `tvf_TeacherRoster`, `tvf_TeacherRosterWriting`, `usp_MergeStudent` (J020 seeding).
- **Writing "Scribed" (SCR) code.** Conventions can be marked **SCR** (scribed — someone else
  physically wrote for the student) in the writing entry grid; SCR is **omitted from the average**
  (sum/count over the scored traits, never counted as 0). `FactAssessmentWriting.ConventionsScore`
  becomes VARCHAR (`'1'`–`'4'` or `'SCR'`); the three writing reads recompute the average over scored
  traits; `usp_UpsertWritingAssessment` validates Conventions ∈ `'1'`–`'4'`/`'SCR'`.
- **Maintenance mode.** Sysadmin can schedule a graceful lockout before an emergency container swap:
  `AppMaintenance` row + `usp_Set/ClearMaintenanceWindow`, `/api/status`, a staged countdown banner
  (warn → lock-after-next-save → full lock → quiet auto-save → "we'll be right back" overlay), a
  sysadmin `/admin/maintenance` page, and one-click Clear + sign-in on the lockdown screen.

### Changed
- **"Students" page renamed to "Reports"** (2026-09-21). Nav label, home-card title, and page header
  all read **Reports**; the route moved `/students` → `/reports` with a permanent redirect from the
  old path (bookmarks/embedded links still resolve). Home-card copy reworded off "assessment" per the
  user-facing wording rule. Same cohort view and per-student history underneath — label/route only.
- **Data Entry: pick a CYCLE, not an instance.** `/enter` now shows **one card per cycle per subject**
  ("SCoR 1" under Reading, Writing, Math) instead of one card per scoped instance — a cycle with 8
  instances was 8 near-identical "SCoR 1" tiles with nothing to tell them apart. The whole entry flow
  is keyed on the cycle header: `/enter/cycle/<cycleGroupId>/<subject>[/<group>]`. Progress on a card
  sums its instances, so a student assessed in both English and French counts as the two entries they
  owe. SQL: `tvf_UserAssessmentWindows` (+`CycleGroupID`, `CycleName`), `tvf_TeacherGroups` (now takes
  `@CycleGroupID, @AssessmentType`; +`WindowIDs`). A class that falls under **two** instances of the
  same cycle (same language, split by program scope or grade band) gets **one grid per instance, each
  with its own Save** — the shape the math grid already uses for a split-grade class.
- **Fixed: cycle progress counts were double.** `tvf_UserAssessmentWindows` selected the instance's
  `ProgramScope` but never filtered on it, so an English-scope and an Early-Immersion-scope instance
  both counted the *same* students — a teacher with 4 students read 8. All three role branches now
  apply the scope match, and the teacher branch is course-scoped to agree with the picker (an
  ELA-only teacher was offered a French Reading card that opened an empty list).
- **Entry groups are course sections, and the course sets the language.** The group picker lists only
  sections of courses mapped in `DimCourseAssessment` (ELA / FLA / Math — never a gym or science
  class), grouped under an **English / French** heading. Because an FLA section is French and an ELA
  section is English, the writing roster's **EN/FR toggle is gone** — there is nothing to set wrong.
  Above-teacher roles see every mapped-course section they'd normally see (a principal: all ELA, FLA
  and Math sections in their school), each card labelled with **whose class** it is.
- **Maintenance mode: no more auto-expire; safer scheduling.** A scheduled window used to lapse ~10
  minutes past its time so a forgotten one self-healed — but that could bring the app back **up
  mid-job** (part-way through a batch of SQL deploys), letting teachers write against a half-migrated
  warehouse. The window now persists until a sysadmin **explicitly** clears it (banner / down overlay /
  `usp_ClearMaintenanceWindow`). Quick-picks are now **10/15/30/60 min** (5 dropped); scheduling under
  10 minutes still works but asks for confirmation, warning that unsaved work on **background** tabs
  may miss the automatic save.
- **Background tabs poll far less.** Hidden tabs check for maintenance every **8 minutes** instead of
  8 seconds (plus an immediate check when you return to the tab, and a 30s retry after a failed
  check). Safe because the countdown, lock and auto-save all run locally once a window is known —
  polling only discovers a new or cleared one. Cuts the idle background load on the server.
- **DB connection pool raised 10 → 20**, so concurrent teachers aren't queued inside the app — real
  demand reaches Fabric and the capacity-usage measurement isn't under-reported.
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

### SQL deployed to live at the 0.5.0 release
Deployed 2026-09-21 via the **staged bundles** in `sql/deploy/live_0.5.0/` (generated by
`scripts/generate_live_deploy.sh` from the tracked sources; run DEV first, then live, in filename order):
1. `01_migrations.sql` — ALTERs to existing live tables: `DimProgram.ScopeBucket`,
   `DimAssessmentWindow` `AssessmentLanguage`/`ProgramScope`/`CycleGroupID`, **`FactAssessmentWriting.ConventionsScore` INT→VARCHAR** (SCR),
   `FactAssessmentWriting.AssessmentLanguage`, and the self-contained-fact columns (reading
   `LevelCode`/expected min-max, writing `WritingAverage`). All idempotent-guarded.
2. `02_new_tables.sql` — tables new in 0.5.0 (+ seeds/backfills): `DimCourseAssessment`, `DimShortCycle`,
   `DimMathComprehensionBand`, `DimMathTask`, `Stg_MathTask`, `FactAssessmentMath`, `FactStudentAdaptation`,
   `AppMaintenance`. Run-once.
3. `03_procedures.sql` — all procs (DROP/CREATE), incl. `usp_LoadMathTasks`; the 5 PowerSchool `COPY INTO`
   loaders are deliberately EXCLUDED (repo holds the not-yet-cutover CSV version; live keeps the TAB loaders).
4. `04_views.sql` / `05_tvfs.sql` — all views + TVFs (DROP/CREATE).
5. `06_grants.sql` — master grant, last.

Already-live and skipped: grade-8 reading benchmarks (20 present) and `StaffAppAccess` (seeded).
DEFERRED to a fast-follow (not in this release): the math split-pacing + carry-forward framework.

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
