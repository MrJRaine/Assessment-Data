/*******************************************************************************
 * Script: seed_dual_language_sentinel_dev.sql   (DEV WAREHOUSE ONLY — synthetic)
 * Purpose: Make the v1.3.0 EN+FR two-row merge VISUALLY verifiable on dev. The dev
 *          course-mapping seed has French-literacy + Math only, so no synthetic
 *          student is expected in BOTH English and French — the stacked (student x
 *          language) rows in the student list and roll-up drill never actually merge
 *          two languages for one person. This seeds ONE uniquely-named sentinel
 *          student with an English AND a French reading result, and an English AND a
 *          French writing result, so the stacking renders as two rows for one student.
 *
 * How the merge is driven (why this works WITHOUT the track rules):
 *   - tvf_StudentCohort keys the reading LANGUAGE off the SCALE on the fact row
 *     (DimReadingScale.ScaleSystem = EN_Reading / FR_Reading), not the window.
 *   - tvf_StudentCohortWriting keys the writing LANGUAGE off FactAssessmentWriting
 *     .AssessmentLanguage ('English' / 'French'), a column on the fact row.
 *   Neither TVF re-validates program family / track rules. So a direct INSERT of one
 *   EN-scale + one FR-scale reading fact, and one English + one French writing fact,
 *   for a single in-scope student produces exactly the stacked rows under test.
 *
 * Writes (DEV only, synthetic):
 *   - UPDATE DimStudent  — rename ONE existing current student to "Dualang Sentinel"
 *                          (a name confirmed unique — query 1 of the namecheck diag).
 *   - UPDATE FactStudentIPP — resolve this student's UNRESOLVED (IsIPP=NULL) IPP gates
 *                          to IsIPP=0 (not-IPP), so the sentinel is CHART-ELIGIBLE and the
 *                          report shows Expected/Diff/Achievement (an unresolved-IPP student
 *                          is deliberately suppressed — chartEligible=0 — which blanked them).
 *   - DELETE + INSERT FactAssessmentReading  — 2 rows for the sentinel (EN + FR scale).
 *   - DELETE + INSERT FactAssessmentWriting  — 2 rows for the sentinel (English + French).
 *   - INSERT FactSubmissionAudit             — one marker row (optional trail).
 *
 * Idempotent: re-running reuses the same sentinel (found by its unique name), wipes
 *   its prior reading/writing facts, and re-inserts the fixed set. Safe to run twice.
 *
 * Reads (to resolve real IDs locally — no placeholders): DimStudent, DimProgram,
 *   DimGrade, DimReadingScale, DimAssessmentWindow, DimStaff, FactEnrollment.
 *
 * NOT for live. Live holds real PII; this repurposes a synthetic student. Region:
 * Canada East (PIIDPA compliant). The user runs this; Claude does not execute SQL.
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Today        DATE         = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
DECLARE @Now          DATETIME2(0) = GETDATE();

DECLARE @SentinelFirst VARCHAR(50) = 'Dualang';
DECLARE @SentinelLast  VARCHAR(50) = 'Sentinel';

DECLARE @StudentNumber     BIGINT;
DECLARE @StudentKey        BIGINT;
DECLARE @StudentGradeOrder INT;
DECLARE @StaffKey          BIGINT;

DECLARE @EnScaleId  BIGINT, @EnLevelCode VARCHAR(10);
DECLARE @FrScaleId  BIGINT, @FrLevelCode VARCHAR(10);
DECLARE @EnMid INT, @FrMid INT;

DECLARE @ReadingWindowId BIGINT;
DECLARE @WritingWindowId BIGINT;

-- =============================================================================
-- 1) Resolve the sentinel student.
--    Reuse a prior run's sentinel (found by its unique name); otherwise pick a
--    deterministic existing FI student, grade 3-8, who is enrolled in an active
--    section (so they're in the caller's scope for teacher AND oversight views).
-- =============================================================================
SELECT TOP 1 @StudentNumber = StudentNumber
FROM DimStudent
WHERE IsCurrent = 1 AND FirstName = @SentinelFirst AND LastName = @SentinelLast;

IF @StudentNumber IS NULL
BEGIN
    SELECT TOP 1 @StudentNumber = s.StudentNumber
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   g ON g.GradeCode   = s.Grade
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND p.ProgramFamily = 'French Immersion'
      AND g.GradeOrder BETWEEN 3 AND 8
      AND EXISTS (SELECT 1 FROM FactEnrollment fe WHERE fe.StudentKey = s.StudentKey AND fe.ActiveFlag = 1)
    ORDER BY s.StudentNumber;
END;

IF @StudentNumber IS NULL
BEGIN
    ;THROW 60001, 'seed_dual_language_sentinel_dev: no eligible FI grade 3-8 enrolled student found to repurpose. Check dev roster.', 1;
END;

-- Rename the sentinel (idempotent — no-op if already named). Updates the CURRENT row.
UPDATE DimStudent
SET FirstName = @SentinelFirst, LastName = @SentinelLast, LastUpdated = @Now
WHERE StudentNumber = @StudentNumber AND IsCurrent = 1;

SELECT @StudentKey = s.StudentKey, @StudentGradeOrder = g.GradeOrder
FROM DimStudent s
JOIN DimGrade g ON g.GradeCode = s.Grade
WHERE s.StudentNumber = @StudentNumber AND s.IsCurrent = 1;

-- Resolve the sentinel's auto-created UNRESOLVED IPP gates (IsIPP=NULL) to not-IPP (0) so the
-- student is CHART-ELIGIBLE and the report renders Expected/Diff/Achievement. An FI grade-3+ student
-- gets unresolved Reading+Writing IPP placeholders in BOTH families; MAX(IsIPP)=0 across the current
-- rows makes both subjects eligible. Leaves already-resolved rows as-is (0 stays 0).
UPDATE FactStudentIPP
SET IsIPP = 0, ChangedBy = 'devseed', LastUpdated = @Now
WHERE StudentKey = @StudentKey AND IsCurrent = 1 AND (IsIPP IS NULL OR IsIPP = 1);

-- =============================================================================
-- 2) Resolve an entering-staff key (any current staff), and the EN + FR reading
--    scale IDs nearest each scale's mid LevelOrder (a readable, representative level).
-- =============================================================================
SELECT TOP 1 @StaffKey = StaffKey FROM DimStaff WHERE IsCurrent = 1 ORDER BY StaffKey;

SELECT @EnMid = (MIN(LevelOrder) + MAX(LevelOrder)) / 2 FROM DimReadingScale WHERE ScaleSystem = 'EN_Reading' AND ActiveFlag = 1;
SELECT @FrMid = (MIN(LevelOrder) + MAX(LevelOrder)) / 2 FROM DimReadingScale WHERE ScaleSystem = 'FR_Reading' AND ActiveFlag = 1;

SELECT TOP 1 @EnScaleId = ReadingScaleID, @EnLevelCode = LevelCode
FROM DimReadingScale WHERE ScaleSystem = 'EN_Reading' AND ActiveFlag = 1
ORDER BY ABS(LevelOrder - @EnMid), LevelOrder;

SELECT TOP 1 @FrScaleId = ReadingScaleID, @FrLevelCode = LevelCode
FROM DimReadingScale WHERE ScaleSystem = 'FR_Reading' AND ActiveFlag = 1
ORDER BY ABS(LevelOrder - @FrMid), LevelOrder;

-- =============================================================================
-- 3) Resolve a current reading window + a current writing window to attach the
--    facts to (most recent active of each). Both EN and FR facts attach to the same
--    reading window; both writing facts to the same writing window — the LANGUAGE is
--    carried by the scale / AssessmentLanguage on the fact, not the window, and sharing
--    one window per subject keeps all the sentinel's rows inside a single cycle so a
--    cycle-scoped view shows them too.
-- =============================================================================
-- Prefer a window whose grade range COVERS the sentinel (so the benchmark join — grade x window
-- month x family — resolves and Expected shows); fall back to any active window of that subject.
SELECT TOP 1 @ReadingWindowId = w.AssessmentWindowID
FROM DimAssessmentWindow w
JOIN DimGrade gmin ON gmin.GradeCode = w.MinGrade
JOIN DimGrade gmax ON gmax.GradeCode = w.MaxGrade
WHERE w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
  AND @StudentGradeOrder BETWEEN gmin.GradeOrder AND gmax.GradeOrder
ORDER BY w.StartDate DESC, w.AssessmentWindowID DESC;

IF @ReadingWindowId IS NULL
    SELECT TOP 1 @ReadingWindowId = AssessmentWindowID
    FROM DimAssessmentWindow WHERE AssessmentType = 'Reading' AND ActiveFlag = 1
    ORDER BY StartDate DESC, AssessmentWindowID DESC;

SELECT TOP 1 @WritingWindowId = w.AssessmentWindowID
FROM DimAssessmentWindow w
JOIN DimGrade gmin ON gmin.GradeCode = w.MinGrade
JOIN DimGrade gmax ON gmax.GradeCode = w.MaxGrade
WHERE w.AssessmentType = 'Writing' AND w.ActiveFlag = 1
  AND @StudentGradeOrder BETWEEN gmin.GradeOrder AND gmax.GradeOrder
ORDER BY w.StartDate DESC, w.AssessmentWindowID DESC;

IF @WritingWindowId IS NULL
    SELECT TOP 1 @WritingWindowId = AssessmentWindowID
    FROM DimAssessmentWindow WHERE AssessmentType = 'Writing' AND ActiveFlag = 1
    ORDER BY StartDate DESC, AssessmentWindowID DESC;

IF @StaffKey IS NULL OR @EnScaleId IS NULL OR @FrScaleId IS NULL
   OR @ReadingWindowId IS NULL OR @WritingWindowId IS NULL
BEGIN
    ;THROW 60002, 'seed_dual_language_sentinel_dev: could not resolve staff / EN scale / FR scale / reading window / writing window on dev. Nothing seeded.', 1;
END;

-- =============================================================================
-- 4) Seed the facts (idempotent: wipe this sentinel's prior facts, then insert).
--    Distinct levels/deltas per language so the two stacked rows read differently:
--      Reading  EN -> on-level (delta 0),  FR -> below (delta -2)
--      Writing  English avg 3.00 (Meeting), French avg 2.00 (Approaching)
-- =============================================================================
DELETE FROM FactAssessmentReading WHERE StudentNumber = @StudentNumber;
DELETE FROM FactAssessmentWriting WHERE StudentNumber = @StudentNumber;

INSERT INTO FactAssessmentReading (
    StudentKey, StudentNumber, AssessmentWindowID, ReadingScaleID, ReadingDelta,
    LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode,
    AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
)
VALUES
    (@StudentKey, @StudentNumber, @ReadingWindowId, @EnScaleId,  0, @EnLevelCode, NULL, NULL, @Today, @StaffKey, @Now, @Now),
    (@StudentKey, @StudentNumber, @ReadingWindowId, @FrScaleId, -2, @FrLevelCode, NULL, NULL, @Today, @StaffKey, @Now, @Now);

INSERT INTO FactAssessmentWriting (
    StudentKey, StudentNumber, AssessmentWindowID, AssessmentLanguage,
    IdeasScore, OrganizationScore, LanguageScore, ConventionsScore, WritingAverage,
    AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
)
VALUES
    (@StudentKey, @StudentNumber, @WritingWindowId, 'English', '3', '3', '3', '3', 3.00, @Today, @StaffKey, @Now, @Now),
    (@StudentKey, @StudentNumber, @WritingWindowId, 'French',  '2', '2', '2', '2', 2.00, @Today, @StaffKey, @Now, @Now);

INSERT INTO FactSubmissionAudit (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
VALUES ('Seed', 'DevSeed', 'seed_dual_language_sentinel_dev.sql', @Now, 'Accepted',
        CONCAT('Dual-language sentinel seeded | StudentNumber=', CAST(@StudentNumber AS VARCHAR(20)),
               ' | EN scale=', @EnLevelCode, ' | FR scale=', @FrLevelCode), 4, @Now);

SELECT CONCAT('Seeded sentinel StudentNumber=', CAST(@StudentNumber AS VARCHAR(20)),
              ' (', @SentinelFirst, ' ', @SentinelLast, ') — EN ', @EnLevelCode,
              ' / FR ', @FrLevelCode, '; writing EN 3.00 / FR 2.00.') AS Result;
GO

-- =============================================================================
-- 5) VERIFY (re-resolve by the unique name — variables do not cross GO).
--    Expect: 2 reading rows (one EN_Reading, one FR_Reading) and 2 writing rows
--    (English + French) for the one sentinel student.
-- =============================================================================
SELECT 'Reading' AS Fact, drs.ScaleSystem AS Lang, far.LevelCode, far.ReadingDelta,
       far.AssessmentDate, far.AssessmentWindowID
FROM FactAssessmentReading far
JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
JOIN DimStudent s ON s.StudentNumber = far.StudentNumber AND s.IsCurrent = 1
WHERE s.FirstName = 'Dualang' AND s.LastName = 'Sentinel'
UNION ALL
SELECT 'Writing' AS Fact, faw.AssessmentLanguage AS Lang,
       CONCAT(faw.IdeasScore, '/', faw.OrganizationScore, '/', faw.LanguageScore, '/', faw.ConventionsScore),
       CAST(faw.WritingAverage AS INT), faw.AssessmentDate, faw.AssessmentWindowID
FROM FactAssessmentWriting faw
JOIN DimStudent s ON s.StudentNumber = faw.StudentNumber AND s.IsCurrent = 1
WHERE s.FirstName = 'Dualang' AND s.LastName = 'Sentinel'
ORDER BY Fact, Lang;
GO

-- IPP gates: expect every current row IsIPP = 0 (resolved → chart-eligible). Any NULL here would
-- re-blank Expected/Diff/Achievement in the report.
SELECT fsi.Subject, fsi.ProgramFamily, fsi.IsIPP, fsi.IsCurrent
FROM FactStudentIPP fsi
JOIN DimStudent s ON s.StudentKey = fsi.StudentKey AND s.IsCurrent = 1
WHERE s.FirstName = 'Dualang' AND s.LastName = 'Sentinel' AND fsi.IsCurrent = 1
ORDER BY fsi.Subject, fsi.ProgramFamily;
GO
