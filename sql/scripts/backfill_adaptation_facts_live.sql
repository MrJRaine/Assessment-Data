/*───────────────────────────────────────────────────────────────────────────────────────────
  backfill_adaptation_facts_live.sql   —   ONE-TIME backfill of FactStudentAdaptation on LIVE

  WHY: on live, DimStudent.Adap = 1 is set for real students, but FactStudentAdaptation has ZERO
  current rows (IPP has 954). The live usp_MergeStudent writes the flag but never ran the Step 6c/6d
  expansion that derives the fact rows (added 2026-09-11; landed on live only partially — same
  pattern as the stale TVFs). The Programming chips + roster + tvf_StudentAdaptation all read
  FactStudentAdaptation, so they correctly show nothing. This script builds the missing rows.

  WHAT: this is Step 6d of usp_MergeStudent, VERBATIM — the same ExpectedAdap applicability
  (English R<=8 / W<=13; French Immersion, dropping J020's (Reading,'French Immersion'); FI grade>=3
  ELA branch; Math P-6) — inserting one current row per expected (Student, Subject, ProgramFamily)
  triple with HasAdaptation = NULL (the unresolved gate). Teachers/admins then resolve Yes/No from
  the Programming > Adaptations roster (usp_UpsertStudentAdaptation), exactly like IPPs after ingest.

  READS : DimStudent, DimProgram, DimGrade (IsCurrent = 1, Adap = 1) + FactStudentAdaptation (guard).
  WRITES: FactStudentAdaptation — INSERT only. No updates, no deletes, no PII values.

  IDEMPOTENT: NOT EXISTS guard skips any triple that already has a current row, so re-running is a
  no-op. @EffectiveDate is Atlantic 'today' (DST-aware), matching the merge proc's stamping.

  AFTER: redeploy sql/procedures/usp_MergeStudent.sql to live so the NEXT ingest keeps building
  these (otherwise it regresses to empty on the next cycle). Then re-test the Programming page.

  Run ONCE against LIVE (Assessment_Warehouse).
───────────────────────────────────────────────────────────────────────────────────────────*/

DECLARE @EffectiveDate DATE =
    CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

;WITH ExpectedAdap AS (
    -- English-program students: Reading (<=Gr8) + Writing (<=Gr13) x 'English'
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.Adap = 1
      AND  p.ProgramFamily = 'English'
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

    UNION ALL

    -- French Immersion x 'French Immersion' (drop J020's (Reading,'French Immersion') — reads in EN).
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.Adap = 1
      AND  p.ProgramFamily = 'French Immersion'
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd
      AND  NOT (sub.Subject = 'Reading' AND s.ProgramCode = 'J020')

    UNION ALL

    -- FI grade>=3 literacy ALSO carries an 'English' (ELA) track, matching the assessment tracks.
    SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('English' AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
    WHERE  s.IsCurrent = 1 AND s.Adap = 1
      AND  p.ProgramFamily = 'French Immersion'
      AND  g.GradeOrder >= 3
      AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

    UNION ALL

    -- Math P-6, own program family.
    SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
    FROM   DimStudent s
    JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN   DimGrade   g ON g.GradeCode   = s.Grade
    WHERE  s.IsCurrent = 1 AND s.Adap = 1
      AND  p.ProgramFamily IN ('English', 'French Immersion')
      AND  g.GradeOrder BETWEEN 0 AND 6
)
INSERT INTO FactStudentAdaptation (
    StudentKey, Subject, ProgramFamily, HasAdaptation,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
)
SELECT
    e.StudentKey, e.Subject, e.ProgramFamily, NULL,
    @EffectiveDate, NULL, 1, 'system', GETDATE()
FROM ExpectedAdap e
WHERE NOT EXISTS (
    SELECT 1 FROM FactStudentAdaptation fsa
    WHERE fsa.StudentKey    = e.StudentKey
      AND fsa.Subject       = e.Subject
      AND fsa.ProgramFamily = e.ProgramFamily
      AND fsa.IsCurrent     = 1
);

-- Confirm: expect Adap_Fact_Current to jump from 0 into the thousands (mirrors DimStudent.Adap=1 scope).
SELECT COUNT(*) AS Adap_Fact_Current_After FROM FactStudentAdaptation WHERE IsCurrent = 1;
