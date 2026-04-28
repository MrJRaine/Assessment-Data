# Drop folder for PowerSchool CSV exports during testing.

Files placed here are gitignored — CSVs containing student PII must NOT be committed.

Expected filenames (per docs/export-procedures.md):
  - students.csv
  - staff.csv
  - sections.csv
  - section-teachers.csv  (skip if PS doesn't track co-teaching)
  - enrollments.csv
