/*******************************************************************************
 * Script: relink_stranded_assessment_studentkeys.sql   (LIVE recovery — WRITES)
 * Purpose: RECOVERY for stranded assessment entries. When a student re-versions
 *          (SCD Type 2 -> NEW StudentKey), rows entered under the OLD key stop
 *          matching the roster/report reads (which join the CURRENT StudentKey),
 *          so the data reads as missing (0 progress, blank in reports/entry).
 *          This re-points those stranded rows to the student's CURRENT StudentKey,
 *          matched by the stable StudentNumber.
 *
 * Writes:  FactAssessmentMath / FactAssessmentReading / FactAssessmentWriting
 *          -- StudentKey + LastUpdated, ONLY where:
 *            (a) the fact's StudentKey is NOT the student's current StudentKey, AND
 *            (b) the student HAS a current (IsCurrent=1) row, AND
 *            (c) re-pointing would NOT collide with an existing row at the SAME grain
 *                (the data wasn't already re-entered under the new key).
 *          Departed students (no current row) and would-collide rows are LEFT AS-IS.
 * Grain for the collision guard:
 *            Math    = (StudentKey, AssessmentWindowID, MathTaskKey, AssessmentDate)
 *            Reading = (StudentKey, AssessmentWindowID, AssessmentDate)
 *            Writing = (StudentKey, AssessmentWindowID, AssessmentLanguage, AssessmentDate)
 * Idempotent: re-running changes nothing (already-linked rows fail the WHERE).
 *
 * One-time catch-up only. DURABLE fix = add StudentNumber to the facts so reads
 * never key off the mutable surrogate (separate script, to follow).
 * Region:  Canada East (PIIDPA compliant)
 *
 * RUN ORDER: (1) PRE-CHECK, compare to the stranded diagnostic; (2) the three
 *            UPDATEs; (3) POST-VERIFY (Stranded should drop to departed + collisions).
 ******************************************************************************/

SET NOCOUNT ON;

-- ===================== (1) PRE-CHECK — what each UPDATE will do =====================
-- WillRelink should ~match the diagnostic's Stranded counts (minus any WouldCollide).
;WITH CurKey AS (
    SELECT StudentNumber, StudentKey,
           ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY EffectiveStartDate DESC, StudentKey DESC) AS rn
    FROM DimStudent WHERE IsCurrent = 1
)
SELECT Subject,
       SUM(Stranded) AS Stranded_withCurrentRow,
       SUM(Collide)  AS WouldCollide,
       SUM(Relink)   AS WillRelink
FROM (
    SELECT 'Math' AS Subject,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey THEN 1 ELSE 0 END AS Stranded,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND EXISTS (SELECT 1 FROM FactAssessmentMath x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.MathTaskKey=f.MathTaskKey AND x.AssessmentDate=f.AssessmentDate)
             THEN 1 ELSE 0 END AS Collide,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND NOT EXISTS (SELECT 1 FROM FactAssessmentMath x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.MathTaskKey=f.MathTaskKey AND x.AssessmentDate=f.AssessmentDate)
             THEN 1 ELSE 0 END AS Relink
    FROM FactAssessmentMath f
    JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
    LEFT JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
    UNION ALL
    SELECT 'Reading',
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey THEN 1 ELSE 0 END,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND EXISTS (SELECT 1 FROM FactAssessmentReading x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.AssessmentDate=f.AssessmentDate)
             THEN 1 ELSE 0 END,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.AssessmentDate=f.AssessmentDate)
             THEN 1 ELSE 0 END
    FROM FactAssessmentReading f
    JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
    LEFT JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
    UNION ALL
    SELECT 'Writing',
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey THEN 1 ELSE 0 END,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND EXISTS (SELECT 1 FROM FactAssessmentWriting x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.AssessmentDate=f.AssessmentDate
                          AND ISNULL(x.AssessmentLanguage,'~') = ISNULL(f.AssessmentLanguage,'~'))
             THEN 1 ELSE 0 END,
        CASE WHEN ck.StudentKey IS NOT NULL AND ck.StudentKey <> f.StudentKey
              AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting x WHERE x.StudentKey=ck.StudentKey
                          AND x.AssessmentWindowID=f.AssessmentWindowID AND x.AssessmentDate=f.AssessmentDate
                          AND ISNULL(x.AssessmentLanguage,'~') = ISNULL(f.AssessmentLanguage,'~'))
             THEN 1 ELSE 0 END
    FROM FactAssessmentWriting f
    JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
    LEFT JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
) s
GROUP BY Subject
ORDER BY Subject;
GO

-- ===================== (2) RE-LINK — Math =====================
;WITH CurKey AS (
    SELECT StudentNumber, StudentKey,
           ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY EffectiveStartDate DESC, StudentKey DESC) AS rn
    FROM DimStudent WHERE IsCurrent = 1
)
UPDATE f
SET f.StudentKey = ck.StudentKey, f.LastUpdated = GETDATE()
FROM FactAssessmentMath f
JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
WHERE ck.StudentKey <> f.StudentKey
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentMath x
                  WHERE x.StudentKey = ck.StudentKey AND x.AssessmentWindowID = f.AssessmentWindowID
                    AND x.MathTaskKey = f.MathTaskKey AND x.AssessmentDate = f.AssessmentDate);
GO

-- ===================== RE-LINK — Reading =====================
;WITH CurKey AS (
    SELECT StudentNumber, StudentKey,
           ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY EffectiveStartDate DESC, StudentKey DESC) AS rn
    FROM DimStudent WHERE IsCurrent = 1
)
UPDATE f
SET f.StudentKey = ck.StudentKey, f.LastUpdated = GETDATE()
FROM FactAssessmentReading f
JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
WHERE ck.StudentKey <> f.StudentKey
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading x
                  WHERE x.StudentKey = ck.StudentKey AND x.AssessmentWindowID = f.AssessmentWindowID
                    AND x.AssessmentDate = f.AssessmentDate);
GO

-- ===================== RE-LINK — Writing (AssessmentLanguage in the grain) =====================
;WITH CurKey AS (
    SELECT StudentNumber, StudentKey,
           ROW_NUMBER() OVER (PARTITION BY StudentNumber ORDER BY EffectiveStartDate DESC, StudentKey DESC) AS rn
    FROM DimStudent WHERE IsCurrent = 1
)
UPDATE f
SET f.StudentKey = ck.StudentKey, f.LastUpdated = GETDATE()
FROM FactAssessmentWriting f
JOIN DimStudent entry ON entry.StudentKey = f.StudentKey
JOIN CurKey ck ON ck.StudentNumber = entry.StudentNumber AND ck.rn = 1
WHERE ck.StudentKey <> f.StudentKey
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting x
                  WHERE x.StudentKey = ck.StudentKey AND x.AssessmentWindowID = f.AssessmentWindowID
                    AND x.AssessmentDate = f.AssessmentDate
                    AND ISNULL(x.AssessmentLanguage,'~') = ISNULL(f.AssessmentLanguage,'~'));
GO

-- ===================== (3) POST-VERIFY — re-run the stranded count =====================
-- Expect Stranded to drop to (departed students with no current row) + (any WouldCollide rows left).
WITH CurKey AS (
    SELECT StudentNumber, StudentKey AS CurrentStudentKey
    FROM DimStudent WHERE IsCurrent = 1
),
Facts AS (
    SELECT 'Math' AS Subject, fm.StudentKey AS EntryStudentKey, es.StudentNumber
    FROM FactAssessmentMath fm    JOIN DimStudent es ON es.StudentKey = fm.StudentKey
    UNION ALL
    SELECT 'Reading', fr.StudentKey, es.StudentNumber
    FROM FactAssessmentReading fr JOIN DimStudent es ON es.StudentKey = fr.StudentKey
    UNION ALL
    SELECT 'Writing', fw.StudentKey, es.StudentNumber
    FROM FactAssessmentWriting fw JOIN DimStudent es ON es.StudentKey = fw.StudentKey
)
SELECT f.Subject,
       COUNT(*) AS TotalEntries,
       SUM(CASE WHEN ck.CurrentStudentKey =  f.EntryStudentKey THEN 1 ELSE 0 END) AS LinkedOk,
       SUM(CASE WHEN ck.CurrentStudentKey <> f.EntryStudentKey THEN 1 ELSE 0 END) AS Stranded,
       SUM(CASE WHEN ck.CurrentStudentKey IS NULL             THEN 1 ELSE 0 END)  AS NoCurrentStudentRow
FROM Facts f
LEFT JOIN CurKey ck ON ck.StudentNumber = f.StudentNumber
GROUP BY f.Subject
ORDER BY f.Subject;
GO
