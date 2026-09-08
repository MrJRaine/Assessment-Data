# Changelog

Version history for the Short Cycles of Response App (web app + Fabric warehouse
deploys to **data.tcrce.ca** / `Assessment_Warehouse`).

Format follows [Keep a Changelog](https://keepachangelog.com/); this project uses
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`, pre-1.0).
Each release lists the **web** changes shipped in the container and any **SQL**
that must be deployed to the live warehouse alongside it.

Entries before `0.3.0` are reconstructed retroactively — formal tracking starts
with `0.3.0`, so earlier detail is approximate.

## [Unreleased] — `0.4.0-dev` (`feat/math-p6-entry`)

Work staged on the dev branch, not yet released to live. Headline: **Math P–6
task-based short cycles** (binary can-do/cannot mastery, by-task proportion +
by-student 4-tier achievement level; data layer + entry matrix). Also carries the
Math-aware variants of the `0.3.0` group-key TVFs. Not on `main` / live yet.

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
