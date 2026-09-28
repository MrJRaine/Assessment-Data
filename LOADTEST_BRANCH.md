# ⚠️ `loadtest` branch — NEVER MERGE TO `main`

This branch (cut from `dev-impersonation`) carries a **deliberate authentication bypass** for load
testing the app's serving capacity with a Locust/k3s cluster. It must **never** be merged into `main`
or `dev`, and the load-test image must **never** run against production or the live warehouse.

## What's here that must not ship

- `webapp/src/lib/loadtest.ts` — the bypass module (key gate, identity allow-list, startup guard).
- `webapp/src/instrumentation.ts` — boot-time fail-closed guard + banner.
- `webapp/src/middleware.ts` — the `LOADTEST_AUTH_BYPASS` branch.
- `webapp/src/lib/auth.ts` — the `X-Loadtest-User` header path in `getCurrentUpn`.
- `scripts/loadtest_guard_check.mjs`, `docs/LOADTEST_HANDBACK.md`, `sql/scripts/list_loadtest_identities.sql`.

## Safeguards already in place

- **Fail-closed at boot:** the container refuses to start if `LOADTEST_AUTH_BYPASS=true` with a live host,
  a non-`*_Dev` warehouse, `AUTH_MODE≠dev`, or no `LOADTEST_KEY`. See `assertLoadtestSafe`.
- **Inert by default:** with `LOADTEST_AUTH_BYPASS` unset, every file above is a no-op and normal Entra
  sign-in applies.

## No CI merge-guard yet — manual check

There's no CI in this repo. Before any release, confirm the bypass module is absent from `main`:

```bash
git grep -l "LOADTEST_AUTH_BYPASS" origin/main && echo "STOP: bypass leaked onto main" || echo "clean"
```

If CI is added later, wire that grep as a required check that fails the build when the string appears on `main`.
