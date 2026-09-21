/*******************************************************************************
 * Script: reseed_programming_rows_dev.sql   (DEV / SYNTHETIC ONLY)
 * Purpose: Reseed FactStudentIPP (incl. Math) + FactStudentAdaptation NULL-gate
 *          rows from the CURRENT DimStudent state (IsCurrent=1, IPP=1 / Adap=1),
 *          WITHOUT a full ingest. Identical logic to usp_MergeStudent Steps 6a-6d,
 *          extracted so it runs standalone.
 *
 * WHY: usp_MergeStudent Steps 1-5 reconcile DimStudent from Stg_Student and CLOSE
 * any current student missing from staging -> would deactivate the directly-inserted
 * Drumlin seed students. This script only touches FactStudentIPP/FactStudentAdaptation.
 *
 * Run as ONE batch (no GO before the verify — the @counters must persist).
 * OPTIONAL first: flip a few Drumlin students to IPP=1 / Adap=1 (they're grade P ->
 * in every band incl. Math P-6) so there's something to seed.
 ******************************************************************************/

-- -- OPTIONAL: exercise the flow on the Drumlin seed students --------------------
-- UPDATE DimStudent SET IPP  = 1 WHERE IsCurrent=1 AND SourceSystemID='DEVSEED' AND StudentNumber IN (8000000001, 8000000002, 8000000003);
-- UPDATE DimStudent SET Adap = 1 WHERE IsCurrent=1 AND SourceSystemID='DEVSEED' AND StudentNumber IN (8000000002, 8000000004);

DECLARE @EffectiveDate   DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
DECLARE @IPPRowsClosed   INT = 0;
DECLARE @IPPRowsCreated  INT = 0;
DECLARE @AdapRowsClosed  INT = 0;
DECLARE @AdapRowsCreated INT = 0;

    -- ------------------------------------------------------------------------
    -- Step 6a: Close FactStudentIPP rows whose (StudentKey, Subject,
    -- ProgramFamily) triple is no longer in the "expected current" set.
    -- Expected set = post-step-5 DimStudent (IsCurrent=1, IPP=1), per-subject
    -- grade bands + programme rules:
    --   * English stream:         Reading + Writing x 'English'
    --   * French Immersion (FLA): Reading + Writing x 'French Immersion' (any grade)
    --   * FI grade >= 3 (ELA):    ALSO Reading + Writing x 'English'
    --   * Math (Eng or FI), P-6:  Math x <own family> (single row; Math is not
    --                             language-split and Math cycles are P-6 only)
    -- Grade bands match the per-subject cycle ranges: Reading P-8 (GradeOrder 0-8),
    -- Writing P-RG (0-13), Math P-6 (0-6). PP (GradeOrder -1) excluded (bands start
    -- at P). Core French ('French Second Language') is not assessed -> no rows.
    -- ------------------------------------------------------------------------
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
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

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
    UPDATE fsi
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedIPP e
          WHERE e.StudentKey    = fsi.StudentKey
            AND e.Subject       = fsi.Subject
            AND e.ProgramFamily = fsi.ProgramFamily
      );

    SET @IPPRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6b: Insert new FactStudentIPP rows (IsIPP = NULL) for every expected
    -- triple lacking a current row. ChangedBy='system' marks auto-created rows.
    -- (ExpectedIPP repeated -- Fabric CTEs don't persist across statements.)
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.IPP = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

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

    SET @IPPRowsCreated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6c: Same reconciliation for FactStudentAdaptation, keyed on Adap=1
    -- (structural mirror of 6a; same per-subject grade bands + programme rules).
    -- ------------------------------------------------------------------------
    ;WITH ExpectedAdap AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

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

        SELECT s.StudentKey, CAST('Math' AS VARCHAR(20)), CAST(p.ProgramFamily AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily IN ('English', 'French Immersion')
          AND  g.GradeOrder BETWEEN 0 AND 6
    )
    UPDATE fsa
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentAdaptation fsa
    WHERE fsa.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedAdap e
          WHERE e.StudentKey    = fsa.StudentKey
            AND e.Subject       = fsa.Subject
            AND e.ProgramFamily = fsa.ProgramFamily
      );

    SET @AdapRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6d: Insert new FactStudentAdaptation rows (HasAdaptation = NULL) for
    -- every expected triple lacking a current row.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedAdap AS (
        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)) AS Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'English'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

        SELECT s.StudentKey, CAST(sub.Subject AS VARCHAR(20)), CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading', 8), ('Writing', 13)) AS sub(Subject, MaxOrd)
        WHERE  s.IsCurrent = 1 AND s.Adap = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder BETWEEN 0 AND sub.MaxOrd

        UNION ALL

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

    SET @AdapRowsCreated = @@ROWCOUNT;

-- ---- verify (synthetic dev data — safe to display) -------------------------
SELECT 'IPP rows created (NULL)' AS Metric, @IPPRowsCreated AS Cnt
UNION ALL SELECT 'IPP rows closed',           @IPPRowsClosed
UNION ALL SELECT 'Adaptation rows created',   @AdapRowsCreated
UNION ALL SELECT 'Adaptation rows closed',    @AdapRowsClosed;

-- Current rows for the Drumlin seed students, by kind/subject/family:
SELECT 'IPP' AS Kind, f.Subject, f.ProgramFamily, COUNT(*) AS CurrentRows
FROM FactStudentIPP f JOIN DimStudent s ON s.StudentKey = f.StudentKey
WHERE f.IsCurrent = 1 AND s.IsCurrent = 1 AND s.SourceSystemID = 'DEVSEED'
GROUP BY f.Subject, f.ProgramFamily
UNION ALL
SELECT 'Adaptation', f.Subject, f.ProgramFamily, COUNT(*)
FROM FactStudentAdaptation f JOIN DimStudent s ON s.StudentKey = f.StudentKey
WHERE f.IsCurrent = 1 AND s.IsCurrent = 1 AND s.SourceSystemID = 'DEVSEED'
GROUP BY f.Subject, f.ProgramFamily;
