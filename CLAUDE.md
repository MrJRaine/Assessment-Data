# Regional Student Assessment Data Platform

## Authority and Access — READ FIRST (binding, non-negotiable)

These are working agreements, not preferences. They lived only as practice for months, which is
exactly why they got broken: practice does not survive context compaction, but this file does.
**Treat silence in these rules as a prohibition, not as permission.**

### Claude NEVER executes anything against the Fabric warehouse

Not writes. Not reads. Not diagnostics. Not `sys.*` metadata checks. **Dev and live alike** — the
`_Dev` warehouse is NOT a sandbox. No `podman exec` running a `mssql` / `ClientSecretCredential`
script, no other route. There is no exception for "just checking", "only synthetic rows", "verifying
my own fix", or "saving a round trip".

**The user runs all SQL and reports the results.** Claude writes SQL to a tracked file in the repo,
links it, and states what it does and what it would change. Diagnostics get handed over the same way:
write the query, say what each possible result would mean, let the user run it. The value of a
diagnostic was never in question — who executes it is.

### Claude's own lane (act freely, no need to ask)

Internet searches · local file changes in this repo · `gh` · `podman`.

Keeping GitHub backed up is **Claude's responsibility**: commit *and push* at logical checkpoints,
without being asked. Don't micro-commit every edit; don't go silent. **Open PRs only when instructed.**

### Decisions: propose → get assent → implement

The user decides **what the app does**, **how the assessments function**, **how we work together**,
and **how a proposed change is structured**. Before implementing, Claude presents a 50-ft view:

- what the change does / what it looks for
- **which tables and fields it reads and writes**
- the shape of the approach

Once that is approved, implementation details are Claude's. The user follows the file edits and
reasoning as they land and asks about specifics then — so narrate while working, but get the nod first.

Announcing an action afterward is **not** permission. Noticing friction in a workflow is a reason to
*raise* it, never to trial a change and narrate it.

### The default when these rules are silent

Act like a **junior developer working under a senior developer**. A junior does not touch shared
databases; brings the approach to the senior before building; keeps their own branch backed up without
being asked; does not rewrite team process over a shortcut; reports a bug rather than quietly
hotfixing a shared environment. Their judgment is trusted on implementation detail — not on scope,
methodology, or process.

Full detail and the incident history: memory `feedback_sql_write_authorization`.

## Project Overview

Centralized platform for collecting and analyzing student reading/writing assessments across a regional school system in Nova Scotia, Canada.

- ~6000 students (grades Primary–12), ~200 teachers
- **Compliance**: PIIDPA — all data must remain in a **Canadian region**. Fabric workspace deliberately deployed to **Canada East**; other components (Power Automate, etc.) only need to be in *some* Canadian region (Canada East or Canada Central are both valid).
- **Status**: Pre-MVP development
- **MVP (June 2026)**: French Immersion pilot, 5–10 teachers, reading assessments only
- **Full rollout (September 2026)**: All programs (EN + FR), all schools, ~200 teachers

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Storage | Microsoft Fabric Warehouse (SQL), Canada East, F8 capacity |
| Ingestion | OneLake CSV landing zone + Fabric Data Pipelines |
| Entry | Power Apps canvas apps embedded in Microsoft Teams — **data layer is SharePoint lists** (the SQL connector is PREMIUM and banned for end users; see `docs/sharepoint-entry-pivot.md`) |
| Automation | Power Automate (standard connectors only) |
| Analytics | Power BI semantic models (10 A5 users only) |
| Identity | Entra ID / USERPRINCIPALNAME() for RLS |

## Critical Architecture Rules

### 1. Use Surrogate Keys in ALL Fact Tables
Fact tables must reference surrogate keys (`StudentKey`, `StaffKey`, `SectionKey`), **never** business keys (`StudentID`, `StaffID`). SCD Type 2 creates new surrogate keys on change — using business keys breaks historical accuracy.

### 2. SCD Type 2 Dimensions
- `DimStudent` — tracks grade, school, program changes
- `DimStaff` — tracks school and role changes
- `DimSection` — tracks teacher reassignments
- `DimSchool` — SCD Type 1 (overwrite only)

Always filter on `IsCurrent = 1` when querying current state.

### 3. RLS Is Enforced at the Semantic/View Layer
RLS is **not** enforced at Fabric storage. Enforce it via:
- Secured SQL views in Fabric Warehouse (filter by `USERPRINCIPALNAME()`)
- RLS roles in Power BI semantic models
- Power Apps reads from secured views only — **never** grant teachers direct workspace access

### 4. $0 Per-User Licensing (binding constraint, 2026-06-12)
No premium connectors, premium licenses, or pay-as-you-go in any END-USER path — teachers and admins run entirely on what M365 A3 includes (standard connectors). The SQL Server connector is premium: end-user apps bind to SharePoint lists; the warehouse is reached only by the Fabric-side bridge (`docs/sharepoint-entry-pivot.md`). When proposing ANY connector/service, state its license class and per-user cost at full rollout in the same breath (see memory `feedback_licensing_gate_on_design`).

### 5. Data Residency
PIIDPA requires all storage, compute, and processing to run in a **Canadian region** — either Canada East or Canada Central qualifies. The Fabric workspace is deliberately deployed to **Canada East** as the project's chosen primary region; new components (Power Automate environments, etc.) should default to Canada East for consistency but Canada Central is also PIIDPA-compliant if Canada East isn't an option. No third-party connectors that route data outside Canada.

## Star Schema

**Fact tables**: `FactEnrollment`, `FactAssessmentReading`, `FactAssessmentWriting`, `FactSubmissionAudit`

**Dimensions**: `DimStudent`, `DimStaff`, `DimSection`, `DimSchool`, `DimAssessmentWindow`, `DimCalendar`, `DimReadingScale`

**Security tables**: `RLS_UserSchoolAccess`, `RLS_UserSectionAccess`

## SQL Coding Standards

- Surrogate keys: `INT IDENTITY`
- Always include `LastUpdated DATETIME DEFAULT GETDATE()`
- SCD Type 2 index: `IX_[BusinessKey]_IsCurrent`
- Required file header: Table name, purpose, SCD type, dates, region note

## Project Skills (read on demand — not all auto-discovered)

The `.claude/skills/` directory contains six project-local skills. The harness does not always surface them in the auto-loaded skill list, so treat the table below as authoritative — read the file directly when the trigger applies.

| Skill | When to read |
|---|---|
| `.claude/skills/session-start.md` | At the start of every session (also enforced by a `SessionStart` hook in `.claude/settings.json`) |
| `.claude/skills/session-wrap.md` | When the user signals end-of-session ("wrap up", "session wrap", "let's stop here", or similar) |
| `.claude/skills/machine-setup.md` | First time working on a new machine ("set up this machine"), or when session-start finds MEMORY.md was not auto-injected (missing memory junction) |
| `.claude/skills/regional-assessment-platform.md` | Any work touching the data model, SCD logic, RLS, or architecture decisions for this platform |
| `.claude/skills/power-apps-canvas-build.md` | Any Power Apps work — screens, YAML sources in `powerapps/sources/`, Power Fx formulas, pack/unpack |
| `.claude/skills/fabric-warehouse-sql.md` | Any time you write, review, or debug T-SQL that will run in `Assessment_Warehouse` (Fabric Warehouse has significant T-SQL limitations vs. standard SQL Server) |

## Full Technical Reference

Use `/regional-assessment-platform` skill for complete specs: full table schemas, SCD merge procedure templates, RLS view SQL, Power Apps data flow, MVP critical path, and cost breakdown.
