---
name: regional-assessment-platform
description: Technical architecture and implementation guide for a regional student assessment data platform in Microsoft Fabric. Use this skill when working on database design, Power Apps development, data modeling, ETL processes, RLS implementation, or any technical decisions related to this specific student assessment project. Trigger whenever the user mentions the assessment platform, Fabric warehouse setup, SCD implementation for student/staff/section dimensions, Power Apps forms for teacher data entry, or asks about project architecture decisions.
---

# Regional Student Assessment Data Platform

## Project Context

**Purpose**: Centralized platform for collecting and analyzing student reading and writing assessments across a regional school system.

**Scale**:
- ~6,000 students (grades Primary to 12)
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

**Security Tables**:
- `StaffSchoolAccess` - School-level authorization (auto-rebuilt from staff export, no manual entries)
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
    EnrollStatus        INT,                       -- PS Enroll_Status: 1 = enrolled, 0 = inactive, -1 = pre-registered
    EffectiveStartDate  DATE NOT NULL,
    EffectiveEndDate    DATE NULL,                 -- NULL = current version
    IsCurrent           BIT NOT NULL,              -- 1 = current, 0 = historical
    SourceSystemID      VARCHAR(50),               -- PowerSchool DCID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)
);
```

**Attributes that trigger new version** (SCD Type 2):
- `CurrentGrade` - Student promoted
- `CurrentSchoolID` - Student transferred schools
- `ProgramCode` - Program change (see DimProgram for valid codes)

**Attributes that just update** (SCD Type 1):
- `FirstName`, `MiddleName`, `LastName` - Name corrections
- `DateOfBirth` - Data corrections

**Note on business key:** `StudentNumber` is the provincial 10-digit student ID (PowerSchool's "Student Number" field). It's more stable than PowerSchool's internal DCID — it follows the student across schools, regions, and re-enrollments. `SourceSystemID` stores the PowerSchool DCID for reference only, not for matching.

### DimStaff (SCD Type 2)

**Purpose**: Track staff assignments and roles over time

**Schema**:
```sql
-- Conceptual schema. See sql/dimensions/DimStaff.sql for Fabric Warehouse-compatible DDL.
CREATE TABLE DimStaff (
    StaffKey            BIGINT NOT NULL IDENTITY,  -- Surrogate key, unique per version
    Email               VARCHAR(255) NOT NULL,     -- Business key (Entra ID UPN, lowercased)
    FirstName           VARCHAR(100),
    LastName            VARCHAR(100),
    RoleCode            VARCHAR(50),               -- Triggers new version
    HomeSchoolID        INT NULL,                  -- Triggers new version; NULL for itinerant staff
    ActiveFlag          BIT,
    EffectiveStartDate  DATE NOT NULL,
    EffectiveEndDate    DATE NULL,
    IsCurrent           BIT NOT NULL,
    SourceSystemID      VARCHAR(50),               -- PowerSchool staff record ID (reference only, NOT for matching)
    LastUpdated         DATETIME2(0)
);
```

**Attributes that trigger new version**:
- `HomeSchoolID` - Teacher transferred
- `RoleCode` - Role change (Teacher → Admin)

**Note on business key:** `Email` is the business key, not a PowerSchool ID. PowerSchool creates a separate staff record per staff-school combination, so itinerant teachers appear multiple times in the export. The merge procedure deduplicates by email and collapses to one DimStaff record per person. Certification numbers exist for teachers but don't cover non-teaching staff and aren't in PowerSchool — so they're not used.

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
    CourseCode NVARCHAR(50),
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

**Attributes that trigger new version**:
- `TeacherStaffKey` - Teacher reassigned to section

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

### Merge Procedure Template

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
CROSS JOIN DimStaff adm
JOIN RLS_UserSchoolAccess access 
    ON adm.Email = access.UserEmail 
    AND s.CurrentSchoolID = access.SchoolID
WHERE s.IsCurrent = 1
  AND adm.RoleCode = 'Administrator';
```

### RLS Mapping Tables

**RLS_UserSchoolAccess**:
```sql
CREATE TABLE RLS_UserSchoolAccess (
    UserEmail NVARCHAR(255),
    SchoolID INT,
    PRIMARY KEY (UserEmail, SchoolID)
);
```

**RLS_UserSectionAccess** (alternative to joining through FactEnrollment):
```sql
CREATE TABLE RLS_UserSectionAccess (
    UserEmail NVARCHAR(255),
    SectionKey INT,
    PRIMARY KEY (UserEmail, SectionKey)
);
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

**Total**: ~$965/month + $60/month amortized A5 = ~$1,025 CAD/month

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
