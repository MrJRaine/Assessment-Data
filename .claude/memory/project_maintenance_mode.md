---
name: project_maintenance_mode
description: "Pre-1.0 feature (NOT built): graceful maintenance/'reset' mode so emergency container swaps can run any time of day with minimal teacher disruption — poll-based countdown banner, staged entry lockout, a quiet auto-save net, new-page redirect, and a sysadmin page to set the window. Full agreed timeline + design."
metadata:
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
  modified: 2026-09-11T13:09:42.714Z
---

**Purpose:** deploy **emergency patches (container swaps) at ANY time of day** "generating as little
aggro as possible." Scoped 2026-09-11.

**BUILT 2026-09-16 (on `dev`/0.5.0-dev; SQL pending dev deploy).** Decisions made at build:
- **Store = WAREHOUSE ROW** (`AppMaintenance`, single row Id=1) + `usp_Set/ClearMaintenanceWindow`
  (both sysadmin-gated in-proc via StaffAppAccess.IsSysAdmin). `/api/status` reads it with a ~10s
  in-memory cache (poll load) and **fails OPEN** on a read error. MaintenanceAt stored UTC; the set
  proc takes a VARCHAR 'YYYY-MM-DD HH:MM:SS' and CASTs (matches the app's VARCHAR-param convention).
- **Clearing = EXPLICIT ONLY** (`usp_ClearMaintenanceWindow`, via the banner / down overlay / admin
  page). The old ~10-min **auto-expire was REMOVED 2026-09-18** — it could bring the app back UP
  mid-job (e.g. part-way through deploying a batch of SQL scripts), letting teachers write against a
  half-migrated warehouse. A forgotten window now stays down, which is the safer failure: the overlay
  carries a Clear button AND sign-in, so a locked-out sysadmin can still switch accounts and clear.
- **Sysadmin UX = "lock down in N minutes"** (quick-pick **10/15/30/60** + custom 1–240 + optional
  message) rather than an absolute datetime picker — avoids Atlantic/DST conversion; server computes T.
  5 min was dropped (below the safe threshold for background tabs). Scheduling **under 10 minutes** is
  still allowed (testing needs it) but pops a **confirmation** warning that unsaved work on BACKGROUND
  tabs may not auto-save in time — informed choice, not a hard block.
- **Hidden tabs poll every 8 min** (not 8s), + immediate poll on becoming visible, + 30s retry after a
  failed poll. Safe because polling only DISCOVERS a new/cleared window — once known, the local 1s
  ticker drives every stage (lock/auto-save/overlay) with no network. This is what the ≥10-min
  guidance protects: worst case a hidden tab learns 8 min late and still clears the T-1 auto-save.
  (Browsers throttle background timers anyway, so the practical saving is smaller than the arithmetic.)
- **M4 new-load redirect SIMPLIFIED:** a client full-screen "We'll be right back" overlay when stage
  = 'down' (past T), covering open tabs AND fresh loads uniformly. The spec's server-path-aware
  "redirect fresh loads at T-5" was skipped — during T-5..T fresh loads just get the banner + locked
  inputs (harmless). Revisit only if that proves confusing.

Files: `sql/security/AppMaintenance.sql`, `sql/procedures/usp_Set|ClearMaintenanceWindow.sql`
(+ grant_webapp_sp.sql); `webapp/src/app/api/status/route.ts`; `components/maintenance/`
(`MaintenanceProvider.tsx` = poller+banner+down overlay+context, `useEntryLock.ts` = grid lock/
auto-save/beforeunload); grids reading/writing/math **and** Programming consume `useEntryLock`;
`app/admin/maintenance/` (page+control+actions, isSysAdmin-gated, nav item). **Deploy to dev/live:**
run the 3 SQL files (self-granting). **SQL deployed to DEV 2026-09-16.**

**Refinements (2026-09-16 testing):**
- Fabric gotchas hit + fixed (also → fabric-warehouse-sql skill): **no `TINYINT`** (Msg 24574 — used INT);
  a bare `IF`-body **`;THROW` must be wrapped in `BEGIN…END`** (Msg 102).
- **Sticky lock across navigation**: `useEntryLock` persists "locked after next save" in sessionStorage
  keyed by T, so navigating away/back or between sections stays locked for the rest of the window (was
  per-mount state that reset). Auto-save wrapped in try/catch.
- **Down = fixed overlay ON TOP** of the still-mounted app (was replacing children → suspected the ~T-1
  client-side crash from tearing down a grid mid auto-save).
- **Sysadmin one-click Clear** on the banner (every stage) + the down overlay (optimistic local clear),
  and **AuthArea (sign in/out) on the down overlay** so a signed-out / wrong-account sysadmin can switch
  accounts and clear it (else the overlay traps them). Dev impersonation bar moved above the overlay.
- **Poll cadence tightened** so open tabs pick up a new window fast: `/api/status` cache 4s; client poll
  8s far / 4s near (fresh loads already poll on mount = immediate; banner is app-wide via AppShell).
- **Banner copy softened** (user: "too aggressive") — kept T-5/T-3/T-1 timing, gentler wording, T-5 stage
  amber not red.

Original agreed spec + timeline preserved below.

**Why POLL, not push:** the app holds no persistent client↔server connection (pages are
server-rendered + force-dynamic), so a client poller drives this, not a socket. True SSE push is the
heavier alternative — only reach for it if poll lag ever proves a problem. See [[project_webapp_fabric_connection]].

**Shared maintenance-window store:** sysadmin sets a window the RUNNING container can read WITHOUT a
rebuild — a warehouse row (`AppMaintenance`) or a mounted file (`/mnt/c/temp/…`, editable over RDP).
Extend the existing health/status endpoint (`/api/status`) to return `{ maintenanceAt, serverNow, message }`.
- **Server-authoritative clock (CRITICAL):** return server "now" (or seconds-remaining) so each client
  offsets its own possibly-skewed laptop clock. Every trigger below keys off SERVER time, or a fast
  laptop fires the lock/auto-save early.
- **Clearing the window (open design detail):** the store is persistent, so the lock does NOT auto-lift
  just because the container restarted. Either the window auto-expires (past `maintenanceAt` + a buffer)
  OR sysadmin posts an explicit "all clear" after the swap. Decide which when building.

**AGREED TIMELINE (T = maintenance/swap moment):**
- **Before T-5 (window approaching):** banner WARNS that data entry will lock 5 minutes before the
  maintenance window.
- **T-5:** inputs/selects disable **after the teacher's NEXT save** (NOT instantly) — then show the
  warning; the buffer keeps a mid-entry teacher from being cut off. **Block INPUT, not save** (Save
  still works so already-staged edits can flush). ALSO: **new page loads redirect** to a "Maintenance
  pending — server coming down in X minutes, we apologize for the inconvenience" screen.
- **T-3:** inputs/selects lock FULLY; warn of the auto-save at T-1.
- **T-1:** **auto-save** whatever is still staged.
- **T:** swap.

**Auto-save is a QUIET safety net — deliberately NOT advertised** so teachers don't rely on it and
push their luck (leave work unsaved assuming it'll be caught). It surfaces ONLY to someone about to be
caught, right before it happens (the T-3 heads-up), never as a promoted feature. Pair with a
`beforeunload` "unsaved changes" guard (belt + suspenders).
- **Subject scope:** **reading + math are safe** to auto-save — each is cell/level independent
  (per-student or per-task upserts), so there's no partial-row validation failure ([[project_math_assessment_model]]
  cell-by-cell 0/1; [[project_ongoing_assessment_model]] latest-by-date). **Writing is the 4-trait
  exception** — a partial row can't save; auto-save complete rows only, or leave writing to manual
  Save + the beforeunload guard.

**Sysadmin control page (to build):** sysadmin picks the maintenance time and starts the synced
countdown (writes the window to the shared store; all clients key off it, so everyone is in sync).
Include cancel / "all clear." Gate on the **`isSysAdmin` StaffAppAccess capability** (resolved in
`AppShell`, like Cycles/Ingest). See [[project_assessment_platform]].

**Enforcement level:** client-side UI lock is sufficient — sysadmin controls when the swap actually
fires, and entry's been frozen since T-5, so nothing is mid-write at T. Proc-level rejection of
in-window saves was considered and SKIPPED (would reject a legitimate last-second save for no gain).

**Reach limitation (accepted):** the banner/lock only affect OPEN tabs; anyone opening the app during
the window hits the redirect screen instead. A fully-AFK teacher with a tab open is exactly who the
auto-save net is for.

**Build checklist (when scheduled, pre-1.0):**
1. Shared window store + `/api/status` (server-authoritative now / seconds-remaining) + clear/expiry.
2. Client poller in `AppShell` → staged banner (warn → lock-after-next-save → full-lock → auto-save
   countdown), all server-synced.
3. Entry-grid gating across the reading / writing / math grids (lock-after-next-save at T-5, full lock
   at T-3, auto-save at T-1) + `beforeunload` guard.
4. New-page-load redirect → maintenance-pending screen while in-window.
5. Sysadmin set-window / start-countdown page (isSysAdmin-gated) + cancel / all-clear.

Related: [[project_webapp_fabric_connection]], [[feedback_loading_states]], [[project_assessment_platform]].
