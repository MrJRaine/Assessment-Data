# SharePoint Entry-Layer Pivot — Design Spec (DRAFT 2026-06-12)

**Why:** the SQL Server connector is premium; A3 teachers can't use the SQL-bound app
(see memory `project_licensing_pivot_2026_06`). Teacher entry moves to SharePoint lists
(standard connector, $0/user). Decided 2026-06-12.

**Goal state:** teachers enter assessments through the existing canvas screens rebound to
lists; the warehouse stays the system of record; a bridge syncs both directions; analysts
use Power BI (A5 Pro); school admins use the SQL screens under PAYG.

---

## Two structural facts that drive the design

### 1. The app must SPLIT in two

Power Apps evaluates premium licensing **per app, by the connections the app contains** —
if an app holds a SQL connection anywhere, every user of that app needs premium, even if
they never open the SQL-bound screens. Therefore:

| App | Screens | Connectors | License |
|---|---|---|---|
| **Teacher Entry** (new) | scrLanding (trimmed), scrWindowSelect, scrGroupSelect, scrRosterGrid, scrIPP (teacher view) | SharePoint only | $0 — A3 covered |
| **Staff Portal** (current app, survives for now) | scrStudentData, scrStudentDetail, scrIngest | SQL (existing) | Maker/dev use only for now — **end-user path for school admins is UNDECIDED (open decision 4)** |

Bonus: **the June pilot uses only the Teacher Entry app → the pilot runs at $0** with no
licensing dependency at all.

**School admins are NOT settled on the SQL app** (open decision 4 below). Their scope is
school-sized (~200-900 students — UNDER the 2000-row delegation cap), so school-scoped
lists are technically viable for them; only regional-analyst scope (full cohort) truly
breaks lists, and analysts are on Power BI. The SQL-app-under-PAYG framing in earlier
drafts was an unconfirmed assumption, not a decision.

### 2. The bridge cannot read the caller-scoped RLS views

`vw_TeacherRoster` etc. filter by `CURRENT_USER` — the bridge identity would see nothing.
The bridge needs **bridge-facing views** (e.g. `vw_BridgeRosterAll`) that return ALL rows
WITH a `TeacherEmail` column, secured by GRANTing SELECT only to the bridge account.
New SQL, small, reuses the historical-roster logic.

---

## Lists (SharePoint site TBD — likely the existing Teams private-channel site)

### `RosterEntry` — read-only working surface (bridge-maintained)
One row per (window × student × teacher-visibility). Columns: `WindowID`*, `WindowName`,
`ScaleSystem`, `WindowStatus`, `GroupKey`, `GroupLabel`, `TeacherEmail`*, `SchoolID`*,
`StudentNumber`, `StudentName`, `Grade`, `ExpectedMinLevel`/`MaxLevel`,
`ExpectedMinOrder`/`MaxOrder`, `ExistingLevelCode`, `ExistingDelta`,
`ReadingIPPStatus`, `ReadingIPPNeedsConfirmation`.
(* = indexed, created BEFORE data lands.)
The app never writes here; the bridge overwrites freely on each outbound sync.

### `Submissions` — append-only queue (app-written, bridge-drained)
`StudentNumber`, `WindowID`*, `Action` (`Upsert` / `Delete` / `IPPConfirm`), `LevelCode`,
`ReadingScaleID`, `IsIPP`, `AssessmentDate`, `SubmittedBy`*, `SubmittedAt`,
`SyncStatus`* (`Pending` / `Synced` / `Error`), `SyncError`, `SyncedAt`.
Separate queue (vs editing RosterEntry in place) so outbound refreshes can't clobber
in-flight entries and every submission carries its own sync state for the error loop.

### `ScaleLevels` — reference (bridge-seeded from DimReadingScale)
`ScaleSystem`*, `LevelCode`, `LevelOrder`, `ActiveFlag`. Feeds cmbNewLevel.

### `SyncCounts` — tripwire
`ScopeKey`* (`<TeacherEmail>|<WindowID>`), `ExpectedRows`, `LastOutboundRun`.
App compares `CountRows` of its loaded slice against `ExpectedRows` and shows a loud
error banner on mismatch — converts silent delegation truncation into a visible failure.

## Bridge

- **Outbound** (warehouse → RosterEntry + ScaleLevels + SyncCounts): on window open +
  nightly during open windows. Business-hours-aware cadence (capacity right-sizing).
- **Inbound** (Submissions → warehouse): every 10-15 min during open windows. Replays
  `Pending` rows through the EXISTING procs (`usp_UpsertReadingAssessment`,
  `usp_DeleteReadingAssessment`, `usp_UpsertStudentIPP`) — Layer-2 validation and
  ReadingDelta computation run unchanged, just later. Writes back `SyncStatus`,
  `SyncError` (THROW message verbatim), updates the RosterEntry row on success.
- **CONFIRMED 2026-06-12 ($0): Fabric-side bridge** — notebook/pipeline + Graph API to the
  lists, running on existing capacity. Requires the **Entra app registration from IT —
  the CRITICAL PATH of the entire pivot; request draft: `docs/it-request-entra-bridge.md`.**
  (Graph API to SharePoint *lists* cannot be done from Fabric without an app identity;
  there is no $0 workaround that avoids the registration.)
- ~~Power Automate variant (one premium license, ~$15 USD/mo)~~ — rejected (no-license-fees
  constraint). Revivable only by explicit user approval if IT stalls past the pilot window.

## App rework (Teacher Entry app)

- Windows/groups galleries derive from `RosterEntry` via client-side GroupBy — no extra lists.
- Save: `ForAll(colDirty, Patch(Submissions, Defaults(Submissions), {...}))` — Patch WORKS
  on SharePoint. Entries render an optimistic "pending sync" row state.
- Error loop: on load (and via a refresh button), rows in `Submissions` where
  `SubmittedBy = me And SyncStatus = "Error"` surface as a banner + per-row badge with
  `SyncError` text. Teachers see rejected entries on their NEXT visit — this is the
  accepted regression vs proc-at-save; client Layer-1 constraints (scale combo filtered
  by ScaleSystem, roster pre-scoped) keep rejections rare.
- **Delegation discipline (hard rules):** every query an indexed equality; Studio
  delegation warnings are BUILD FAILURES; any gallery that could approach 2000 rows is a
  design error; SyncCounts tripwire on every load.

## Open decisions (user owns)

1. **List permission model** (PIIDPA): (a) single lists readable by an assessment-staff
   security group — simplest, but any teacher could query beyond their roster;
   (b) per-school sites/lists — better isolation, more bridge fan-out;
   (c) bridge-managed item-level permissions — tightest, heaviest.
   Needs a deliberate call before real student data lands in lists.
2. ~~Bridge license~~ **RESOLVED 2026-06-12: Fabric-side, $0.** Remaining sub-questions for
   the IT conversation: client secret vs certificate (and where it's stored — Key Vault must
   be a Canadian region), secret rotation cadence, and the target site URL for the
   Sites.Selected grant (depends on open decision 3).
3. ~~Site location~~ **Recommendation issued 2026-06-12: dedicated team site** —
   full setup guide (site, 4 list schemas, indexes, permissions): `docs/sharepoint-site-setup.md`.
   Resolved when the site exists and its URL is supplied for the Sites.Selected grant.
4. ~~School-admin path~~ **RESOLVED 2026-06-12 by hard constraint: "NO recurring license
   fees" (user, verbatim sentiment).** Admins go on **school-scoped lists** (their scope
   fits the 2000-row delegation cap). **School admins ARE in the pilot** (confirmed
   2026-06-12, consistent with the standing "all three roles demonstrated in MVP" scope
   rule) → the admin port is IN the pre-pilot build, not deferred: cohort + history lists,
   per-student on-demand history in scrStudentDetail, SchoolID-scoped queries.
   Fallback ONLY if the pilot date forces it (user's call, not assumed): pilot admins get
   the entry-monitoring path (window/group/roster read-only via SchoolID) and the
   cohort/detail dashboards land immediately post-pilot.
   PAYG is off the table everywhere. The current SQL app degrades to maker-only reference —
   no production users, no premium licenses, ever.
5. Inbound cadence vs teacher expectation ("when will my save show as confirmed?").

## Sequence (~4-7 weeks to pilot-grade — pilot includes school admins)

0. **NOW:** file the Entra app registration with IT (gates the $0 bridge — critical path).
1. **Wk 1:** bridge-facing SQL views + GRANTs; lists + indexes (incl. cohort + history lists
   for the admin scope); outbound bridge; ScaleLevels seed.
2. **Wk 2:** app split; rebind window/group/roster/IPP screens; Submissions save path.
3. **Wk 3:** inbound bridge + error write-back; error-surfacing UI; SyncCounts tripwires.
4. **Wk 4-5:** admin port — scrStudentData/scrStudentDetail against school-scoped lists,
   per-student on-demand history; admin read-only roster views.
5. **UAT vs the SQL app side-by-side; buffer; pilot share** (Step 20) — both apps, $0 licensing.

Note: the pilot also demonstrates the analyst role — that's Power BI (model + RLS roles
already deployed); confirm whether a starter analyst report needs to be in pilot scope.
