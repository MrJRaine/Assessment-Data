---
name: feedback_git_workflow
description: "The project's git branch + worktree workflow (set 2026-09-11 after a bad feat drift). Two worktrees (dev, patch); dev is the long-lived integration branch; hotfix/critical-patch cut off main; MANDATORY main->dev back-merge after every patch. Consistent names, prune on merge."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-11T15:23:38.617Z
---

**Set 2026-09-11** after a branch-naming mess: I had similarly-named branches
(`feat/math-p6-entry`, `feature/prior-year-baseline`) and talked about them as if
they were one, while `feat` silently drifted **29 commits** behind `main`. The fixed
convention below exists to make that impossible.

## Worktrees (physical)
- **`C:\Git-Repos\Assessment-Data`** = the **dev** worktree, on branch **`dev`**. Larger
  features / bigger patches develop here.
- **`C:\Git-Repos\Assessment-Data-prod`** = the **patch** worktree, on **`main`** (the live
  release state). Hotfixes/critical patches are cut off `main` here; also the clean `main`
  checkout for release container builds. (Intended dir name `-patch`; a Windows file lock
  blocked the rename 2026-09-11 — cosmetic, retry when the folder isn't open.)

## Branches
- **`main`** = live release state. **`dev`** = long-lived integration branch (never pruned).
- **`hotfix`** / **`critical-patch`** = SHORT-LIVED, cut fresh off **current `main`** in the
  patch worktree for time-sensitive fixes. Consistent NAMES (suffix `/<slug>` only if two run
  at once); PR to `main`; **auto-deleted on merge** (GitHub "delete head branch on merge" is
  ENABLED as of 2026-09-11).
- Larger `dev` work PRs to `main` as a release.

## THE RULE THAT PREVENTS DRIFT (non-negotiable)
**After ANY merge to `main` (hotfix, critical-patch, or a dev release), immediately merge
`main` → `dev`.** Also cut every new hotfix/critical-patch from the *current* `main`, never an
old base. Without this back-merge, `dev` rots (exactly what happened to `feat`). With it, `dev`
is never more than one patch behind `main`.

## Hygiene
- **Consistent names only** — no ad-hoc `feat/…` vs `feature/…` lookalikes. That ambiguity was
  the root cause.
- Prune merged branches (auto on merge). Verify a reconciliation BUILDS (`next build` via the
  image) before deleting the source branch.
- State WHICH branch every git claim refers to; never say "merged main in" without naming the
  target branch.

## Current topology (2026-09-11)
`main` = v0.4.1 (live). `dev` = `0.5.0-dev` — reconciled: 0.4.0 baseline + 0.4.1 footer/diff-fix
+ Math P-6 + Programming makeover Phase 0. See [[project_programming_makeover]], [[project_math_assessment_model]].
