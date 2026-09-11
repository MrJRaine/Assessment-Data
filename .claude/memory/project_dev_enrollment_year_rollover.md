---
name: Dev Enrollment Year Rollover
description: Dev synthetic FactEnrollment is dated for ONE school year; when the calendar crosses into a new year the rows expire and teachers resolve empty rosters — roll enrollments forward a year to fix.
metadata:
  type: project
---

The dev synthetic data (`_Dev` warehouse) has a fixed **single-school-year** `FactEnrollment` set. The whole app is **date-driven** (`AT TIME ZONE Atlantic`, `today`), and the roster chain keeps an enrollment only if `StartDate <= today AND (EndDate IS NULL OR EndDate >= today)`. So once "today" crosses past the synthetic year's `EndDate`, **almost every enrollment expires**, classroom teachers (AccessLevel NULL) resolve **empty rosters**, and no open cycle appears in Data Entry — even though the app, grade bands, and `FactSectionTeachers`/`DimSection` links are all fine.

**Symptom (seen 2026-09-04):** dev had 41 enrollments, all 2025-2026 (StartDate 2025-09-02 … EndDate ≤ 2026-06-30), only 1 open-ended → only 1 student current on 2026-09-04. Just one teacher (Daphne Oak, the one open-ended row) resolved anything. Privileged accounts (Admin/Analyst/Specialist) still saw everything because their role branch bypasses enrollment/grade bands.

**Fix (dev only):** roll the synthetic enrollments forward one year so the September rows are current again — `sql/scripts/rollforward_enrollment_dev.sql` (`UPDATE FactEnrollment SET StartDate=DATEADD(YEAR,1,StartDate), EndDate=DATEADD(YEAR,1,EndDate)`; `DATEADD(YEAR,1,NULL)=NULL` keeps the open row open; reversible with `-1`). After it, the P-6 homeroom teachers (Aurora Maple, Bryce Birch, Cedar Pine) resolve all three subjects, the 7-8 teacher (Elder Spruce) Reading+Writing, Daphne Oak (grade 9) Writing.

**Note:** roll-forward keeps students at their prior-year GRADE (the enrollment's `StudentKey` points to that DimStudent version). Fine for band testing; a realistic new-year set would also promote grades (+1) — a separate DimStudent change, not done.

**Diagnostics built (all `sql/scripts/*_dev.sql`, 2026-09-04):** `who_sees_open_cycle_dev` (CROSS APPLY `tvf_UserAssessmentWindows` per staff → who sees an open cycle + subjects), `classroom_teacher_grades_dev` (per-teacher grade span via the roster chain), `staff_roster_linkage_dev` (SectionsByStaffKey vs SectionsByFST vs ResolvableStudents — pinpoints where the chain breaks), `enrollment_currency_dev` (FactEnrollment date span + CurrentToday). Trap noted: the impersonation dropdown counts sections off `DimSection.TeacherStaffKey`, but rosters resolve off `FactSectionTeachers.TeacherEmail` — a teacher can show sections yet resolve none. Related: [[project_dev_live_environment_split]], [[feedback_live_pii_boundary]].
