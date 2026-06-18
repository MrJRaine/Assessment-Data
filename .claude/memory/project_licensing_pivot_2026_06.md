---
name: Licensing Crisis, Entry-Layer Pivot, and the Pinned Supabase Option
description: 2026-06-12 — Power Apps SQL connector is premium (~$10 USD/active user/mo); A3/A5 don't cover it. DECISION — pivot teacher entry to SharePoint lists (standard connectors), analysts to Power BI. PINNED for post-pilot — Supabase/Postgres migration analysis (compelling numbers; privacy review is the long pole).
metadata:
  type: project
---

## The discovery (2026-06-12)

At Step 20 (share with pilot teachers) the licensing wall surfaced: the SQL Server connector
is **premium**, every app USER needs premium licensing, and M365 A3/A5 include
standard-connector Power Apps only. The user's own two months of building/testing worked
because of an (almost certainly) self-service **Premium trial** started when the SQL
connection was first added (Step 16, 2026-05-11) — **the user is verifying the trial and its
expiry date; until replaced by PAYG or a maker license, dev access has a clock on it.**
Root-cause analysis and the standing prevention rule live in [[feedback_licensing_gate_on_design]].

Costs at full rollout (200 teachers, seasonal): PAYG $10 USD/active user/mo ≈ $6000-8000 CAD/yr;
per-user premium $48 000 USD/yr; per-app plan retired from direct channels Jan 2026
(CSP/EA + EDU pricing via Microsoft rep — quote was recommended but pivot decision mooted it).

## The decision (2026-06-12): SharePoint-list pivot (Option B)

Three options were priced (full comparison in the session archive):
- **A. Custom web app** (Blazor + Entra OBO, identity passthrough preserves CURRENT_USER RLS
  + proc validation; $0/user; 6-10 wks; gated on IT Entra app registration)
- **B. SharePoint-lists rework** of the existing canvas app (3-5 wks)  ← **CHOSEN**
- **B0. Keep app, pay PAYG** (days; ~$6000-8000 CAD/yr if permanent)

**User chose B to leverage the existing canvas app.** Then hardened (same day, verbatim
mood: "NO MORE LICENSE FEES") into a **binding constraint: $0 per-user recurring licensing
anywhere in the production path. PAYG and premium licenses are off the table — not a
cost-optimization, a rule.** Shape:
- **Teachers (200, A3)**: entry screens rebound from SQL views/procs to SharePoint lists —
  standard connector, $0/user.
- **Analysts (10, A5)**: served via Power BI (A5 includes Pro — note A5 does NOT include
  Power Apps premium). Semantic model + 3 DAX RLS roles already deployed. (A5 is already
  owned — not a new fee.)
- **School admins (A3)**: **school-scoped lists** (their ~200-900-student scope fits the
  2000-row delegation cap). **Admins ARE in the pilot** (confirmed 2026-06-12) → admin port
  is in the pre-pilot build (cohort/history lists, per-student on-demand history). NOT PAYG —
  resolved by the constraint. Pilot-grade timeline ~4-7 wks.
- **Bridge** warehouse↔lists: **Fabric-side ($0) is mandated** — pipeline/notebook + Graph,
  which REQUIRES the Entra app registration from IT → **critical path; file immediately.**
  The one-premium-license Automate variant survives only as a user-approved emergency
  stopgap (default NO).
- The old SQL-bound app becomes maker-only reference; no production users → the premium
  trial expiry mostly stops mattering (list-bound development needs no premium).

Known costs of B (accepted knowingly): SQL RLS does not gate lists (permission design needed —
PIIDPA surface); **validation timing inverts** (proc THROWs fire at bridge-replay, not at
teacher save — needs error-sync-back column + count tripwires); silent Power Apps delegation
truncation at 2000 rows (rule: every query an indexed equality; Studio delegation warnings =
build failures). Spec: `docs/sharepoint-entry-pivot.md`.

## PINNED — Supabase/Postgres migration (revisit post-pilot / at capacity right-sizing)

Strategic conclusion from 2026-06-12 analysis (user-endorsed, de-biased of sunk cost):
**the forward-looking dollars favor leaving Fabric post-grant; the privacy review is the long
pole, not engineering.**

- Workload truth: ~6000 students, ~45 000 assessment rows/yr, <1 write/sec peak, <1 GB for a
  decade. Never warehouse-shaped.
- Sizing: Supabase Pro + Small compute (2 GB) ≈ **$30 USD ≈ $41 CAD/mo** vs F2 $241 CAD/mo
  (current F8 $964). ~$2400+ CAD/yr avoidable. Region: AWS ca-central-1 exists.
- Architecture maps 1:1: CURRENT_USER RLS views → native RLS policies; usp_ procs →
  Postgres functions via supabase.rpc() (**synchronous validation errors preserved** — the
  thing Option B gives up); Entra sign-in via OIDC federation; supabase-js + RLS collapses
  the middle tier (static SPA, no hosted backend); pg_cron replaces Pipelines.
- **Edge Functions residency rule** (verified against supabase docs/guides/functions/regional-invocation):
  region pinning is **per-invocation only** (`region:` option / `x-region` header), default =
  nearest-to-caller (can be US) — compliant-by-convention, not by default. Design rules if
  adopted: PII logic in-database by default; single client wrapper that always pins
  ca-central-1 (no raw invoke()); functions self-assert executing region and fail closed.
  No auto-failover when pinned = fail-closed in Canada (correct for PIIDPA).
- Blockers/process: new-vendor Privacy Impact Assessment + procurement (months, school-board
  process, CLOUD Act conversation); Power BI re-pointed to Postgres import mode; SQL port
  2-4 wks (pgSQL is friendlier than Fabric's T-SQL subset).
- Strategic posture (user, 2026-06-12): pay Microsoft for what they're uniquely good at
  (identity, Teams distribution, governance, analyst Power BI) and own/keep portable every
  layer they tax (app layer, possibly the database).

## Related

[[feedback_licensing_gate_on_design]] — the prevention rule born from this.
[[project_capacity_rightsizing_intent]] — the budget review where the pinned option gets decided.
[[project_submission_validation_strategy]] — the validation design Option B partially inverts.
