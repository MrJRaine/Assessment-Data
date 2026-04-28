# Regional Student Assessment Data Platform

## Project Overview

Centralized platform for collecting and analyzing student reading/writing assessments across a regional school system in Nova Scotia, Canada.

- ~6000 students (grades Primary–12), ~200 teachers
- **Compliance**: PIIDPA — all data must remain in **Canada East** region
- **Status**: Pre-MVP development
- **MVP (June 2025)**: French Immersion pilot, 5–10 teachers, reading assessments only
- **Full rollout (September 2025)**: All programs (EN + FR), all schools, ~200 teachers

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Storage | Microsoft Fabric Warehouse (SQL), Canada East, F8 capacity |
| Ingestion | OneLake CSV landing zone + Fabric Data Pipelines |
| Entry | Power Apps canvas apps embedded in Microsoft Teams |
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

### 4. Data Residency
All storage, compute, and processing must run in **Canada East**. No third-party connectors that route data outside Canada.

## Star Schema

**Fact tables**: `FactEnrollment`, `FactAssessmentReading`, `FactAssessmentWriting`, `FactSubmissionAudit`

**Dimensions**: `DimStudent`, `DimStaff`, `DimSection`, `DimSchool`, `DimAssessmentWindow`, `DimCalendar`, `DimReadingScale`

**Security tables**: `RLS_UserSchoolAccess`, `RLS_UserSectionAccess`

## SQL Coding Standards

- Surrogate keys: `INT IDENTITY`
- Always include `LastUpdated DATETIME DEFAULT GETDATE()`
- SCD Type 2 index: `IX_[BusinessKey]_IsCurrent`
- Required file header: Table name, purpose, SCD type, dates, region note

## Full Technical Reference

Use `/regional-assessment-platform` skill for complete specs: full table schemas, SCD merge procedure templates, RLS view SQL, Power Apps data flow, MVP critical path, and cost breakdown.
