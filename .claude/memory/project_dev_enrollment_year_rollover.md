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

**After a dev RE-INGEST, two things break together (2026-10-05):** the ingest (a) re-applies the old
synthetic enrollment dates (expired → run `rollforward_enrollment_dev.sql` for the date-gated ENTRY/roster
side; note Reports use `FactEnrollment.ActiveFlag` not dates, so cohort reports can still resolve while
rosters are empty) AND (b) CLOSES the project lead's manually-granted `DimStaff`/`StaffSchoolAccess` (the
synthetic staff file omits that email → anti-join deactivation), so the project-lead SELF-VIEW shows "No
students in your scope" everywhere → run `grant_dev_projectlead_access.sql` (restores DimStaff analyst +
StaffSchoolAccess + sysadmin). Diagnose with `diag_cohort_scope_dev.sql` (per-user cohort row counts +
who holds StaffSchoolAccess).

**FIX for half of that pair, at the SOURCE (2026-10-06):** the dev ingest CSV
`data/imports/enrollments/EnrollmentsExport.csv` was shifted +1 year (all 880 rows
`09/02/2025→09/02/2026`, `06/30/2026→06/30/2027`) so a fresh ingest now lands **current** rosters for
school year 2026-27 — **`rollforward_enrollment_dev.sql` is no longer needed after ingest** (keep it only
if the calendar later crosses past 2027-06-30; then re-shift the CSV instead). Only EnrollmentsExport
carries school-year dates: `StudentsExport.DOB` (real birth dates) and mathtasks `AssessmentMonth` (month
bins) were deliberately NOT shifted. **The access-grant half is separate and still required after a
re-ingest** — `grant_dev_projectlead_access.sql` is IDENTITY-driven (project-lead email omitted from the
synthetic `StaffExport` → anti-join deactivation), not date-driven, so the CSV shift does not touch it.
(Could be killed too by adding the project-lead to StaffExport — not done, scope/mechanism differs.)
