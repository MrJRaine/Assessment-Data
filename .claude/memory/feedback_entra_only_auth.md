---
name: feedback_entra_only_auth
description: dev + main (live) web-app code must be Entra-only auth — the AUTH_MODE=dev bypass belongs ONLY on the dev-impersonation branch
metadata:
  type: feedback
---

The user wants **only Entra auth in the code for live and dev** — that INCLUDES removing the
dev-auth bypass (`AUTH_MODE=dev` / `ALLOW_DEV_AUTH` / `DEV_FAKE_UPN`), not just the impersonation bar.
Dev-auth + impersonation live ONLY on the `dev-impersonation` branch (the `-imp` image, :3002).

**Why:** the user gave this instruction earlier, but it was never recorded, so a later session found
`authMode.ts`'s fail-closed dev bypass still in every build and a machine's untracked `.env.dev` still
set to `AUTH_MODE=dev` — awdev (:3001) silently ran as `DEV_FAKE_UPN` instead of real sign-in
(found 2026-10-12, 1.2.0 sign-off). The user was rightly frustrated at having to repeat it.

**How to apply:** never reintroduce a dev-auth path on `dev`/`main`; a fail-closed opt-in is NOT an
acceptable substitute. When merging `dev` → `dev-impersonation`, the dev-auth path must SURVIVE on that
branch only. Untracked `.env.dev` files don't travel by git — on a new machine check `AUTH_MODE` there.
Related: [[feedback_git_workflow]], [[reference_podman_windows_dev_container]].
