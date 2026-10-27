---
name: feedback_changelog_as_you_go
description: "Update CHANGELOG.md (and patchNotes.ts for user-visible changes) AS each change lands, not just at release. The footer version comes from package.json."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-10-20T14:09:03.640Z
---

**Maintain the changelog AS WE GO — not at release.** Set 2026-09-17, ahead of the ~1-week-out launch
when we'll be rapidly fixing + deploying versions.

**Why:** the version footer + in-app "What's new" must reflect reality continuously; letting them lag
(the footer was stuck at v0.4.1 while the build was 0.5.0-dev) is exactly the drift to avoid.

**How to apply — after landing a notable change (a committed feature/fix):**
- Add an entry to `CHANGELOG.md` under the current `## [Unreleased] — <ver>-dev` section (Keep-a-Changelog
  Added/Changed/Fixed; developer-facing; note any SQL to deploy). Do this in the same work, don't batch to wrap.
- If the change is **user-visible**, also add a TEACHER-facing note to `webapp/src/lib/patchNotes.ts`
  (plain language, no jargon, avoid "assessment" per [[feedback_avoid_assessment_term]]). Newest first.
- The footer version is sourced from **`webapp/package.json`** (`NEXT_PUBLIC_APP_VERSION` via next.config,
  which reads package.json at build time). The in-app popup shows the current minor line PLUS the previous
  one (e.g. 0.5.x lists 0.5.x + 0.4.x) via `recentNotes()`.
- **BUMP package.json DURING DEV, not at cutover (corrected 2026-10-20).** When the first user-visible
  change of a new minor lands on `dev`, set `package.json` to **`X.Y.Z-dev`** AND add the matching
  `patchNotes.ts` current-line entry THEN — so the footer reads `X.Y.Z-dev` and the "What's New" popup are
  part of the dev test pass. Leaving package.json at the prior release through dev is the drift that bit us:
  the footer shows the OLD version on a new-version build, and the bump then slips out **unchecked at
  cutover** — a forgotten bump once forced a **second cutover**. The cutover then only STRIPS `-dev`
  (`X.Y.Z-dev` → `X.Y.Z`); fold that strip into the release ritual ([[feedback_commit_cadence]]) so it
  can't be forgotten.
- Keep `CHANGELOG.md` ↔ `patchNotes.ts` ↔ `package.json` in sync. Full versioning scheme: [[project_image_versioning_scheme]].

**What QUALIFIES for the CHANGELOG (set 2026-10-07):** only things that are NEW or CHANGED to users
relative to what shipped. A **repair of something that was working at its release and later broke** —
e.g. an environment/infra regression like the #1119 ingest `COPY INTO` outage (SP/Fabric-side change,
not our code) — does **NOT** go in the CHANGELOG: it's not a new change, it's a return to the already-
shipped behavior. Record those in our INTERNAL log only (memory + the implementation-plan Left Off notes).
The CHANGELOG `Fixed` section is for a defect that was **broken from its own release date** and later
hotfixed (shipped wrong, then corrected) — that one IS user-facing history and belongs there.
Litmus: "was this behavior ever live and correct for users?" Yes→repair, keep it out. No (broken since
ship)→Fixed entry.

**SERVER-SIDE-ONLY (warehouse SQL) behavior changes deployed to live between releases (set 2026-10-13):**
a warehouse-only SQL change that ALTERS behavior (e.g. the 2026-10-13 SpecialistTeacher Data-Entry
scoping fix — TVFs only, no app image) is **live without a container deploy, so it gets NO semver bump
and NO new version** (don't invent a 1.2.1 for a server-side fix). Record it as a **dated "server-side
patch" bullet UNDER THE CURRENT RELEASE's CHANGELOG section** (e.g. a blockquote under `## [1.2.0]`),
NOT under `## [Unreleased]` (which reads as "not shipped" — but it IS live) and NOT as a phantom new
version. **`patchNotes.ts` is NOT the vehicle** for these: the in-app "What's new" footer is tied to
`package.json`, which doesn't change, so a patchNotes entry wouldn't surface until the next container
release anyway — leave it out until then. (The user confirmed this convention 2026-10-13.)
