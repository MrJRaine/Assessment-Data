---
name: Fact-Table SCD Linking Policy
description: When fact tables freeze surrogate keys vs re-resolve them — design decisions per fact, with rationale
type: project
originSessionId: 22e078d6-e607-4d91-8331-841a7d446663
---
Fact tables in this warehouse fall into two categories based on how their surrogate-key links to Type 2 dims are maintained over time. The policy is per-fact and was made deliberately.

## FactEnrollment — Type 1 link (re-resolve while active)

**Current behaviour:** `usp_MergeEnrollment` Step 2 UPDATEs StudentKey/SectionKey on every ingest cycle to whatever the current DimStudent / DimSection version resolves to via `IsCurrent = 1`. No filter on `f.ActiveFlag` — closed enrollments still in PS rolling window also get re-resolved.

**Planned refinement (decided 2026-05-04, not yet implemented):** add CASE-based gate so that StudentKey/SectionKey freeze when the row is already inactive at start of run. Active rows continue to re-resolve. The active→inactive close transition still re-resolves (final freeze captures keys at moment of closure). Reactivation re-resolves to current. Other fields (StartDate, EndDate, ActiveFlag, LastUpdated) update unconditionally regardless of activeness.

**Why this design:** an enrollment is an ongoing relationship. While active, "current pointer" semantics are what reports want ("show me students currently in Section ABC"). Once closed, the historical record should freeze — the enrollment captures a specific past period and the student/section identity at that period.

**How to apply:** When implementing the FactEnrollment freeze refinement, modify Step 2 to use CASE on the surrogate-key SETs. Validate with a test scenario where DimStudent versions while a closed enrollment is still in PS export — confirm closed-enrollment StudentKey doesn't drift.

## FactAssessmentReading / FactAssessmentWriting — Type 2 link (frozen at insert)

**Policy (decided 2026-05-04, applies when these procs are built in Step 31):** StudentKey is captured at insert time and **never re-resolved**. Subsequent updates only touch score fields. Resolution at insert uses effective-date join, not `IsCurrent = 1`:

```sql
JOIN DimStudent s
  ON s.StudentNumber = @StudentNumber
 AND @AssessmentDate BETWEEN s.EffectiveStartDate
                         AND COALESCE(s.EffectiveEndDate, '9999-12-31')
```

**Why effective-date over IsCurrent:** assessments are point-in-time events. If a teacher gives an assessment on Nov 15 and enters it in Power Apps on Dec 5, and the student was promoted on Dec 1, `IsCurrent = 1` at write time would link to the post-promotion version (wrong). Effective-date resolution correctly returns the Grade 5 version that was current on Nov 15.

**Power Apps writeback contract:** Power Apps writes `StudentNumber + AssessmentDate`, not StudentKey. The warehouse-side merge proc does the surrogate-key resolution via the effective-date join. Cleaner abstraction (Power Apps stays in business-key land; surrogate keys are a warehouse-internal concern) and automatically eliminates the entry-lag edge case.

**Reporting patterns:** longitudinal "all of Alpha's assessments across her career" joins through `DimStudent.StudentKey` (point-in-time correct) and filters on `DimStudent.StudentNumber` to match across all versions. Each row naturally carries the student's grade/school/program *as of the assessment date*.

**How to apply:** When building `usp_MergeAssessmentReading` (Step 31): no UPDATE on StudentKey ever. Insert-only path uses effective-date JOIN. Score corrections via separate UPDATE filtered by `ReadingAssessmentID` or equivalent stable identifier — touches only score columns.

## Summary table

| Fact table              | Link policy   | Re-resolution trigger                         | Insert resolution           |
|-------------------------|---------------|-----------------------------------------------|-----------------------------|
| FactEnrollment          | Type 1 active | Re-resolve while active; freeze when inactive (planned refinement) | `IsCurrent = 1` |
| FactSectionTeachers     | N/A           | Bridge keys on business keys (SectionID, TeacherEmail) — no surrogate key dependency | N/A |
| FactStaffAssignment     | Type 2 versioned | SCD Type 2 on the bridge itself; closes/reopens on staff merge | `IsCurrent = 1` for current StaffKey |
| FactAssessmentReading   | Type 2 frozen | Never re-resolve StudentKey                   | Effective-date join on AssessmentDate |
| FactAssessmentWriting   | Type 2 frozen | Same as FactAssessmentReading                 | Same                        |
| FactSubmissionAudit     | None          | No dim links                                  | N/A                         |
