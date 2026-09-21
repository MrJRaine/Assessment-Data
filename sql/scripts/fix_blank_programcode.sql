/*******************************************************************************
 * Script: fix_blank_programcode.sql   (LIVE + DEV data remediation)
 * Purpose: Clear DQ check #41 ("DimStudent.ProgramCode not found in DimProgram")
 *          for a phantom, malformed student version (blank ProgramCode, a
 *          same-day add-then-remove of a null-grade student pulled from the file
 *          pending a school correction). #41 scans ALL versions and treats '' as
 *          non-NULL, so the dead row keeps tripping the ingest DQ gate.
 * Created: 2026-09-08
 * Region:  Canada East (PIIDPA compliant).
 *
 * ProgramCode is NOT NULL (can't null the blank) and the version is referenced
 * by FactEnrollment rows (can't delete it alone). So remove the whole phantom
 * footprint: the enrollment rows (leaf facts -- nothing hangs off them), then
 * the student version. Gated so it only ever touches versions still in #41
 * violation, and it refuses to delete a version that has any assessment/IPP
 * history (those students are NOT phantoms -- STOP and tell me if the pre-check
 * shows Reading/Writing/IPP > 0).
 *
 * RUN THE PRE-CHECKS (steps 1-2) FIRST and eyeball them before the deletes.
 ******************************************************************************/

-- 1) The offending student version(s). Expect a 0-day closed row, no assessments.
SELECT
    s.StudentKey, s.IsCurrent, s.EffectiveStartDate, s.EffectiveEndDate,
    (SELECT COUNT(*) FROM FactEnrollment       e WHERE e.StudentKey = s.StudentKey) AS EnrollRows,
    (SELECT COUNT(*) FROM FactAssessmentReading r WHERE r.StudentKey = s.StudentKey) AS ReadingRows,
    (SELECT COUNT(*) FROM FactAssessmentWriting w WHERE w.StudentKey = s.StudentKey) AS WritingRows,
    (SELECT COUNT(*) FROM FactStudentIPP        i WHERE i.StudentKey = s.StudentKey) AS IPPRows
FROM DimStudent s
WHERE s.ProgramCode IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimProgram p WHERE p.ProgramCode = s.ProgramCode);

-- 2) The enrollment rows that step 3 will delete (surrogate keys / dates -- no PII).
SELECT e.EnrollmentID, e.StudentKey, e.SectionKey, e.StartDate, e.EndDate, e.ActiveFlag
FROM FactEnrollment e
WHERE e.StudentKey IN (
    SELECT s.StudentKey FROM DimStudent s
    WHERE s.ProgramCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimProgram p WHERE p.ProgramCode = s.ProgramCode)
);

-- 3) Delete the phantom's enrollments (only for versions still in #41 violation
--    that carry NO assessment/IPP history).
DELETE FROM FactEnrollment
WHERE StudentKey IN (
    SELECT s.StudentKey FROM DimStudent s
    WHERE s.ProgramCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM DimProgram p WHERE p.ProgramCode = s.ProgramCode)
      AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading r WHERE r.StudentKey = s.StudentKey)
      AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting  w WHERE w.StudentKey = s.StudentKey)
      AND NOT EXISTS (SELECT 1 FROM FactStudentIPP         i WHERE i.StudentKey = s.StudentKey)
);

-- 4) Delete the phantom version (enrollments now gone; still gated on no assessment/IPP).
DELETE FROM DimStudent
WHERE ProgramCode IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimProgram        p WHERE p.ProgramCode = DimStudent.ProgramCode)
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading r WHERE r.StudentKey = DimStudent.StudentKey)
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting  w WHERE w.StudentKey = DimStudent.StudentKey)
  AND NOT EXISTS (SELECT 1 FROM FactStudentIPP         i WHERE i.StudentKey = DimStudent.StudentKey)
  AND NOT EXISTS (SELECT 1 FROM FactEnrollment         e WHERE e.StudentKey = DimStudent.StudentKey);

-- 5) Verify: expect ZERO rows.
SELECT s.ProgramCode, COUNT(*) AS Rows
FROM DimStudent s
WHERE s.ProgramCode IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimProgram p WHERE p.ProgramCode = s.ProgramCode)
GROUP BY s.ProgramCode;
