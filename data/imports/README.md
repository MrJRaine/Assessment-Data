# Drop folder for PowerSchool exports during testing.

Files placed here are gitignored — exports containing student or staff PII must NOT be committed.

## Folder structure

The ingest pipeline routes by folder, not filename — drop each export in its dedicated subfolder. Filename can be whatever PS produces (e.g. `AssessmentDataStudentsExport.text`); only the folder matters.

```
data/imports/
├── students/          ← Export 1: Students table → DimStudent
├── staff/             ← Export 2: Teachers table → DimStaff + FactStaffAssignment
├── sections/          ← Export 3: Sections table → DimSection + FactSectionTeachers (Primary)
├── section-teachers/  ← Export 4: Co-Teachers sqlReport → FactSectionTeachers (non-Primary, skip if PS doesn't track)
└── enrollments/       ← Export 5: CC table → FactEnrollment
```

## Format

- **Direct table extracts** (Students, Staff, Sections, Enrollments) — TAB-delimited, `.text` extension (PS default).
- **sqlReports** (Co-Teachers) — comma-delimited, `.csv` extension, double-quote text qualifier.
- The ingest pipeline auto-detects delimiter from the header line, so either form works in any folder.

Full export specs and field mappings: [docs/export-procedures.md](../../docs/export-procedures.md) and [docs/powerschool-field-mapping.md](../../docs/powerschool-field-mapping.md).
