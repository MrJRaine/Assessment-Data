---
name: Assessment Platform Project
description: Distilled current-state decision record for the regional student assessment data platform (Microsoft Fabric, Nova Scotia). Final/resolved decisions organized by topic — NOT a chronological log. Read this at session start; the full session-by-session narrative lives in project_session_archive.md (read on demand).
type: project
originSessionId: 4e72a76d-8a9e-4688-9831-7b79552a94a1
---

Regional student reading/writing assessment platform for a Nova Scotia school system (~6000 students P–12, ~200 teachers, 10 region-level analytics users). Built on Microsoft Fabric. This file is the **distilled decision record** — each entry is the *resolved* state of a decision plus its rationale, with pointers to where the mechanics live. The chronological log (every session's "Decisions and Discoveries", test-data snapshots, intermediate/reversed decisions) is preserved verbatim in **[[project_session_archive]]** — go there only to recover a historical detail or the reasoning behind a reversal.

**Where the detail lives (don't duplicate it here):**
- `CLAUDE.md` + `/regional-assessment-platform` skill — architecture, schemas, scale, compliance.
- `/fabric-warehouse-sql` skill — every T-SQL limitation + the reserved-word/timezone/COPY INTO conventions.
- `/power-apps-canvas-build` skill — the canonical Power Apps reference (build workflow, Power Fx gotchas, control templates, write pattern, pre-flight).
- `docs/implementation-plan.md` — step status + the "Left Off — DATE" notes (current next-actions live there, NOT here).
- Topic memories (linked below) — deep rationale for specific decisions.

---

## Fabric infrastructure (confirmed)

- Workspace `Regional_Data_Portal`; Warehouse `Assessment_Warehouse`; semantic model `Assessment_Analytics`. Fabric artifacts use `underscore_style`; SQL objects use `PascalCase`.
- Capacity **F8** (~$964 CAD/mo), **grant-funded for MVP only**. F2 (~$241/mo) is the real post-grant target — model decisions as if F2 applies; capacity-review Apr–May 2026. See [[project_capacity_rightsizing_intent]].
- Region: Fabric is in **Canada East** (deliberate implementation choice). PIIDPA's actual bar is "any Canadian region" (Canada East *or* Canada Central both qualify) — don't conflate the project's Canada-East standard with the regulatory floor. See [[feedback_piidpa_canada_not_canada_east]].
- Licensing: teachers/admins on M365 A3 (Power Apps Teams-embedded + standard Power Automate + free Power BI). 10 regional analysts upgraded A3→A5.

## Timeline (dates corrected 2026-06-09 — originals read "2025", a year typo carried through every source doc)

- **Pilot MVP: June 2026** — French Immersion pilot, 5–10 teachers, reading only.
- **Full rollout: September 2026** — all programs (EN + FR), all schools, ~200 teachers, reading + writing.
- Provenance (so this isn't re-questioned): the plan's critical path is "8 weeks to June" and hands-on build started 2026-04-22 → that lands the pilot in June 2026. The original "June 2025 / September 2025" wording predated the build by a year and was never reconciled against the calendar until 2026-06-09.

---

## Core architecture decisions (resolved)

- **Warehouse, not Lakehouse, for the data store** — Power Apps needs SQL write access; Lakehouse SQL endpoint is read-only. A small Lakehouse (`Assessment_Landing`) still exists, holding only the OneLake CSV landing zone (`Files/imports/{topic}/`). Dim/Fact tables live in `Assessment_Warehouse`.
- **Warehouse, not SQL Database** — analytical star-schema + Power BI workload.
- **No Spark** — ~6000-student volume doesn't justify it; T-SQL procs + (eventually) Data Pipelines suffice.
- **Surrogate keys in all fact tables** — never business keys (SCD Type 2 mints new surrogate keys on change). Fabric IDENTITY is `BIGINT` only, bare `IDENTITY` (no seed/increment).
- **RLS is derived, never manually maintained** — all access must be derivable from the authoritative PS staff export; no manual exception tables (they drift). Section access from the `FactSectionTeachers` bridge; school access from the materialized `StaffSchoolAccess` table.
- **No live PowerSchool connection** — all PS data lands via manual CSV upload + ingest. PS-sourced tables are stale until the next ingest, so "live view" freshness arguments don't apply — default to materialization on ingest. Power Apps assessment writes are the only live data path. See [[feedback_no_live_ps_connection]].
- **Semantic model: Direct Lake on OneLake mode** (not "on SQL"). The SQL mode was abandoned mid-build because its DirectQuery DAX subset blocks `CONTAINSROW`, breaking `[Col] IN tablevar` RLS. OneLake mode gives the full DAX surface but permits no views in the model — which forced materializing `vw_StaffSchoolAccess` into a table (below).

## SCD policy (resolved)

- **Every business attribute on DimStudent / DimStaff / DimSection is Type 2.** Any change to a business-meaningful field versions the row. Only lifecycle/audit columns are exempt (surrogate key, business key, EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated). Rationale: point-in-time reports must be reproducible after later changes. **Always filter `IsCurrent = 1` for current state.**
  - One exception: **`DimStaff.AccessLevel` is Type 1** (overwrite) — a denormalized snapshot of the person's highest-priority school-tier role; its history is recoverable from `FactStaffAssignment`'s own Type 2 history.
- **DimSchool is Type 1** (overwrite). Seeded from the NS 2024-2025 Directory of Public Schools (22 TCRCE schools) — NOT from PS.
- **Anti-join semantics — close-only vs close+replace:** if an entity absent from an import has a *single known* inactive state → close + insert replacement (DimStaff: `ActiveFlag=0`). If the absent state is *multi-valued/unknowable* → close-only, no replacement (DimStudent: could be Inactive/Graduated/Pre-Enrolled; FactStaffAssignment: triple just stops). Document the choice in each proc header.
- **FactSectionTeachers is keyed on business keys** (`SectionID`, `TeacherEmail`, `TeacherRole`) — NOT surrogate keys — so DimSection Type 2 churn (e.g. frequent EnrollmentCount versions) doesn't cascade into the bridge, and RLS matches `CURRENT_USER` against `TeacherEmail` with no DimStaff join.
- **Per-fact surrogate-key linking policy** (freeze vs re-resolve) is its own memory: [[project_assessment_fact_scd_policy]]. Summary: FactEnrollment re-resolves while active, freezes when closed; FactAssessmentReading/Writing freeze StudentKey at insert via effective-date join on AssessmentDate (never re-resolve).

## Business keys (resolved)

- **DimStudent → `StudentNumber`** (provincial 10-digit). More stable than PS DCID (which changes on re-enrollment). DCID kept in `SourceSystemID` for reference only.
- **DimStaff → `Email`** (lowercased; = Entra UPN for RLS). PS emits one row per staff-school-role combo, so PS IDs can't identify a person. DimStaff is pure identity; per-school/role detail lives in the `FactStaffAssignment` bridge (grain: email × school × role; `SourceSystemID` change on an existing triple = email-reuse collision → version + audit warn).
- **DimSchool → `SchoolID VARCHAR(10)`** (4-digit provincial numbers with leading zeros, e.g. `'0079'`). All dependent SchoolID columns are VARCHAR(10); ingest left-pads to 4.

## Reference dimensions (seeded once; not touched by the ingest orchestrator)

| Dim | Rows | Notes |
|---|---|---|
| DimProgram | 20 | ProgramFamily = English / French Immersion / French Second Language; IsImmersion flag. CSAP/Adult/TAP excluded. |
| DimRole | 50 | PS Group# → one of 6 RoleCodes. |
| DimGender | 3 | F/M/X; code stored verbatim on DimStudent. |
| DimTerm | 63 | TermID `YYTT`; SchoolYear/TermCode. |
| DimGrade | 15 | PP=−1, P=0, 1–12, RG=13. Fixes lexicographic grade-range bugs (use GradeOrder). |
| DimReadingScale | 59 | 27 EN (DT + A–Z) + 32 FR (TD + 1–30 + 30+). LevelOrder for arithmetic. |
| DimReadingBenchmark | 160 | (ScaleSystem, ProgramFamily, GradeCode, Month) → ExpectedMin/Max. |
| DimAchievementLevel | 4 | Operator-column bounds (DECIMAL) + hex colors; reused for writing 2.75 threshold later. |
| DimCalendar | 5844 | Bulk-insert (WHILE-loop version was too slow). |

**RoleCode taxonomy (6 values):** `Teacher` (section-level RLS via FactSectionTeachers; incl. APSEA itinerants, IB/O2/Co-op coordinators after the 22/32 reclass), `SpecialistTeacher` + `Administrator` (school-level RLS via StaffSchoolAccess), `RegionalAnalyst` (multi-school via CanChangeSchool), `ProvincialAnalyst` + `SupportStaff` (no app access — excluded from all security groups). NULL = unused PS slots.

## PowerSchool ingest conventions (resolved)

- **Manual CSV upload → `usp_RunFullIngestCycle`** is the MVP path (Strategy A). The orchestrator runs all 5 load+merge procs in dependency order (Student → Staff → Section → Enrollment → SectionTeachers) and re-resolves downstream keys.
- **Folder-based routing** (`data/imports/{students|staff|sections|section-teachers|enrollments}/`) — pipeline ignores filenames.
- **Format quirks** (full detail in `/fabric-warehouse-sql` + `docs/export-procedures.md`): PS *direct table extracts* = TAB-delimited, CR-only line endings (`ROWTERMINATOR='0x0D'`), `.text` extension, no quote qualifier; PS *sqlReports* (Co-Teachers) = comma, CRLF, `FIELDQUOTE='"'`.
- **Translations at ingest:** email→LOWER; SchoolID zero-pad to 4; HomeSchoolID `'0'`→NULL, per-row SchoolID `'0'`→`'0000'`, `'999999'`→stripped; Grade_Level `0`→`'P'`, `-1`→`'PP'`, `13`→`'RG'`; dates `MM/DD/YYYY` via `CONVERT(...,101)`; `[Group]` is a reserved word.
- **EnrollStatus** is multi-valued (`0` Active / `2` Inactive / `3` Graduated / `-1` Pre-Enrolled); Students export filtered to `IN (0,-1)` so pre-enrolled reach the warehouse with a date-gated visibility rule.
- **Truncate-all-6 reset rule** for testing: when resetting before `usp_RunFullIngestCycle`, truncate all 6 orchestrator targets (FactEnrollment, FactSectionTeachers, FactStaffAssignment, DimSection, DimStaff, DimStudent), never selectively (TRUNCATE resets IDENTITY → stale surrogate keys otherwise). See [[feedback_full_reset_truncate_all]].
- **Verify state via `SELECT COUNT(*)`, never the Fabric data-preview pane** (it caches). See [[feedback_fabric_stale_preview]].

## Ingest automation (resolved: DEFERRED to post-MVP)

Automated ingest is **deferred entirely**; the pilot uses manual upload + manual orchestrator run. The chosen *future* path is **OneLake SharePoint shortcuts** — a Lakehouse `Files/imports/{topic}/` subfolder that live-links to the Teams private-channel SharePoint folder; existing `usp_Load*Staging` `COPY INTO` procs work unchanged, only a scheduled trigger is needed. This **supersedes** all earlier abandoned approaches (in-app picker → PA → OneLake; SP→OneLake via service principal; Dataflow Gen 2). See [[project_onelake_sharepoint_shortcuts]]; the dead ends and why are in [[project_session_archive]] + [[feedback_webcontents_no_binary]].

## RLS approach (resolved)

- **SQL views use `CURRENT_USER`** (Fabric Warehouse rejects `USERPRINCIPALNAME()`; DAX RLS roles still use `USERPRINCIPALNAME()`).
- **`StaffSchoolAccess`** = materialized table rebuilt every staff merge (was a view; materialized so the OneLake semantic model can use full DAX RLS). Output: StaffKey | Email | SchoolID | AccessLevel; `WHERE AccessLevel IS NOT NULL` is the inclusion gate.
- **Three secured Power-Apps-facing views**: `vw_TeacherStudents`, `vw_SchoolStudents`, `vw_RegionalData`. **Three DAX RLS roles**: Teachers (current-only), SchoolAdmins (per-row SchoolID, allows historical), RegionalAnalysts (unrestricted).
- **Window-context views** (`vw_UserAssessmentWindows`, `vw_TeacherGroups`, `vw_TeacherRoster`) use **historical-roster reconciliation** — for a closed window, a teacher sees the roster they HAD then (effective-date join on the window date), not their current roster. Admin side is current-only by design. See [[project_historical_roster_reconciliation]].
- RLS empirically validated at the SQL layer via a 5-test impersonation matrix; DAX-layer end-user validation is deferred to pilot UAT (SSO blocks all "View as / Test as role" tooling on Direct Lake on OneLake).

## Power Apps (resolved — but see the 2026-06-12 licensing pivot below)

**LICENSING PIVOT (2026-06-12) — read [[project_licensing_pivot_2026_06]] before any entry-layer work.** The SQL Server connector is PREMIUM; A3/A5 don't cover it; the SQL-bound app cannot be shared to teachers as-is. DECIDED: **binding constraint — $0 per-user recurring licensing in the production path (no PAYG, no premium, period).** Teacher entry AND school-admin screens rebind to **SharePoint lists** (admins school-scoped — fits the 2000-row delegation cap; ported after the teacher pilot); analysts → Power BI (A5 Pro, already owned); bridge must be **Fabric-side ($0)** → the IT Entra app registration is the pivot's critical path. Old SQL app = maker-only reference. The user's own access has run on a premium TRIAL (expiry being verified — live deadline). Spec: `docs/sharepoint-entry-pivot.md`.

**ENTRY-LAYER FORK (2026-06-18) — self-hosted web app (Phase 3b), likely to supersede 3a.** A containerized **Next.js + TypeScript** app (Podman) is being spiked as the alternative to the SharePoint bridge: it reaches Fabric **server-side** (service-principal/OBO → zero per-user licensing), restores validation-at-save (no bridge replay), and is the same front end the pinned Postgres/Supabase move needs. In `webapp/` — skeleton + Auth.js Entra login wiring + nav/layout for all 8 screens, built and verified under Podman. Blocked on an Entra app registration, **IT-only in this tenant** (401 confirmed — [[project_entra_appreg_it_gated]]); bundled request `docs/it-request-entra-webapp-dev.md`, hosting brief `docs/brief-server-hosting-requirements.md` (target `data.tcrce.ca`). 3a (SharePoint) is the documented fallback. Branch `phase-3b-webapp`.

The facts below remain true of the canvas app itself:

App: **`Student Data Staff Portal`** (broader than MVP — Phase 5 adds viewer/admin dashboards). Full reference is `/power-apps-canvas-build`. Key resolved facts:
- **Build approach:** author Power Fx as YAML in `powerapps/sources/Src/*.pa.yaml`, pack via `pac canvas pack` (Claude packs via Bash), Studio only for bootstrap + visual polish. Pivoted from the Copilot hybrid (dropped — unreliable). See [[project_powerapps_build_approach]].
- **Writes go through wrapper stored procs** (`usp_Insert/Upsert/Delete*`), called via the dot-stripped form `Assessment_Warehouse.dbouspXxx({...})`. Patch/SubmitForm do NOT work against Fabric Warehouse. No `OUTPUT` clause in procs. See [[project_powerapps_write_pattern]].
- **BIGINT precision:** Power Fx Number is 16-digit safe; Fabric BIGINT IDENTITY is 19-digit → cast every exposed surrogate key to `VARCHAR(20)` in views, take VARCHAR(20) proc params. See [[project_powerapps_bigint_precision]].
- **Submission validation** is three-layer (client constrains inputs → proc input validation 51010+ → compute safety nets 51001–09); validate before writing. See [[project_submission_validation_strategy]].
- Standing patterns: loading-state (Clear+Refresh+ClearCollect, loaded flag, Gallery.Visible) [[project_powerapps_loading_state_pattern]]; responsive sizing (Parent.Height-relative) [[project_powerapps_responsive_sizing]]; brand `#0092C9` + Lato.

## Assessment model (resolved)

- Three `AssessmentType` values: **Reading / Writing / Math**, one type per `DimAssessmentWindow` row; concurrent efforts = multiple overlapping windows (NOT bundled). Math is post-MVP, scoring TBD. `ScaleSystem` is reading-specific (NULL for Writing/Math). Settled — don't re-litigate. See [[project_assessment_types]].
- Reading scale: vendor-neutral `EN_Reading` / `FR_Reading` naming — **never reference F&P** (political constraint) even though EN levels match A–Z. ReadingDelta = signed distance from the benchmark min/max for the window's dominant month; DT/TD submittable; Grade 7 carry-over of the Grade-6-June benchmark; Grade 8+ NOT carried. See [[project_reading_scale_design]].
- IPP tracking: `FactStudentIPP` (SCD Type 2, per StudentKey×Subject×ProgramFamily; `IsIPP` NULL=unresolved gate). Auto-created per applicability rules in `usp_MergeStudent`.

---

## Deployment state (current — watch this)

- **Deployed & live:** all dims/facts, all 5 merge procs + orchestrator + year-end close-out, 3 RLS views + window-context views, StaffSchoolAccess table, semantic model + 3 DAX roles, all write/delete procs (reading assessment, IPP, ingest-trigger, audit), data-quality suite. Power Apps: 8 screens built (see implementation-plan Step 18 status).
- **Source ahead of deployed (do NOT deploy yet):** the 5 `usp_Load*Staging` procs are updated *in source* to PowerSchool **sqlReport CSV** format (comma/quote/CRLF, `'*'` wildcard) but the warehouse still runs the **TAB direct-extract** ingest. Deploy the CSV loaders **only at cutover**, together with the new PS SQL reports being authored. Headers in the files say so. Don't deploy or regenerate test data as CSV until a cutover is explicitly scheduled.
- **App restyle — COMPLETE (7/7, validated 2026-06-12).** Direction B ported to all screens incl. scrRosterGrid (tint-column swap, classic-button conversions, loaded-flag gating). Waypoint build preserved: `powerapps/waypoints/Student Data Staff Portal.2026-06-11.direction-b-restyle-complete.msapp` (git-kept). Port bugs + patterns in `/power-apps-canvas-build` §3i/§7f/§7g.
- **scrStudentData cohort filters (built 2026-06-10) + Pack B Teacher filter (built 2026-06-12).** Centralized `colCohortFiltered`; multi-select Homeroom/Program/School (analyst-only)/Achievement/**Teacher** (admin/analyst-gated, fed by `vw_StudentCohortTeachers` — DEPLOYED). NOTE: per the licensing pivot these SQL-bound screens are maker-only until rebound to lists (admin port). The as-of-window recompute idea ("Pack C") remains deferred.
- **Entry-layer pivot (ACTIVE 2026-06-12)**: `sql/security/bridge_views.sql` authored NOT deployed (5 RLS-bypassing bridge views — never grant to users); `docs/sharepoint-entry-pivot.md` (spec) + `docs/it-request-entra-bridge.md` (ready to send; site URL TBD) + `docs/sharepoint-site-setup.md` (site + 4 list schemas). IT Entra registration = critical path.
- **Web-app fork (Phase 3b, started 2026-06-18)**: `webapp/` — Next.js 15 + TS, containerized (Podman; build + run verified, all routes 200). Built: server-only Fabric connection (`queryAsUser` w/ `@UPN`), Auth.js Entra login wiring (round-trip UNTESTED — app reg IT-gated), navigation + layout scaffold for all 8 screens (placeholder data), TCRCE logo + favicon package. NOT done: live auth, Fabric read/write, real data binding. Branch `phase-3b-webapp` (unmerged; PR open against main).
- **Test-data baseline** (small synthetic set): ~21 students, 2 assessment windows (EN + FR P–6, both Open), reading-scale + benchmark seeds, a handful of FactAssessmentReading rows + FactStudentIPP placeholders. Exact end-of-session counts live in [[project_session_archive]]. A temporary `jeffrey.raine@tcrce.ca` RegionalAnalyst row exists for self-test; replaced automatically on the first real PS ingest (PS Group 40 → RegionalAnalyst).

## Open / deferred decisions

- **Entry-layer build (ACTIVE) — 3a vs 3b:** two $0-per-user paths in flight. **3b (self-hosted Next.js web app)** is the favored direction, being de-risked (Entra auth round-trip → then Fabric read/write) and likely to supersede **3a (SharePoint-list bridge, Fabric-side)**. Decide once the 3b spike confirms; until then **don't send the 3a bridge-daemon IT request** (`it-request-entra-bridge.md`) — it would provision an unused identity. Both gated on an IT-only Entra registration ([[project_entra_appreg_it_gated]]). See [[project_licensing_pivot_2026_06]].
- **Pilot timing:** targets a **fall assessment window** (date TBD by user). July–August is unavailable — both pilot teachers AND the project lead are 10-month staff, and build happens only in working sessions. June = de-risk 3b + get the IT request into the summer queue; substantive build resumes late Aug/Sept.
- **User's Power Apps premium trial expiry** — being verified; when it lapses, dev access to the SQL-bound app stops. Mitigate via PAYG link or one maker license. (Moot if 3b supersedes the canvas app.)
- **PINNED — Supabase/Postgres migration** (post-pilot, at the capacity right-sizing review): forward dollars favor it (~$41 vs $241 CAD/mo); privacy review (new vendor, CLOUD Act) is the long pole. Full analysis in [[project_licensing_pivot_2026_06]]. Strategic posture: pay Microsoft for identity/Teams/Power BI; own and keep portable everything they tax.
- **Stakeholder divergence:** FSL Coordinator wants the "Relative to End-of-June Target" metric for FI; English Literacy Coordinator does NOT for English. Schema supports both; visibility per-program-family. Don't auto-extend a single-coordinator ask across both families. See [[project_stakeholder_preferences]].
- **Coaches role:** no "coach" RoleCode exists; access depends on which PS Group PS assigns (board coaches likely Group 40→RegionalAnalyst; school coordinator-coaches likely Group 22→Teacher). Unconfirmed — needs PS admin.
- **Scope:** all three roles (teacher/admin/analyst) must be demonstrated in MVP — demographic slicers + admin/analyst filters are IN scope (don't park them). The user owns scope; surface tradeoffs as questions. See [[feedback_no_unilateral_scope_decisions]].
- **Capacity right-sizing review** Apr–May 2026 (F8→F2 decision before the 2026-2027 budget cycle).
- Automated ingest (post-MVP); Teams app-catalog embed (Step 27, post-pilot — pilot is direct Power Apps share); writing assessments + Power BI analyst reports (Phase 5).

---

## Conventions & working agreements (quick index — full text in the linked memories)

- **Numbers:** never comma thousands separators; space above 9999 in prose; bare in code. [[feedback_number_formatting]]
- **PS = PowerSchool** in chat. [[feedback_abbreviations]]
- **Project email:** `jeffrey.raine@tcrce.ca` (ignore the auto-memory `jeff.raine@gnspes.ca`). [[feedback_project_email]]
- **Percentages:** 1 decimal on charts, 2 in tables. [[feedback_percent_decimal_precision]]
- **Time zone:** store UTC, display/compare Atlantic via `AT TIME ZONE`. [[project_timezone_convention]]
- **Compliance:** proactively flag PII/residency exposure even when the user likely has it handled; never route real PS PII through Claude. [[feedback_compliance_flagging]]
- **Don't prompt for session wrap**; **no claims of between-turn/background work**; **clickable file links** in action instructions; **don't dictate Studio UI menu paths**; **SQL reserved aliases** (RowCount/Group/Current) and **Power Fx identifier column args** are recurring pre-flight items. See the respective feedback memories in MEMORY.md.

> Maintenance: keep this file lean and current. New durable decisions edit the relevant section here (replacing, not appending, the prior state). Session-by-session narrative goes to [[project_session_archive]] and `docs/implementation-plan.md` Left Off notes — NOT here.
