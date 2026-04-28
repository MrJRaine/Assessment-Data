# Regional Student Assessment Data Platform - Project Instructions

## Project Overview

This repository contains the implementation for a regional student assessment data platform built on Microsoft Fabric. The platform collects and analyzes reading and writing assessments for ~6000 students across multiple schools in Nova Scotia, Canada.

**Key Constraints**:
- All data must remain in Canada East region (PIIDPA compliance)
- Microsoft Fabric F8 capacity ($964.34 CAD/month)
- Users have Microsoft 365 A3 licenses
- 10 regional analytics users upgraded to A5 ($720/year)

**Timeline**:
- **MVP by June 2025**: French Immersion pilot with 5-10 teachers
- **Full rollout September 2025**: All programs (English + French), ~200 teachers

## Technology Stack

### Core Platform
- **Microsoft Fabric F8** (Canada East)
  - Fabric Warehouse (SQL-based storage)
  - OneLake for CSV landing zone
  - Data Pipelines for ETL
  - Semantic models for Power BI

### Application Layer
- **Power Apps**: Canvas apps embedded in Teams for teacher data entry
- **Power Automate**: CSV ingestion, validation, submission logging
- **Power BI**: Region-level analytics (10 A5 users only)

### Data Sources
- **PowerSchool SIS**: Manual CSV exports (students, staff, schools, enrollments)
- **Power Apps**: Teacher-entered assessment data

## Architecture Principles

### 1. Row-Level Security (RLS)
**Critical**: RLS is enforced at the semantic model and view layer, NOT at Fabric storage level.

- Teachers: See only students in their assigned sections
- School Admins: See all students in their school(s)
- Regional Users: See all data

**Implementation**:
- Create secured SQL views in Fabric Warehouse
- Apply RLS roles in Power BI semantic models
- Power Apps reads from secured views only
- Never grant teachers direct Fabric workspace access

### 2. Slowly Changing Dimensions (SCD Type 2)
**Critical**: Use surrogate keys in ALL fact tables, never business keys.

**SCD Type 2 dimensions** (track history):
- `DimStudent` - Track grade/school/program changes
- `DimStaff` - Track school/role changes  
- `DimSection` - Track teacher reassignments

**SCD Type 1 dimension** (overwrite):
- `DimSchool` - No history needed

**Why this matters**: When a student changes grade, a new `StudentKey` is created. All fact tables must reference `StudentKey` (surrogate) not `StudentID` (business key) to correctly associate assessments with the student's state at assessment time.

### 3. Star Schema Design
- **Fact tables**: Enrollments, Reading Assessments, Writing Assessments, Submission Audit
- **Dimension tables**: Student, Staff, School, Section, Assessment Window, Calendar, Reading Scale
- **Security tables**: RLS_UserSchoolAccess, RLS_UserSectionAccess

### 4. Data Residency
- ALL storage, processing, and compute must occur in Canada East region
- No third-party processors outside Canada
- Fabric capacity reserved in Canada East
- Document compliance in all deployment scripts

## Repository Structure

```
/
├── sql/
│   ├── dimensions/
│   │   ├── DimStudent.sql           # SCD Type 2
│   │   ├── DimStaff.sql             # SCD Type 2
│   │   ├── DimSection.sql           # SCD Type 2
│   │   ├── DimSchool.sql            # SCD Type 1
│   │   ├── DimAssessmentWindow.sql
│   │   ├── DimCalendar.sql
│   │   └── DimReadingScale.sql
│   ├── facts/
│   │   ├── FactEnrollment.sql
│   │   ├── FactAssessmentReading.sql
│   │   ├── FactAssessmentWriting.sql
│   │   └── FactSubmissionAudit.sql
│   ├── security/
│   │   ├── RLS_UserSchoolAccess.sql
│   │   └── RLS_UserSectionAccess.sql
│   ├── views/
│   │   ├── vw_TeacherStudents.sql
│   │   ├── vw_SchoolStudents.sql
│   │   └── vw_RegionalData.sql
│   ├── procedures/
│   │   ├── usp_MergeStudent.sql
│   │   ├── usp_MergeStaff.sql
│   │   └── usp_MergeSection.sql
│   └── scripts/
│       ├── 01_CreateSchema.sql
│       ├── 02_LoadDimensions.sql
│       └── 03_LoadSeedData.sql
├── power-apps/
│   ├── TeacherEntryForm/
│   │   ├── README.md
│   │   └── screenshots/
│   └── SchoolDashboard/
├── power-automate/
│   ├── CSV-Ingestion-Flow.json
│   └── README.md
├── power-bi/
│   ├── semantic-models/
│   │   └── AssessmentAnalytics.pbip
│   └── reports/
│       └── RegionalDashboard.pbip
├── data-pipelines/
│   ├── PowerSchool-Import.json
│   └── README.md
├── test-data/
│   ├── sample-students.csv
│   ├── sample-staff.csv
│   └── sample-assessments.csv
├── docs/
│   ├── architecture.md
│   ├── deployment-guide.md
│   ├── user-guide-teachers.md
│   └── troubleshooting.md
└── .claude/
    └── instructions.md              # This file
```

## Data Model Reference

### Key Tables and Relationships

**DimStudent** (SCD Type 2):
```sql
StudentKey INT PRIMARY KEY IDENTITY    -- Surrogate key (unique per version)
StudentID INT NOT NULL                 -- Business key (same across versions)
CurrentGrade NVARCHAR(10)              -- Triggers new version
CurrentSchoolID INT                    -- Triggers new version
ProgramCode NVARCHAR(10)               -- Triggers new version (EN/FR)
EffectiveStartDate DATE
EffectiveEndDate DATE                  -- NULL = current
IsCurrent BIT                          -- 1 = current, 0 = historical
```

**FactAssessmentReading**:
```sql
ReadingAssessmentID INT PRIMARY KEY
StudentKey INT                         -- MUST be surrogate key!
AssessmentWindowID INT
ReadingScaleID INT
ReadingDelta INT
AssessmentDate DATE
EnteredByStaffKey INT                  -- MUST be surrogate key!
SubmissionTimestamp DATETIME
```

**DimAssessmentWindow** (defines what/when/who):
```sql
AssessmentWindowID INT PRIMARY KEY
WindowName NVARCHAR(100)               -- e.g., "Fall 2025 Reading - Primary"
AssessmentType NVARCHAR(20)            -- 'Reading' or 'Writing'
SchoolYear NVARCHAR(9)                 -- '2025-2026'
StartDate DATE
EndDate DATE
MinGrade NVARCHAR(10)                  -- Applicability
MaxGrade NVARCHAR(10)
ProgramCode NVARCHAR(10)               -- 'FR', 'EN', or NULL
IsCurrentWindow BIT
```

## Coding Standards

### SQL Scripts

**File naming**:
- Dimension tables: `Dim[EntityName].sql`
- Fact tables: `Fact[EntityName].sql`
- Views: `vw_[Purpose].sql`
- Procedures: `usp_[Action][Entity].sql`

**Required header**:
```sql
/*******************************************************************************
 * Table: [TableName]
 * Purpose: [Brief description]
 * SCD Type: [1, 2, or N/A]
 * Created: [YYYY-MM-DD]
 * Modified: [YYYY-MM-DD] - [Description of change]
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/
```

**Standards**:
- Use `INT IDENTITY` for surrogate keys
- Always include `LastUpdated DATETIME DEFAULT GETDATE()`
- Index on business key + IsCurrent for SCD Type 2: `IX_[BusinessKey]_IsCurrent`
- Use meaningful foreign key names: `FK_[ChildTable]_[ParentTable]_[Column]`
- Include comments explaining SCD Type 2 logic

### SCD Type 2 Merge Procedures

**Required logic**:
1. Check if business key exists with `IsCurrent = 1`
2. If not exists → Insert first version
3. If exists → Compare Type 2 attributes
4. If changed → Expire old record (set `IsCurrent = 0`, set `EffectiveEndDate`), insert new version
5. If unchanged → Update Type 1 attributes only

**Type 2 attributes by dimension**:
- **DimStudent**: `CurrentGrade`, `CurrentSchoolID`, `ProgramCode`
- **DimStaff**: `HomeSchoolID`, `RoleCode`
- **DimSection**: `TeacherStaffKey`

**Type 1 attributes** (just update in place):
- Names, email, student number, date of birth, etc.

### Power Apps Development

**Connection requirements**:
- Apps must be embedded in Microsoft Teams (A3 license compliance)
- Connect only to secured views, never base tables
- Always filter by `USERPRINCIPALNAME()` for teacher apps
- Validate data client-side before submission
- Log all submissions to `FactSubmissionAudit`

**Naming conventions**:
- Screens: `scr[Purpose]` (e.g., `scrStudentSelect`, `scrAssessmentEntry`)
- Collections: `col[Purpose]` (e.g., `colMyStudents`, `colActiveWindows`)
- Variables: `var[Purpose]` (e.g., `varSelectedStudent`, `varCurrentWindow`)

### Power BI Development

**Semantic model requirements**:
- Source from Fabric Warehouse views only
- Implement RLS with DAX: `[Email] = USERPRINCIPALNAME()`
- Use incremental refresh for fact tables
- Schedule refreshes during off-peak hours
- Document all calculated columns and measures

**RLS roles**:
- `Teacher`: Filter to user's assigned sections
- `SchoolAdmin`: Filter to user's authorized schools
- `Regional`: No filter (see all data)

## Development Workflow

### 1. MVP (June 2025) - French Immersion Pilot

**Scope**:
- French Immersion students only (`ProgramCode = 'FR'`)
- 1-2 pilot schools
- 5-10 teachers
- 1 assessment window (end of year)
- Reading assessments only (defer writing if time-constrained)

**Deliverables**:
- Core dimension tables (current state snapshot, defer full SCD for September)
- `FactAssessmentReading` only
- Basic secured view for teachers
- Simple Power Apps entry form
- Manual CSV import (defer automation)

**Out of scope**:
- Power BI dashboards
- Automated ingestion
- School admin tools
- Historical data
- Full SCD Type 2 implementation

### 2. Full Rollout (September 2025)

**Additions**:
- All programs (EN + FR)
- All schools and teachers (~200)
- Both reading and writing assessments
- Multiple concurrent assessment windows
- Full SCD Type 2 implementation
- Automated CSV ingestion via Power Automate
- School admin dashboards
- Power BI analytics (10 A5 users)
- Historical backfill (if required)

## Testing Requirements

### Unit Tests
- Each merge procedure must handle: new record, unchanged record, Type 1 change, Type 2 change
- Views must correctly filter by user identity
- Assessment window applicability logic (grade range, program)

### Integration Tests
- End-to-end: PowerSchool CSV → merge procedures → fact tables
- RLS enforcement: Teacher sees only their students
- Power Apps submission → Fabric warehouse write

### Data Quality Tests
- No orphaned records (all foreign keys valid)
- No duplicate current versions (one record per business key with `IsCurrent = 1`)
- Date logic: `EffectiveEndDate` = `DATEADD(DAY, -1, new EffectiveStartDate)`
- Assessment dates fall within window dates

## Security Checklist

Before any deployment:

- [ ] Fabric workspace is in **Canada East** region
- [ ] OneLake storage location confirmed as **Canada East**
- [ ] All data pipelines run in **Canada East** compute
- [ ] No third-party connectors that route data outside Canada
- [ ] RLS views created and tested
- [ ] Teachers cannot access base tables directly
- [ ] Power Apps connects only to secured views
- [ ] Audit logging enabled on all fact table writes
- [ ] Test user access with actual Entra ID accounts

## Common Pitfalls to Avoid

### 1. Using Business Keys in Fact Tables
**Wrong**:
```sql
CREATE TABLE FactAssessmentReading (
    StudentID INT,  -- ❌ Business key breaks with SCD Type 2
    ...
);
```

**Correct**:
```sql
CREATE TABLE FactAssessmentReading (
    StudentKey INT,  -- ✅ Surrogate key
    ...
    FOREIGN KEY (StudentKey) REFERENCES DimStudent(StudentKey)
);
```

### 2. Forgetting to Filter on IsCurrent
**Wrong**:
```sql
SELECT * FROM DimStudent WHERE StudentID = 12345;  -- Returns all versions!
```

**Correct**:
```sql
SELECT * FROM DimStudent WHERE StudentID = 12345 AND IsCurrent = 1;
```

### 3. Direct Fabric Workspace Access for End Users
**Wrong**: Adding teachers to Fabric workspace members

**Correct**: Teachers access via Power Apps → secured views with RLS

### 4. Granting Power BI Pro Licenses
**Wrong**: Buying Power BI Pro for 200 teachers ($2600/month)

**Correct**: Teachers consume from Premium workspace via embedded visuals (included in A3)

### 5. Hard-Coding Assessment Windows
**Wrong**: `WHERE AssessmentDate BETWEEN '2025-06-01' AND '2025-06-30'`

**Correct**: `JOIN DimAssessmentWindow WHERE IsCurrentWindow = 1`

## Environment Variables

When deploying to Fabric:

```json
{
  "fabricWorkspaceName": "Regional_Data_Portal",
  "fabricRegion": "canadaeast",
  "warehouseName": "Assessment_Warehouse",
  "semanticModelName": "Assessment_Analytics",
  "powerAppsEnvironment": "Production",
  "adGroupTeachers": "SG-Assessment-Teachers",
  "adGroupSchoolAdmins": "SG-Assessment-SchoolAdmins",
  "adGroupRegionalAnalysts": "SG-Assessment-Regional"
}
```

## Monitoring and Maintenance

### Fabric Capacity Monitoring
- Use **Fabric Capacity Metrics** app
- Watch for sustained >80% utilization
- Stagger refresh schedules to avoid peak contention
- Consider F16 upgrade only if sustained throttling occurs

### Data Quality Monitoring
Weekly checks:
- Orphaned records query
- Duplicate IsCurrent checks  
- Assessment date validation (within window)
- Enrollment count trends (spot anomalies)

### Performance Optimization
- Incremental refresh for fact tables (load only new/changed records)
- Columnstore indexes on large fact tables
- Partition fact tables by school year
- Archive old assessment windows after 10 years

## Support and Escalation

**Data Issues**: Data Steward [TBD]
**Platform Issues**: Fabric Administrator [TBD]
**Security/Access**: IT Security [TBD]
**Schema Changes**: Requires data governance approval

## Additional Resources

- [Microsoft Fabric Documentation](https://learn.microsoft.com/en-us/fabric/)
- [SCD Type 2 Best Practices](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/type-2/)
- [Power Apps Security](https://learn.microsoft.com/en-us/power-apps/maker/canvas-apps/security/)
- [Power BI RLS](https://learn.microsoft.com/en-us/power-bi/admin/service-admin-rls)

## Questions or Issues?

If you encounter scenarios not covered in these instructions:
1. Check the `/docs` folder for detailed documentation
2. Review the skill file at `/regional-assessment-platform/SKILL.md`
3. Contact the project data steward
4. Update these instructions with learnings

---

**Last Updated**: 2025-04-22
**Project Status**: Pre-MVP Development
**Target MVP**: June 2025
**Target Full Rollout**: September 2025
