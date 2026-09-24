/*───────────────────────────────────────────────────────────────────────────────────────────
  backfill_ipp_facts_live.sql   —   ONE-TIME additive backfill of FactStudentIPP on LIVE

  WHY: the live usp_MergeStudent is a pre-2026-09-11 version (the 2026-09-17 merge to main updated
  the FILE but the CREATE PROC was never re-run on the live warehouse). It predates Math IPPs and
  the per-subject grade bands, so live FactStudentIPP (954 rows) has Reading + Writing only — NO
  Math IPP rows. The Programming IPP roster's Math column is therefore always empty.

  This is the TWIN of backfill_adaptation_facts_live.sql: Step 6b of usp_MergeStudent, VERBATIM
  (keyed on DimStudent.IPP = 1 instead of Adap = 1), inserting one current row per expected
  (Student, Subject, ProgramFamily) triple that lacks one, IsIPP = NULL (unresolved gate). It ADDS
  the missing Math P-6 rows (and any Reading/Writing now in-band that weren't before); teachers then
  confirm from the Programming > IPP roster (usp_UpsertStudentIPP).

  INSERT-ONLY, by design — same as the adaptation twin:
    * It does NOT close stale old-band rows (Step 6a). Any pre-existing row a teacher already
      resolved is left untouched; nothing a teacher entered is lost.
    * The CLOSING side (retiring rows now out of band, e.g. a Gr9 Reading row under the P-8 band)
      happens when usp_MergeStudent is redeployed to live and the NEXT ingest runs Step 6a. Redeploy
      the proc (sql/procedures/usp_MergeStudent.sql) after this so that reconciliation happens.

  READS : DimStudent, DimProgram, DimGrade (IsCurrent = 1, IPP = 1) + FactStudentIPP (guard).
  WRITES: FactStudentIPP — INSERT only. No updates, no deletes, no PII values.

  IDEMPOTENT: NOT EXISTS guard skips any triple that already has a current row, so re-running is a
  no-op. @EffectiveDate is Atlantic 'today' (DST-aware), matching the merge proc.

  Run ONCE against LIVE (Assessment_Warehouse).
───────────────────────────────────────────────────────────────────────────────────────────*/

DECLARE @EffectiveDate DATE =
    CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

;WITH ExpectedIPP AS (
    -- English-literacy stream: {Reading<=8, Writing<=13} x {English}
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1
      AND  p.ProgramFamily = 'English'
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

    UNION ALL

    -- French Immersion (FLA), any grade: {Reading<=8, Writing<=13} x {French Immersion}
    -- (drop J020's (Reading,'French Immersion') — late immersion reads in English).
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1
      AND  p.ProgramFamily = 'French Immersion'
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
      AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

    UNION ALL

    -- French Immersion grade >= 3 (ELA): additionally {Reading<=8, Writing<=13} x {English}
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.IPP = 1
      AND  p.ProgramFamily = 'French Immersion'
      AND  g.GradeOrder >= 3
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

    UNION ALL

    -- Math (English or FI), grades P-6: Math x <own family>, single row
    SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    WHERE  s.IsCurrent = 1 AND s.IPP = 1
      AND  p.ProgramFamily IN ('English', 'French Immersion')
      AND  g.GradeOrder BETWEEN 0 AND 6
)
INSERT INTO FactStudentIPP (
    StudentKey, Subject, ProgramFamily, IsIPP,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
)
SELECT
    e.StudentKey, e.Subject, e.ProgramFamily, NULL,
    @EffectiveDate, NULL, 1, 'system', GETDATE()
FROM ExpectedIPP e
WHERE NOT EXISTS (
    SELECT 1 FROM FactStudentIPP fsi
    WHERE fsi.StudentKey    = e.StudentKey
      AND fsi.Subject       = e.Subject
      AND fsi.ProgramFamily = e.ProgramFamily
      AND fsi.IsCurrent     = 1
);

-- Confirm: a Math row should now appear alongside Reading + Writing.
SELECT Subject, COUNT(*) AS N
FROM FactStudentIPP WHERE IsCurrent = 1
GROUP BY Subject ORDER BY Subject;
