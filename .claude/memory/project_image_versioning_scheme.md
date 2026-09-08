---
name: project_image_versioning_scheme
description: "RESOLVED 2026-09-08 — prod images now use semver tags + git tags + root CHANGELOG.md, starting at v0.3.0. SHA-named builds before 0.3.0 stay valid for rollback."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-08T17:23:04.079Z
---

**DECIDED + IMPLEMENTED 2026-09-08 (was an open TODO from 2026-09-02):** production
image releases moved off commit-SHA tar names + the mutable `:token` tag onto a real
**semver** scheme.

**The scheme now in force:**
- Image tagged by release version: `assessment-webapp:0.3.0` (no more `:token`).
- Tar named by version: `assessment-webapp-<version>.tar` (e.g. `assessment-webapp-0.3.0.tar`).
- Version is kept in three synced places per release: root [[CHANGELOG.md]] (`CHANGELOG.md`),
  `webapp/package.json` `version`, and an annotated git tag `v<version>` on the merge commit.
- Pre-1.0 semver: bug-fix-only release = PATCH; any new user-facing feature = MINOR.
- Rollback is by prior version tag; SHA-tagged builds before 0.3.0 (`:c30095b`, …) remain
  valid rollback references and are still named by SHA.

`docs/prod-container-swap.md` is updated for this: the tar carries the version tag directly
(the retag-on-load step is gone), and it has an up-front "Release SQL prerequisite" callout
pointing at the CHANGELOG's per-release SQL list.

**First release under the scheme: v0.3.0** — homeroom `/`-in-name 404 fix (materialized
`DimStudent.GroupKey`) + small-group roster filter + collapsible school filter. Live warehouse
SQL deployed and the `/` 404 confirmed cleared on data.tcrce.ca 2026-09-08; container swap to
`:0.3.0` is the remaining step (IT drops the tar in `C:\temp`). See [[project_assessment_platform]].
