---
name: feedback_git_workflow
description: "The project's git branch + worktree workflow (set 2026-09-11 after a bad feat drift). Two worktrees (dev, patch); dev is the long-lived integration branch; hotfix/critical-patch cut off main; MANDATORY main->dev back-merge after every patch, AND main->dev-impersonation reconcile + <version>-imp image rebuild every release (added 2026-09-23). Consistent names, prune on merge."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-25T12:39:34.598Z
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
- **`dev-impersonation`** = LONG-LIVED branch (never pruned) = the current release + the
  sysadmin-impersonation demo delta (impersonation bar; runs `AUTH_MODE=dev` for partner/demo
  screenshots). It builds the `<version>-imp` image behind the `awdev-impersonation` container
  (:3002). Kept current via the reconcile rule below — NOT ad-hoc.
- Larger `dev` work PRs to `main` as a release.

## THE RULE THAT PREVENTS DRIFT (non-negotiable)
**After ANY merge to `main` (hotfix, critical-patch, or a dev release), immediately merge
`main` → `dev`.** Also cut every new hotfix/critical-patch from the *current* `main`, never an
old base. Without this back-merge, `dev` rots (exactly what happened to `feat`). With it, `dev`
is never more than one patch behind `main`.

**Same rule for `dev-impersonation` (added 2026-09-23).** It is a long-lived branch = release +
impersonation delta, so it drifts exactly like `dev` would. A release is not DONE until you also
**merge `main` → `dev-impersonation`, re-layer the impersonation feature over any conflicts, and
rebuild the `<version>-imp` image** (then restart `awdev-impersonation` on :3002 if it's in use).
It was parked as "backlog" once and drifted to `0.6.0-imp` while live ran `0.6.2` — the exact
failure this rule prevents. The impersonation reconcile is NOT optional; it rides every release,
right after the `main` → `dev` back-merge.

## Hygiene
- **Consistent names only** — no ad-hoc `feat/…` vs `feature/…` lookalikes. That ambiguity was
  the root cause.
- Prune merged branches (auto on merge). Verify a reconciliation BUILDS (`next build` via the
  image) before deleting the source branch.
- State WHICH branch every git claim refers to; never say "merged main in" without naming the
  target branch.

## Current topology (2026-09-25)
`main` = `dev` = **v0.7.0** (live 2026-09-25; tag `v0.7.0`, merge commit `075a39c`). `dev-impersonation`
reconciled to v0.7.0 (`18b1db7`; one add/add conflict in `data.ts` — impersonation readers vs the new
Math/RWM readers, both kept) and the `0.7.0-imp` image rebuilt + `awdev-impersonation` (:3002) restarted.
Full ritual ran clean: dev→main --no-ff, tag, main→dev FF back-merge, imp reconcile, `gh release v0.7.0`.
