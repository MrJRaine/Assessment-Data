---
name: regional-assessment-platform
description: Technical architecture and implementation guide for a regional student assessment data platform in Microsoft Fabric. Use this skill when working on database design, Power Apps development, data modeling, ETL processes, RLS implementation, or any technical decisions related to this specific student assessment project. Trigger whenever the user mentions the assessment platform, Fabric warehouse setup, SCD implementation for student/staff/section dimensions, Power Apps forms for teacher data entry, or asks about project architecture decisions.
---

# Regional Student Assessment Data Platform

## Writing Conventions (user preference)

**Never use comma as a thousands separator** in any output — chat, docs, code comments, SQL, commit messages. Write `5844` not `5,844`. For numbers above 9999 in prose, use a space: `10 000`. For numbers ≤ 9999, no separator at all. The user reads commas as decimal points (French primary/secondary education) and finds the standard thousands-separator confusing.

## Project Context

**Purpose**: Centralized platform for collecting and analyzing student reading and writing assessments across a regional school system.

**Scale**:
- ~6000 students (grades Primary to 12)
- ~200 teachers across multiple schools
- 6 reading assessment pulls per year
- 3 writing assessment pulls per year
- 10-year data retention

**Timeline**:
- **MVP by June 2025**: French Immersion pilot with small teacher group
- **Full rollout September 2025**: All programs (English + French)

**Compliance**: 
- Canadian data residency required (PIIDPA)
- All data in Canada East region
- Row-level security enforced at data layer

---

## Technology Stack

### Core Platform
**Microsoft Fabric F8 Capacity**
- Monthly cost: $964.34 CAD (grant-funded)
- Canada East region
- 8 Capacity Units (CUs)

### Licensing
**Existing baseline**:
- All teachers/school admins: Microsoft 365 A3
- Includes: Power Apps (Teams-embedded), Power Automate (standard), Power BI (free tier)

**Incremental licensing**:
- 10 region-level analytics users: A3 → A5 upgrade
- Cost: $72/user/year = $720/year total

### Data Sources
**PowerSchool SIS**:
- Manual CSV exports (scheduled basis)
- Student demographics, staff, schools, enrollment data
- No real-time integration required

### Application Layer
**Power Apps (Canvas Apps)**:
- Teacher assessment entry forms
- School-level monitoring dashboards
- Embedded in Microsoft Teams
- Direct connection to Fabric warehouse views

**Power Automate**:
- CSV file ingestion triggers
- Data validation
- Submission logging
- Uses standard connectors only (no premium)

**Power BI**:
- Region-level analytics only (10 A5 users)
- Connects to Fabric semantic models
- Teachers/admins do NOT need Power BI access

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│ ENTRY LAYER                                             │
│ Power Apps (Teams-embedded) → Teacher data entry       │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ INGESTION LAYER                                         │
│ Power Automate → CSV validation → Fabric Pipeline      │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ STORAGE LAYER (Microsoft Fabric - Canada East)         │
│ Fabric Warehouse (SQL) → Star schema with SCD Type 2   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ SECURITY LAYER                                          │
│ Secured SQL views with RLS → Filter by user identity   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ PRESENTATION LAYER                                      │
│ Teachers: Power Apps with embedded visuals             │
│ Admins: Power Apps school dashboards                   │
│ Region: Power BI reports (A5 users)                    │
└─────────────────────────────────────────────────────────┘
```

---

## Data Model

### Star Schema Design

**Fact Tables**:
- `FactEnrollment` - Student-to-section assignments
- `FactSectionTeachers` - Teacher-to-section assignments (bridge, supports co-teaching)
- `FactAssessmentReading` - Reading assessment results
- `FactAssessmentWriting` - Writing assessment results
- `FactSubmissionAudit` - Ingestion and submission tracking

**Dimension Tables** (with SCD specifications):
- `DimStudent` - **SCD Type 2** (track grade/school/program changes)
- `DimStaff` - **SCD Type 2** (track school/role changes)
- `DimSection` - **SCD Type 2** (track teacher reassignments)
- `DimSchool` - **SCD Type 1** (overwrite, no history needed)
- `DimAssessmentWindow` - Pull schedule and applicability
- `DimCalendar` - Time dimension for analysis
- `DimProgram` - PowerSchool program code reference (GradeBand, ProgramFamily, IsImmersion, SpecialtyType)
- `DimReadingScale` - Reading level reference values

**Security Views**:
- `vw_StaffSchoolAccess` - School-level authorization for admins and regional analysts, derived live from `FactStaffAssignment` at query time (no rebuild step, no drift risk)
- Teacher-level section access is derived from `FactSectionTeachers` at query time — no separate RLS table

### Critical Design Principle: Use Surrogate Keys

**ALL fact tables must reference surrogate keys, not business keys:**

```sql
-- ✓ CORRECT
CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID INT PRIMARY KEY IDENTITY,
    StudentKey INT NOT NULL,              -- Surrogate key
    EnteredByStaffKey INT NOT NULL,       -- Surrogate key
    SectionKey INT,                        -- Surrogate key
    AssessmentWindowID INT,
    ...
    FOREIGN KEY (StudentKey) REFERENCES DimStudent(StudentKey)
);

-- ✗ WRONG - Don't use business keys
CREATE TABLE FactAssessmentReading (
    StudentNumber BIGINT,  -- Business key - breaks with SCD Type 2!
    ...
);
```

**Why**: When a student changes grade/school, a new StudentKey is created. Assessments must link to the correct version of the student record based on when the assessment occurred.

---

## Dimension Table Specifications

### DimStudent (SCD Type 2)

**Purpose**: Track student profile over time as they progress through grades/schools

**Schema**:
```sql
-- Conceptual schema. See sql/dimensions/DimStudent.sql for Fabric Warehouse-compatible DDL
-- (VARCHAR not NVARCHAR, BIGINT IDENTITY, no constraints, no indexes, etc.)
CREATE TABLE DimStudent (
    StudentKey          BIGINT NOT NULL IDENTITY,  -- Surrogate key, unique per version
    StudentNumber       BIGINT NOT NULL,           -- Business key: provincial 10-digit student number
    FirstName           VARCHAR(100),
    MiddleName          VARCHAR(100),              -- Nullable; disambiguates same-name students in the same school/grade
    LastName            VARCHAR(100),
    DateOfBirth         DATE,
    CurrentGrade        VARCHAR(10),               -- Triggers new version
    CurrentSchoolID     INT,                       -- Triggers new version
    ProgramCode         VARCHAR(10),               -- Triggers new version, e.g. 'E015', 'S115'
    EnrollStatus        INT,                       -- PS Enroll_Status: 0 = Active, 2 = Inactive, 3 = Graduated, -1 = Pre-Enrolled
    Homeroom            VARCHAR(50),               -- PS Home_Room
    Gender              VARCHAR(10) NOT NULL,      -- PS Gender
    SelfIDAfrican       BIT,                       -- PS NS_AssignIdentity_African — student self-ID as African descent
    SelfIDIndigenous    BIT,                       -- PS NS_aboriginal — student self-ID as Indigenous descent
    CurrentIPP          BIT,                       -- PS CurrentIPP — has at least one IPP
    CurrentAdap         BIT,                       -- PS CurrentAdap — has adaptations
    EffectiveStartDate  DATE NOT NULL,
    EffectiveEndDate    DATE NULL,                 -- NULL = current version
    IsCurrent           BIT NOT NULL,              -- 1 = current, 0 = historical
    SourceSystemID      VARCHAR(50),               -- PowerSchool DCID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)
);
```

**SCD policy: every business attribute is Type 2.** Any change creates a new versioned row. The only fields exempt from versioning are the lifecycle/audit columns: `StudentKey`, `StudentNumber`, `EffectiveStartDate`, `EffectiveEndDate`, `IsCurrent`, `SourceSystemID`, `LastUpdated`.

**Rationale:** reports often cite point-in-time values (e.g. "X students with IPPs in Q3 2025"). Without Type 2 on these attributes, a later re-run would produce different numbers when names, homerooms, IPP statuses, etc. change — sending stakeholders chasing phantom discrepancies. Treating every business field as Type 2 makes any historical query reproducible.

**Type 2 trigger fields:**
- `CurrentGrade` - Student promoted
- `CurrentSchoolID` - Student transferred schools
- `ProgramCode` - Program change (see DimProgram for valid codes)
- `EnrollStatus` - Active/Inactive/Graduated/Pre-Enrolled state changes
- `FirstName`, `MiddleName`, `LastName` - Name changes or corrections
- `DateOfBirth` - Data corrections
- `Homeroom` - Homeroom reassignment
- `Gender` - Gender update
- `SelfIDAfrican`, `SelfIDIndigenous` - Self-ID flag updates
- `CurrentIPP`, `CurrentAdap` - IPP/adaptations status changes

**Note on business key:** `StudentNumber` is the provincial 10-digit student ID (PowerSchool's "Student Number" field). It's more stable than PowerSchool's internal DCID — it follows the student across schools, regions, and re-enrollments. `SourceSystemID` stores the PowerSchool DCID for reference only, not for matching.

### DimStaff (SCD Type 2) + FactStaffAssignment (bridge)

**Purpose**: Track staff identity over time, with per-school/per-role detail split into a bridge table. DimStaff is pure person identity; FactStaffAssignment preserves the full PowerSchool export grain (email × school × role).

**Why split?** PS emits one row per staff-school-role combination. A vice-principal who also teaches one class at the same school appears twice; an itinerant specialist at five schools appears five times. Collapsing that to a single "winning" role on DimStaff would lose information. The bridge preserves full grain; DimStaff answers "who is this person?" without lying about their assignments.

**DimStaff schema**:
```sql
-- Conceptual schema. See sql/dimensions/DimStaff.sql for Fabric Warehouse-compatible DDL.
CREATE TABLE DimStaff (
    StaffKey            BIGINT NOT NULL IDENTITY,  -- Surrogate key, unique per version
    Email               VARCHAR(255) NOT NULL,     -- Business key (Entra ID UPN, lowercased)
    FirstName           VARCHAR(100),
    LastName            VARCHAR(100),
    Title               VARCHAR(100) NULL,         -- PS Title (e.g. "Vice Principal")
    HomeSchoolID        VARCHAR(10) NULL,          -- Primary school (NULL for itinerant staff)
    CanChangeSchool     VARCHAR(255) NULL,         -- Raw PS semicolon-separated school list
    IsDistrictLevel     BIT,                       -- Derived (1 if '0' present in CanChangeSchool)
    ActiveFlag          BIT,                       -- Derived at ingest via import reconciliation
    AccessLevel         VARCHAR(50) NULL,          -- Type 1 — derived per-person from FactStaffAssignment highest-priority school-tier role: 'RegionalAnalyst' / 'Administrator' / 'SpecialistTeacher'. NULL for staff with no school-tier access.
    EffectiveStartDate  DATE NOT NULL,
    EffectiveEndDate    DATE NULL,
    IsCurrent           BIT NOT NULL,
    LastUpdated         DATETIME2(0)
);
```

**SCD policy: every business attribute is Type 2 — with one exception.** Any change to `FirstName`, `LastName`, `Title`, `HomeSchoolID`, `CanChangeSchool`, `IsDistrictLevel`, or `ActiveFlag` creates a new versioned row. `AccessLevel` is **Type 1** (overwrite) — it's a denormalized snapshot of the person's highest-priority school-tier RoleCode in `FactStaffAssignment`, computed at ingest. Historical AccessLevel is recoverable from `FactStaffAssignment`'s own Type 2 history, so DimStaff doesn't need to version it. Lifecycle/audit columns exempt from versioning: `StaffKey`, `Email`, `EffectiveStartDate`, `EffectiveEndDate`, `IsCurrent`, `LastUpdated`. Same rationale for the Type 2 attributes as `DimStudent`: reports cite point-in-time values and must be reproducible regardless of intervening name corrections, school reassignments, or access changes.

`RoleCode` and `SourceSystemID` are NOT on DimStaff — those moved to `FactStaffAssignment` (or are inapplicable because of the collapse). The three per-person access columns (`HomeSchoolID`, `CanChangeSchool`, `IsDistrictLevel`) live here because they describe the person, not a specific assignment — PS sources them from a joined table and emits the same values on every row of a multi-row staff member.

**FactStaffAssignment schema** (one row per distinct email × school × role):
```sql
CREATE TABLE FactStaffAssignment (
    StaffAssignmentID   BIGINT NOT NULL IDENTITY,
    StaffKey            BIGINT NOT NULL,           -- FK to DimStaff
    SchoolID            VARCHAR(10) NOT NULL,
    RoleCode            VARCHAR(50) NOT NULL,      -- 'Teacher', 'SpecialistTeacher', 'Administrator', 'RegionalAnalyst', 'ProvincialAnalyst', 'SupportStaff' (translated from PS Group via DimRole)
    EffectiveStartDate  DATE NOT NULL,
    EffectiveEndDate    DATE NULL,                 -- NULL = currently held
    IsCurrent           BIT NOT NULL,
    SourceSystemID      VARCHAR(50),               -- PS staff record ID; CHANGE here triggers a new version (email-reuse collision detection)
    LastUpdated         DATETIME2(0)
);
```

**SCD semantics — both tables need reconciliation**:

| Event | DimStaff | FactStaffAssignment |
|---|---|---|
| New email in import | INSERT with ActiveFlag=1 | INSERT one row per school×role |
| Existing, present, all business fields match | No-op (touch LastUpdated) | No-op if triple unchanged AND SourceSystemID matches; otherwise reconcile |
| Existing, present, ANY business field differs (name correction, HomeSchoolID change, access list change, etc.) | Type 2 close + new version with updated values | Reconcile triples independently; SourceSystemID change on an existing triple closes + reopens (collision detection) |
| Existing, absent from import | Type 2 close + new inactive (ActiveFlag=0) | Type 2 close all current rows for that StaffKey |
| Returning (inactive → present) | Type 2 close + new active (ActiveFlag=1) | Fresh INSERTs for current school×role triples |

**ActiveFlag lifecycle**: `ActiveFlag` is NOT pulled from PowerSchool — the staff export comes from a PS report pre-filtered to currently active staff (teachers + specialists + admins). Inclusion implies active. The merge procedure derives `ActiveFlag` via anti-join reconciliation. "Inactive" does NOT mean "no longer employed" — it means the person dropped out of the active-staff report this cycle (on leave, sabbatical, retired, role change, left region).

**Note on business key:** `Email` is the business key, not a PowerSchool ID. There's no `SourceSystemID` on DimStaff because multiple PS records can collapse into one DimStaff row — the PS record ID is preserved per-row on FactStaffAssignment instead.

### DimSection (SCD Type 2)

**Purpose**: Track instructional groupings and teacher assignments

**Schema**:
```sql
CREATE TABLE DimSection (
    -- Surrogate key
    SectionKey INT PRIMARY KEY IDENTITY,
    
    -- Business key
    SectionID NVARCHAR(50) NOT NULL,
    
    -- Attributes
    SchoolID INT,
    TermID INT,                           -- PS TermID (e.g. 3501); joins to DimTerm
    CourseCode NVARCHAR(50),
    SectionNumber NVARCHAR(20),           -- School-set, e.g. '01', '02'; Power App display
    CourseName NVARCHAR(200),             -- Human-readable course name; Power App display
    EnrollmentCount INT,                  -- Stored to avoid re-aggregating FactEnrollment
    MaxEnrollment INT,                    -- Capacity; lower for special programs
    TeacherStaffKey INT,                  -- FK to DimStaff surrogate key!
    
    -- SCD Type 2 tracking
    EffectiveStartDate DATE NOT NULL,
    EffectiveEndDate DATE NULL,
    IsCurrent BIT NOT NULL DEFAULT 1,
    
    -- Metadata
    SourceSystemID NVARCHAR(50),
    LastUpdated DATETIME DEFAULT GETDATE(),
    
    FOREIGN KEY (TeacherStaffKey) REFERENCES DimStaff(StaffKey),
    INDEX IX_SectionID_IsCurrent (SectionID, IsCurrent)
);
```

**SCD policy: every business attribute is Type 2.** Any change to `SchoolID`, `TermID`, `CourseCode`, `SectionNumber`, `CourseName`, `EnrollmentCount`, `MaxEnrollment`, or `TeacherStaffKey` creates a new versioned row. Same rationale as `DimStudent` and `DimStaff`. Note: `EnrollmentCount` shifts as students enroll/withdraw, so DimSection accumulates versions throughout the school year — acceptable at pilot volume.

**No cascade to `FactSectionTeachers`.** That bridge keys on `SectionID` (business key) and `TeacherEmail` directly, so it survives DimSection versioning untouched. Teacher reassignments are reconciled directly within the bridge by the (`SectionID`, `TeacherEmail`, `TeacherRole`) triple. `DimSection.TeacherStaffKey` remains a denormalized "primary teacher of record" snapshot for reporting only — not used for access control.

### DimSchool (SCD Type 1)

**Purpose**: School reference data

**Schema**:
```sql
CREATE TABLE DimSchool (
    SchoolID INT PRIMARY KEY,             -- Natural key is fine
    SchoolName NVARCHAR(200),
    Community NVARCHAR(100),
    ActiveFlag BIT,
    LastUpdated DATETIME DEFAULT GETDATE()
);
```

**Why Type 1**: Schools rarely change, and when they do (name change, closure), historical tracking isn't needed for assessment analysis.

### DimAssessmentWindow

**Purpose**: Define when assessments are collected and for whom

**Schema**:
```sql
CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID INT PRIMARY KEY,
    WindowName NVARCHAR(100),             -- e.g., "Fall 2025 Reading - Primary"
    AssessmentType NVARCHAR(20),          -- 'Reading' or 'Writing'
    SchoolYear NVARCHAR(9),               -- '2025-2026'
    StartDate DATE,
    EndDate DATE,
    
    -- Grade Level Applicability
    AppliesTo NVARCHAR(50),               -- 'Primary', 'Elementary', etc.
    MinGrade NVARCHAR(10),                -- 'P' or '1' or '7'
    MaxGrade NVARCHAR(10),                -- '6' or '12'
    
    -- Program Filter
    ProgramCode NVARCHAR(10),             -- 'FR', 'EN', or NULL for all
    
    -- Operational flags
    ActiveFlag BIT,
    IsCurrentWindow BIT,                  -- Only one active per type
    
    -- Metadata
    CreatedDate DATETIME DEFAULT GETDATE(),
    CreatedBy NVARCHAR(100)
);
```

**Example - June MVP**:
```sql
INSERT INTO DimAssessmentWindow VALUES (
    1,
    'June 2025 Reading - French Immersion Pilot',
    'Reading',
    '2024-2025',
    '2025-06-01',
    '2025-06-30',
    'All',
    'P',
    '12',
    'FR',      -- French only
    1,         -- Active
    1,         -- Current
    GETDATE(),
    'system'
);
```

### DimReadingScale

**Purpose**: Reading level benchmarks by grade and program

**Schema**:
```sql
CREATE TABLE DimReadingScale (
    ReadingScaleID INT PRIMARY KEY,
    ProgramCode NVARCHAR(10),             -- 'EN' or 'FR'
    Grade NVARCHAR(10),
    ScaleValue NVARCHAR(10),              -- Reading level code
    ExpectedMidYear NVARCHAR(10),         -- Benchmark expectation
    Description NVARCHAR(200)
);
```

### DimCalendar

**Purpose**: Standard time dimension for date-based analysis

**Schema**:
```sql
CREATE TABLE DimCalendar (
    DateKey INT PRIMARY KEY,              -- YYYYMMDD format
    Date DATE,
    SchoolYear NVARCHAR(9),               -- '2025-2026'
    Month INT,
    MonthName NVARCHAR(20),
    Quarter INT,
    Week INT,
    DayOfWeek INT,
    IsSchoolDay BIT
);
```

---

## Fact Table Specifications

### FactEnrollment

**Purpose**: Track student membership in sections over time

**Schema**:
```sql
CREATE TABLE FactEnrollment (
    EnrollmentID INT PRIMARY KEY IDENTITY,
    StudentKey INT NOT NULL,              -- Surrogate key
    SectionKey INT NOT NULL,              -- Surrogate key
    StartDate DATE,
    EndDate DATE,                         -- NULL if currently enrolled
    ActiveFlag BIT,
    
    FOREIGN KEY (StudentKey) REFERENCES DimStudent(StudentKey),
    FOREIGN KEY (SectionKey) REFERENCES DimSection(SectionKey)
);
```

**Notes**:
- Students typically have 6-10 concurrent enrollments
- ActiveFlag = 1 for current enrollments

### FactAssessmentReading

**Purpose**: Store reading assessment results

**Schema**:
```sql
CREATE TABLE FactAssessmentReading (
    ReadingAssessmentID INT PRIMARY KEY IDENTITY,
    StudentKey INT NOT NULL,              -- Surrogate key
    AssessmentWindowID INT,
    ReadingScaleID INT,                   -- Assigned reading level
    ReadingDelta INT,                     -- Difference from expected
    AssessmentDate DATE,
    EnteredByStaffKey INT,                -- Who submitted (surrogate key)
    SubmissionTimestamp DATETIME,
    
    FOREIGN KEY (StudentKey) REFERENCES DimStudent(StudentKey),
    FOREIGN KEY (AssessmentWindowID) REFERENCES DimAssessmentWindow(AssessmentWindowID),
    FOREIGN KEY (ReadingScaleID) REFERENCES DimReadingScale(ReadingScaleID),
    FOREIGN KEY (EnteredByStaffKey) REFERENCES DimStaff(StaffKey)
);
```

### FactAssessmentWriting

**Purpose**: Store writing assessment rubric scores

**Schema**:
```sql
CREATE TABLE FactAssessmentWriting (
    WritingAssessmentID INT PRIMARY KEY IDENTITY,
    StudentKey INT NOT NULL,
    AssessmentWindowID INT,
    
    -- Writing Rubric Scores
    IdeasScore INT,                       -- 1-4 scale
    OrganizationScore INT,
    LanguageScore INT,
    ConventionsScore INT,
    
    AssessmentDate DATE,
    EnteredByStaffKey INT,
    SubmissionTimestamp DATETIME,
    
    FOREIGN KEY (StudentKey) REFERENCES DimStudent(StudentKey),
    FOREIGN KEY (AssessmentWindowID) REFERENCES DimAssessmentWindow(AssessmentWindowID),
    FOREIGN KEY (EnteredByStaffKey) REFERENCES DimStaff(StaffKey)
);
```

### FactSubmissionAudit

**Purpose**: Track all data ingestion and submission activity

**Schema**:
```sql
CREATE TABLE FactSubmissionAudit (
    AuditID INT PRIMARY KEY IDENTITY,
    RecordType NVARCHAR(50),              -- 'Assessment', 'Enrollment', 'CSV Import'
    Source NVARCHAR(50),                  -- 'PowerSchool', 'Power Apps'
    SubmittedBy NVARCHAR(255),            -- User email
    SubmissionTimestamp DATETIME,
    Status NVARCHAR(50),                  -- 'Accepted', 'Rejected', 'Corrected'
    Message NVARCHAR(MAX),                -- Validation messages
    RecordCount INT
);
```

---

## SCD Type 2 Implementation

### Production Merge Procedure Conventions (established 2026-04-30)

The deployed merge procs are set-based and topic-scoped, NOT per-row parameter-driven. Canonical examples in `sql/procedures/`:
- `usp_MergeStudent` — single-table SCD merge (DimStudent only)
- `usp_MergeStaff` — two-table SCD merge (DimStaff + FactStaffAssignment in one proc, since FactStaffAssignment depends on the just-merged StaffKey)

**File-set per ingest topic (4 or 5 files):**
- `sql/staging/Stg_<Topic>.sql` — all-VARCHAR landing table; `COPY INTO` target
- `sql/staging/Wrk_<Topic>.sql` — typed working set with translations applied
- (For two-table topics, an additional `Wrk_<Topic2>.sql` for the second grain)
- `sql/procedures/usp_Load<Topic>Staging.sql` — TRUNCATE + COPY INTO; replaceable by Strategy B Pipeline (Step 29)
- `sql/procedures/usp_Merge<Topic>.sql` — Stg → Wrk → Dim/Fact SCD reconciliation

**Merge proc structure (every topic follows this):**
1. **Build Wrk from Stg** — apply ALL translations here (sentinel mappings, type casts, boolean encodings, NULL normalization, lowercasing). The reconciliation steps assume Wrk is already clean and typed.
2. **Phase: close changed-current rows** — UPDATE…JOIN where business fields differ. Use `WHERE EXISTS (SELECT w.fields EXCEPT SELECT d.fields)` for NULL-safe comparison across all Type 2 trigger fields.
3. **Phase: close missing-current rows** (if anti-join applies for this dimension)
4. **Phase: insert deactivation rows** (only if `close + replace` semantic — see anti-join semantics below)
5. **Phase: insert active versions** — combined NEW + just-closed-CHANGED + RETURNING in one INSERT…SELECT WHERE NOT EXISTS
6. **Phase: touch unchanged rows** — UPDATE LastUpdated WHERE EffectiveStartDate < @EffectiveDate (strict less-than means same-day re-runs read 0 touched, which is fine)
7. **Phase: refresh Type 1 columns** (only if the dimension has any — DimStaff.AccessLevel is currently the only one)
8. **Audit row insert** to FactSubmissionAudit with all counters.

**Anti-join semantics — picking close-only vs close-and-replace:**
- **Close-only (no replacement)**: when the absent state is multi-valued and we can't infer which value to use. Examples: DimStudent (could be Inactive/Graduated/Pre-Enrolled), FactStaffAssignment (a triple just stops existing). The row becomes `IsCurrent=0` with no new current row; downstream IsCurrent=1 filters naturally exclude it.
- **Close + insert replacement**: when the absent state is binary and we know exactly what to materialize. Example: DimStaff (`ActiveFlag=0` is the only possible inactive state). The replacement preserves last-known business fields with the inactive flag flipped.

**Required translations (applied in Wrk INSERT):**
- `Email` → `LOWER()` everywhere (matches Entra ID UPN)
- `SchoolID` → `RIGHT('0000' + value, 4)` (zero-pad to 4 chars)
- Sentinel `'0'` on `HomeSchoolID` → NULL; sentinel `'0'` on per-row `SchoolID` → `'0000'`
- `'999999'` (graduates pseudo-school) stripped from CanChangeSchool parsing
- Date columns: `MM/DD/YYYY` via `CONVERT(DATE, val, 101)`; empty → NULL
- Numeric casts via `CAST(val AS BIGINT)` / `CAST(val AS INT)`
- Boolean encodings (DimStudent): `'Yes'`/`''` → 1/NULL; `'1'`/`'2'`/`''` → 1/0/NULL; `'Y'`/`'N'`/`''` → 1/0/NULL
- Grade_Level: `'0'` → `'P'`, `'-1'` → `'PP'`, others verbatim
- DimRole resolution: `JOIN DimRole ON CAST(s.[Group] AS INT) = r.RoleNumber AND r.ActiveFlag = 1 AND r.RoleCode IS NOT NULL` — rows that don't match are excluded from FactStaffAssignment Wrk and counted as a warning

**Identifier quoting:** PS exports use `Group` as a column name — reserved word. Use `[Group]` (bracket-quoted) in T-SQL, not `"Group"` (relies on QUOTED_IDENTIFIER ON).

**`@EffectiveDate` parameter:** every merge proc takes `@EffectiveDate DATE = NULL`, defaults to today inside the proc body. Override only for backfill or replay.

**Audit message convention:** `usp_Merge<Topic>: <staged> staged | DimX: <inserted> inserts | <versioned> versioned (closed) | <deactivated> deactivated | <touched> touched`. For multi-table merges, separate per-table sections with ` || `. Append `[WARN: ...]` segments for any anomalies. Set `Status = 'AcceptedWithWarnings'` if any warning fires; otherwise `'Accepted'`.

**Migration ordering gotcha:** CREATE PROCEDURE doesn't validate column existence at compile time (deferred name resolution). A merge proc that references a column added by a separate `ALTER TABLE … ADD COLUMN` migration will create successfully on a pre-migration warehouse but fail at EXEC with `Invalid column name`. Always run column-add migrations BEFORE deploying merge procs that reference the new columns.

### Legacy Per-Row Merge Procedure Template (deprecated)

The template below is from an earlier per-row design and is NOT what the deployed procs use. Kept here for historical reference only — see `sql/procedures/usp_MergeStudent.sql` for the actual production pattern.

**For DimStudent** (adapt pattern for DimStaff and DimSection):

```sql
CREATE PROCEDURE usp_MergeStudent
    @StudentID INT,
    @StudentNumber NVARCHAR(50),
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100),
    @DateOfBirth DATE,
    @CurrentGrade NVARCHAR(10),
    @CurrentSchoolID INT,
    @ProgramCode NVARCHAR(10),
    @ActiveFlag BIT,
    @SourceSystemID NVARCHAR(50),
    @EffectiveDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ExistingKey INT;
    DECLARE @Changed BIT = 0;
    
    -- Find current version
    SELECT TOP 1 @ExistingKey = StudentKey
    FROM DimStudent
    WHERE StudentID = @StudentID 
      AND IsCurrent = 1;
    
    -- New student - insert first version
    IF @ExistingKey IS NULL
    BEGIN
        INSERT INTO DimStudent (
            StudentID, StudentNumber, FirstName, LastName, DateOfBirth,
            CurrentGrade, CurrentSchoolID, ProgramCode, ActiveFlag,
            EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID
        )
        VALUES (
            @StudentID, @StudentNumber, @FirstName, @LastName, @DateOfBirth,
            @CurrentGrade, @CurrentSchoolID, @ProgramCode, @ActiveFlag,
            @EffectiveDate, NULL, 1, @SourceSystemID
        );
    END
    ELSE
    BEGIN
        -- Check if Type 2 attributes changed
        SELECT @Changed = CASE 
            WHEN CurrentGrade != @CurrentGrade 
              OR CurrentSchoolID != @CurrentSchoolID 
              OR ProgramCode != @ProgramCode 
            THEN 1 
            ELSE 0 
        END
        FROM DimStudent
        WHERE StudentKey = @ExistingKey;
        
        IF @Changed = 1
        BEGIN
            -- Expire current record
            UPDATE DimStudent
            SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
                IsCurrent = 0
            WHERE StudentKey = @ExistingKey;
            
            -- Insert new version
            INSERT INTO DimStudent (
                StudentID, StudentNumber, FirstName, LastName, DateOfBirth,
                CurrentGrade, CurrentSchoolID, ProgramCode, ActiveFlag,
                EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID
            )
            VALUES (
                @StudentID, @StudentNumber, @FirstName, @LastName, @DateOfBirth,
                @CurrentGrade, @CurrentSchoolID, @ProgramCode, @ActiveFlag,
                @EffectiveDate, NULL, 1, @SourceSystemID
            );
        END
        ELSE
        BEGIN
            -- No Type 2 change, just update Type 1 fields
            UPDATE DimStudent
            SET FirstName = @FirstName,
                LastName = @LastName,
                StudentNumber = @StudentNumber,
                ActiveFlag = @ActiveFlag,
                LastUpdated = GETDATE()
            WHERE StudentKey = @ExistingKey;
        END
    END
END;
```

### CSV Import Process

**Power Automate → Fabric Pipeline flow**:

1. PowerSchool CSV uploaded to OneLake landing zone
2. Power Automate validates file structure
3. Triggers Fabric Data Pipeline
4. Pipeline reads CSV, calls merge procedures for each row
5. Logs results to FactSubmissionAudit

**Key point**: Use `@EffectiveDate = GETDATE()` for current imports, or actual event date if backfilling history.

---

## Row-Level Security (RLS)

### Critical Understanding

**WHERE RLS is enforced**: 
- At the Fabric semantic model level (Power BI dataset)
- Through secured SQL views in Fabric Warehouse

**WHERE RLS is NOT enforced**:
- Direct Fabric workspace access (members see everything via SQL endpoint)
- OneLake file access

**Implication**: Teachers and school admins must access data through:
- Power Apps (reading from secured views)
- Power BI reports (with RLS roles applied)
- Never direct workspace membership

### Security Views

**Teacher access - see only assigned students**:

```sql
CREATE VIEW vw_TeacherStudents
AS
SELECT 
    s.StudentKey,
    s.StudentID,
    s.FirstName,
    s.LastName,
    s.CurrentGrade,
    s.CurrentSchoolID,
    s.ProgramCode,
    t.Email AS TeacherEmail,
    sec.SectionKey,
    sec.CourseCode
FROM DimStudent s
JOIN FactEnrollment e ON s.StudentKey = e.StudentKey
JOIN DimSection sec ON e.SectionKey = sec.SectionKey
JOIN DimStaff t ON sec.TeacherStaffKey = t.StaffKey
WHERE s.IsCurrent = 1          -- Current student version
  AND sec.IsCurrent = 1        -- Current section version
  AND t.IsCurrent = 1          -- Current teacher version
  AND e.ActiveFlag = 1;        -- Active enrollment
```

**Filter in Power Apps or Power BI**:
```dax
-- DAX RLS role for teachers
[TeacherEmail] = USERPRINCIPALNAME()
```

**School administrator access - see all students in their school**:

```sql
CREATE VIEW vw_SchoolStudents
AS
SELECT 
    s.StudentKey,
    s.StudentID,
    s.FirstName,
    s.LastName,
    s.CurrentGrade,
    s.CurrentSchoolID,
    sch.SchoolName,
    adm.Email AS AdminEmail
FROM DimStudent s
JOIN DimSchool sch ON s.CurrentSchoolID = sch.SchoolID
JOIN vw_StaffSchoolAccess access
    ON s.CurrentSchoolID = access.SchoolID
WHERE s.IsCurrent = 1
  AND access.AccessLevel IN ('Administrator', 'RegionalAnalyst', 'SpecialistTeacher');
```

### RLS Derivation (no manual tables)

Access is derived from authoritative ingest fields — there are no manually-maintained RLS tables:

**School-level access** — `sql/security/vw_StaffSchoolAccess.sql`:

A pure unpacking view over DimStaff (no joins, no aggregation). Driven by three DimStaff fields:
- `AccessLevel` (Type 1 column on DimStaff) — staff member's highest-priority school-tier RoleCode, computed at ingest from FactStaffAssignment. NULL for staff with no school-tier role. Filter `WHERE AccessLevel IS NOT NULL` is the inclusion gate.
- `HomeSchoolID` — primary school contribution.
- `CanChangeSchool` — semicolon-separated list, parsed live in the view.

Output schema:
```
StaffKey | Email | SchoolID | AccessLevel
```

Parse rules for `CanChangeSchool` (semicolon-separated list):
- `999999` (graduates pseudo-school) → stripped
- `0` (district-level tier marker) → emitted as `'0000'` aggregate-row marker
- Any other integer → zero-padded to 4 chars (e.g. `79` → `'0079'`)

`AccessLevel` ordering (priority): `RegionalAnalyst > Administrator > SpecialistTeacher`. It's a person-tier indicator, not a per-school role claim. The merge proc resolves it once per person per ingest.

**Excluded entirely** (their `AccessLevel` is NULL, so no rows surface in the view):
- `Teacher` — section-level RLS via FactSectionTeachers, not school-level.
- `ProvincialAnalyst` — never authenticates to the PowerApp (not in security group).
- `SupportStaff` — no student-data access in the app.

The `'0000'` aggregate row only surfaces for school-tier staff who have `'0'` in their CanChangeSchool list.

**Section-level access** — derived from `FactSectionTeachers` directly in `vw_TeacherStudents`. The bridge stores `TeacherEmail` directly (business key), so RLS matches `USERPRINCIPALNAME()` without any DimStaff join:
```sql
-- Pattern used in vw_TeacherStudents
JOIN DimSection sec ON sec.SectionID = e.SectionID AND sec.IsCurrent = 1
JOIN FactSectionTeachers fst
    ON fst.SectionID = sec.SectionID
    AND fst.IsCurrent = 1
WHERE fst.TeacherEmail = USERPRINCIPALNAME()
```

---

## Power Apps Implementation

### Teacher Assessment Entry Form

**Requirements**:
- Embedded in Microsoft Teams
- Filter students by current section assignments
- Show only active assessment windows applicable to student grade/program
- Direct write to Fabric views
- Validate required fields before submission

**Data Flow**:
1. Teacher launches app in Teams
2. App authenticates via Entra ID (email = USERPRINCIPALNAME())
3. Loads students from `vw_TeacherStudents` filtered by teacher email
4. Loads active assessment windows from `DimAssessmentWindow` WHERE `IsCurrentWindow = 1`
5. Teacher selects student, window, enters assessment data
6. App writes to `FactAssessmentReading` or `FactAssessmentWriting`
7. Logs submission to `FactSubmissionAudit`

**Connection method**:
- Power Apps → Fabric SQL endpoint (may require custom connector)
- Alternative: Power Apps → Power BI dataset → Fabric (with writeback via Power Automate)

### School Monitoring Dashboard

**Requirements**:
- Show submission completion by teacher
- Filter by grade, program, assessment window
- Highlight missing submissions
- View submission trends over time

**Data source**:
- Read from `vw_SchoolStudents`
- Aggregate completion from fact tables

---

## MVP Implementation Plan (June 2025)

### Scope Reduction for Pilot

**In scope**:
- French Immersion students only
- 1-2 pilot schools
- 5-10 pilot teachers
- 1 assessment window (end-of-year)
- Reading assessments only (skip writing if time-constrained)

**Out of scope for June**:
- English program students
- Full region rollout
- Power BI dashboards (use basic Power Apps views)
- Automated PowerSchool ingestion (manual CSV uploads)
- School admin monitoring tools
- Historical data loads (start fresh)
- SCD Type 2 full implementation (snapshot current state only)

### Critical Path (8 weeks to June)

**Weeks 1-2: Foundation**
- Provision Fabric F8 workspace (Canada East)
- Initial PowerSchool data pull (French only)
- Create core warehouse tables (minimum viable schema)
- Set up 1 assessment window for pilot

**Weeks 3-4: Data Layer**
- Build FactAssessmentReading
- Create basic secured views with RLS
- Manual CSV import process (defer automation)
- Test RLS with pilot teacher accounts

**Weeks 5-6: Power Apps**
- Teacher entry form (single screen)
- Student dropdown, assessment fields, submit
- Basic validation
- Direct write to Fabric

**Week 7: Testing**
- Pilot teacher UAT
- Fix blocking issues only
- Document feedback for September

**Week 8: Buffer**
- Training materials
- Troubleshooting
- Final adjustments

### Biggest Risks

1. **Power Apps to Fabric connection** - Test immediately
2. **Fabric F8 provisioning delays** - Start ASAP
3. **PowerSchool data quality** - Validate French program codes
4. **Teacher availability** - Lock in early

---

## September Full Rollout Additions

**Scope expansion**:
- All students (English + French)
- All schools
- All teachers (~200)
- Multiple concurrent assessment windows
- Both reading and writing assessments
- Full SCD Type 2 implementation
- Automated CSV ingestion via Power Automate
- School admin dashboards
- Power BI analytics for region (10 A5 users)

**New components**:
- Historical backfill (if required)
- Advanced RLS roles (teachers, school admins, regional)
- Semantic model with incremental refresh
- Monitoring and capacity management
- Governance documentation

---

## Cost Summary

**Monthly recurring**:
- Fabric F8 capacity: $964.34 CAD

**Annual recurring**:
- 10 A5 upgrades: $720/year

**No additional costs for**:
- Power Apps (included in A3 when Teams-embedded)
- Power Automate standard connectors (included in A3)
- Power BI consumption by teachers (access via Premium workspace)
- Dataverse (not used)
- Azure SQL (not used)
- Premium connectors (not needed)

**Total**: ~$965/month + $60/month amortized A5 = ~$1025 CAD/month

---

## Key Technical Decisions Log

1. **SCD Type 2 for Student/Staff/Section** - Track changes over time for accurate historical analysis
2. **Surrogate keys in all fact tables** - Required for SCD Type 2 to work properly
3. **RLS at semantic layer, not storage** - Fabric workspace members would see all data; enforce in views/models
4. **Power Apps embedded in Teams** - Avoids standalone app licensing
5. **Manual CSV imports for MVP** - Automate in September, don't let it block June
6. **No Dataverse** - Fabric warehouse is sufficient; avoids additional complexity
7. **Long table format** - Assessments as rows, not columns (scalable, query-friendly)
8. **DimAssessmentWindow** - Essential for tracking what/when/who for each pull
9. **Star schema** - Industry standard for analytics, optimal for Power BI

---

## Questions to Resolve

- Assessment calendar: Do all grades pull on same dates, or staggered by grade band?
- PowerSchool export frequency: Daily? Weekly? On-demand only?
- Student transfer workflows: How do mid-year transfers between schools get handled?
- Backfill requirements: Load historical data, or start fresh from pilot?
- Writing rubric scoring: 1-4 scale confirmed? Any additional writing metrics?

---

## Reference Architecture

**Similar implementations**:
- Educational assessment platforms using Fabric
- SCD Type 2 in star schemas for longitudinal analysis
- Power Apps with RLS for secure data entry

**Best practices**:
- Fabric capacity monitoring via Capacity Metrics app
- Incremental refresh for semantic models
- Staggered refresh schedules to avoid contention
- Audit logging for all data modifications

---

## Success Criteria

**MVP (June)**:
- 5-10 teachers can enter assessments for French students
- RLS prevents teachers from seeing other teachers' students
- Data persists correctly in Fabric warehouse
- Basic validation prevents bad submissions

**Full Rollout (September)**:
- All 200 teachers actively using system
- School admins can monitor completion
- Regional analytics users have Power BI access
- Automated CSV ingestion from PowerSchool
- No compliance violations (Canadian data residency confirmed)
- F8 capacity utilization <80% during peak periods

---

## Contact & Governance

**Data Steward**: [To be assigned]
**Platform Administrator**: [To be assigned]
**Change Management**: All schema changes require data governance approval
**Documentation**: This skill document is the living technical reference
