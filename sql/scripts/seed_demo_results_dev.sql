/*******************************************************************************
 * Script:  seed_demo_results_dev.sql
 * Purpose: Populate the synthetic DEV students with believable result history so
 *          the demo environment "looks right": a prior-year JUNE Short Cycle
 *          (Reading + Writing) and a partially-entered current SHORT CYCLE 1
 *          (Reading + Writing + Math, half of each class).
 *
 *          Values are drawn on a BELL CURVE (approx-normal via an Irwin-Hall sum
 *          of 3 uniforms, std ~0.5) around a per-subject expected TARGET:
 *            - Reading : centre = the DECIMAL AVERAGE of the grade/month benchmark
 *                        ExpectedMin & ExpectedMax level-orders, + offset, then
 *                        ROUND-HALF-TO-EVEN, clamped to the scale. ReadingDelta is
 *                        computed vs that same benchmark band.
 *            - Writing : each trait centred on ACHIEVEMENT LEVEL 2 (Approaching —
 *                        "between Not Yet Meeting and Meeting"), + offset, clamped 1-4.
 *            - Math    : a per-student mastery RATE centred on 0.65, + offset,
 *                        clamped; each task then marked 1 with that probability, so a
 *                        class averages ~65% while individual students spread.
 *
 *          RANDOMNESS is SEEDED per student via HASHBYTES(StudentKey + salt), NOT
 *          NEWID(). Fabric hoists a NEWID() CROSS APPLY to a single per-query value
 *          (which flattened every student in a class to the same level); a hash of
 *          a per-row column can't be folded, so it varies per student AND is
 *          reproducible on re-run. Different salts give independent draws.
 *
 *          JUNE uses each student's grade MINUS 1 (a current Gr-4 was Gr-3 last June)
 *          and month 6; current GRADE P is EXCLUDED from June (not enrolled then).
 *          MATH has NO June data. SHORT CYCLE 1 covers HALF of each homeroom (a
 *          deterministic split on StudentKey, so the same half across all subjects).
 *
 * READS:   DimStudent, DimProgram, DimGrade, DimReadingBenchmark, DimReadingScale,
 *          DimMathTask, DimStaff, DimShortCycle, DimAssessmentWindow.
 * WRITES:  DimShortCycle + DimAssessmentWindow (a new prior-year "June 2026" SCoR,
 *          copied from SC1's Reading/Writing instances), FactAssessmentReading,
 *          FactAssessmentWriting, FactAssessmentMath.
 *
 * SAFE:    DEV-ONLY (aborts if DB_NAME() is not the _Dev warehouse). IDEMPOTENT:
 *          a re-run first DELETES this script's own prior rows (matched by the seed
 *          StaffKey) across the June + SC1 cycles, then regenerates them — so fixing
 *          the values and re-running fully refreshes them. Real teacher entries (any
 *          OTHER StaffKey) are never touched, and SC1 inserts still skip a student who
 *          already has a real entry. Seeded values are reproducible per student.
 *
 * Created: 2026-09-22 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev data only.
 *
 * ---- Per-row bell draw, keyed by a hash so it varies per student ----
 * One HASHBYTES('SHA2_256', <key>+<salt>) yields 32 bytes; three disjoint 8-byte
 * windows give three uniforms in [0,1); their sum minus 1.5 is ~N(0, 0.5^2). The hash
 * is computed once per row in a CROSS APPLY hb(h); the sum is re-derived from hb.h
 * (same bytes => same value each time it's referenced).
 ******************************************************************************/

------------------------------------------------------------------------------
-- 0. DEV guard — refuse to run anywhere but the _Dev warehouse.
------------------------------------------------------------------------------
IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'seed_demo_results_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

------------------------------------------------------------------------------
-- 1. Resolve the moving pieces (BEFORE creating June, so June isn't picked as SC1).
------------------------------------------------------------------------------
DECLARE @SC1CGID   VARCHAR(36);
DECLARE @JuneCGID  VARCHAR(36) = '6a11e000-2026-406e-9c17-0de100062026'; -- fixed => idempotent
DECLARE @SeedStaff BIGINT;
DECLARE @JuneDate  DATE = '2026-06-15';
DECLARE @SC1Date   DATE;

-- SC1 = the earliest active Short Cycle (cycle 1 of the year), EXCLUDING the prior-year
-- June demo cycle this script creates (its 2026-06-01 start would otherwise sort first
-- and steal @SC1CGID on a re-run, sending the "SC1" inserts at the June windows).
SELECT TOP 1 @SC1CGID = CycleGroupID
FROM dbo.DimShortCycle
WHERE ActiveFlag = 1 AND CycleGroupID <> @JuneCGID
ORDER BY StartDate ASC, CycleGroupID;

SELECT @SC1Date = DATEADD(DAY, 3, StartDate)
FROM dbo.DimShortCycle WHERE CycleGroupID = @SC1CGID;

SELECT TOP 1 @SeedStaff = StaffKey
FROM dbo.DimStaff
WHERE IsCurrent = 1 AND ActiveFlag = 1
ORDER BY CASE WHEN AccessLevel = 'RegionalAnalyst' THEN 0 ELSE 1 END, StaffKey;

IF @SC1CGID IS NULL OR @SeedStaff IS NULL
BEGIN
    ;THROW 50001, 'Could not resolve SC1 cycle or a seed staff key — is dev seeded with a Short Cycle and staff?', 1;
END;

-- Spread factors: Irwin-Hall(3) has std ~0.5, so multiply to reach the target sigma.
DECLARE @ReadSpread  DECIMAL(9,4) = 3.00;  -- ~1.5 reading levels
DECLARE @WriteSpread DECIMAL(9,4) = 1.80;  -- ~0.9 achievement points
DECLARE @MathSpread  DECIMAL(9,4) = 0.30;  -- ~0.15 mastery rate

------------------------------------------------------------------------------
-- 2. Create the prior-year "June 2026" SCoR by COPYING SC1's Reading + Writing
--    instances (mirrors dev exactly; Math excluded — no June math).
------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimShortCycle WHERE CycleGroupID = @JuneCGID)
    INSERT INTO dbo.DimShortCycle
        (CycleGroupID, DisplayName, StartDate, EndDate, SchoolYear, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
    VALUES
        (@JuneCGID, 'June 2026 (prior year)', '2026-06-01', '2026-06-30', '2025-2026', 1, GETDATE(), 'seed_demo_results_dev', GETDATE());

INSERT INTO dbo.DimAssessmentWindow
    (WindowName, AssessmentType, SchoolYear, StartDate, EndDate, MinGrade, MaxGrade,
     ProgramFamily, ProgramScope, ScaleSystem, AssessmentLanguage, BenchmarkMonth,
     CycleGroupID, ActiveFlag, CreatedDate, CreatedBy, LastUpdated)
SELECT
    'June 2026 (prior year)', w.AssessmentType, '2025-2026', '2026-06-01', '2026-06-30',
    w.MinGrade, w.MaxGrade, w.ProgramFamily, w.ProgramScope, w.ScaleSystem, w.AssessmentLanguage,
    CASE WHEN w.AssessmentType = 'Reading' THEN 6 ELSE NULL END,
    @JuneCGID, 1, GETDATE(), 'seed_demo_results_dev', GETDATE()
FROM dbo.DimAssessmentWindow w
WHERE w.CycleGroupID = @SC1CGID
  AND w.AssessmentType IN ('Reading', 'Writing')
  AND NOT EXISTS (
      SELECT 1 FROM dbo.DimAssessmentWindow j
      WHERE j.CycleGroupID = @JuneCGID
        AND j.AssessmentType = w.AssessmentType
        AND ISNULL(j.ProgramScope, '~')      = ISNULL(w.ProgramScope, '~')
        AND ISNULL(j.AssessmentLanguage, '~') = ISNULL(w.AssessmentLanguage, '~')
        AND j.MinGrade = w.MinGrade AND j.MaxGrade = w.MaxGrade
  );

-- ============================================================================
-- 3. Idempotent re-seed: remove ONLY previously-seeded rows (this seed StaffKey)
--    across the June + SC1 cycles so a re-run fully regenerates them. Real teacher
--    entries (any OTHER StaffKey) are left untouched.
-- ============================================================================
DELETE f FROM dbo.FactAssessmentReading f
JOIN dbo.DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
WHERE w.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff;

DELETE f FROM dbo.FactAssessmentWriting f
JOIN dbo.DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
WHERE w.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff;

DELETE f FROM dbo.FactAssessmentMath f
JOIN dbo.DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
WHERE w.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff;

-- ============================================================================
-- 3a. READING — JUNE (grade-1 rollback, month 6, grade P excluded)
-- ============================================================================
;WITH RB AS (
    SELECT b.ScaleSystem, b.GradeCode, b.AssessmentMonth,
           b.ExpectedMinLevel, b.ExpectedMaxLevel,
           mn.LevelOrder AS MinOrd, mx.LevelOrder AS MaxOrd,
           (mn.LevelOrder + mx.LevelOrder) / 2.0 AS AvgOrd
    FROM dbo.DimReadingBenchmark b
    JOIN dbo.DimReadingScale mn ON mn.ScaleSystem = b.ScaleSystem AND mn.LevelCode = b.ExpectedMinLevel
    JOIN dbo.DimReadingScale mx ON mx.ScaleSystem = b.ScaleSystem AND mx.LevelCode = b.ExpectedMaxLevel
),
SM AS (SELECT ScaleSystem, MAX(LevelOrder) AS MaxLvlOrd FROM dbo.DimReadingScale GROUP BY ScaleSystem)
INSERT INTO dbo.FactAssessmentReading
    (StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta, LevelCode,
     ExpectedMinLevelCode, ExpectedMaxLevelCode, AssessmentDate, EnteredByStaffKey,
     SubmissionTimestamp, LastUpdated)
SELECT
    s.StudentKey, w.AssessmentWindowID, sc.ReadingScaleID,
    CASE WHEN o.ord < rb.MinOrd THEN o.ord - rb.MinOrd
         WHEN o.ord > rb.MaxOrd THEN o.ord - rb.MaxOrd ELSE 0 END,
    sc.LevelCode, rb.ExpectedMinLevel, rb.ExpectedMaxLevel,
    @JuneDate, @SeedStaff, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM dbo.DimStudent s
JOIN dbo.DimProgram p  ON p.ProgramCode = s.ProgramCode
JOIN dbo.DimGrade  cg  ON cg.GradeCode = s.Grade
JOIN dbo.DimGrade  pg  ON pg.GradeOrder = cg.GradeOrder - 1
JOIN dbo.DimAssessmentWindow w
      ON w.CycleGroupID = @JuneCGID AND w.AssessmentType = 'Reading'
     AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
JOIN RB rb ON rb.ScaleSystem = w.ScaleSystem AND rb.GradeCode = pg.GradeCode AND rb.AssessmentMonth = 6
JOIN SM sm ON sm.ScaleSystem = w.ScaleSystem
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), s.StudentKey) + 'rjun') )) hb(h)
CROSS APPLY (VALUES ( rb.AvgOrd + ( (((CONVERT(BIGINT,SUBSTRING(hb.h,1,8))%100000)+100000)%100000)/100000.0
                                  + (((CONVERT(BIGINT,SUBSTRING(hb.h,9,8))%100000)+100000)%100000)/100000.0
                                  + (((CONVERT(BIGINT,SUBSTRING(hb.h,17,8))%100000)+100000)%100000)/100000.0 - 1.5 ) * @ReadSpread )) r(raw)
CROSS APPLY (VALUES ( FLOOR(r.raw) )) f(n0)
CROSS APPLY (VALUES ( CASE WHEN r.raw - f.n0 < 0.5 THEN f.n0
                           WHEN r.raw - f.n0 > 0.5 THEN f.n0 + 1
                           ELSE f.n0 + (CONVERT(INT, f.n0) % 2) END )) rd(rord)   -- round half to EVEN
CROSS APPLY (VALUES ( CASE WHEN rd.rord < 0 THEN 0 WHEN rd.rord > sm.MaxLvlOrd THEN sm.MaxLvlOrd ELSE rd.rord END )) o(ord)
JOIN dbo.DimReadingScale sc ON sc.ScaleSystem = w.ScaleSystem AND sc.LevelOrder = o.ord
WHERE s.IsCurrent = 1 AND s.Grade <> 'P'
  AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder;

-- ============================================================================
-- 3b. READING — SHORT CYCLE 1 (current grade, SC1 month, HALF of each homeroom)
-- ============================================================================
;WITH RB AS (
    SELECT b.ScaleSystem, b.GradeCode, b.AssessmentMonth,
           b.ExpectedMinLevel, b.ExpectedMaxLevel,
           mn.LevelOrder AS MinOrd, mx.LevelOrder AS MaxOrd,
           (mn.LevelOrder + mx.LevelOrder) / 2.0 AS AvgOrd
    FROM dbo.DimReadingBenchmark b
    JOIN dbo.DimReadingScale mn ON mn.ScaleSystem = b.ScaleSystem AND mn.LevelCode = b.ExpectedMinLevel
    JOIN dbo.DimReadingScale mx ON mx.ScaleSystem = b.ScaleSystem AND mx.LevelCode = b.ExpectedMaxLevel
),
SM AS (SELECT ScaleSystem, MAX(LevelOrder) AS MaxLvlOrd FROM dbo.DimReadingScale GROUP BY ScaleSystem),
Half AS (
    SELECT s.StudentKey, s.Grade, s.ProgramCode,
           NTILE(2) OVER (PARTITION BY COALESCE(NULLIF(s.Homeroom, ''), CONCAT(s.SchoolID, '|', s.Grade))
                          ORDER BY s.StudentKey) AS HalfBucket
    FROM dbo.DimStudent s
    WHERE s.IsCurrent = 1
)
INSERT INTO dbo.FactAssessmentReading
    (StudentKey, AssessmentWindowID, ReadingScaleID, ReadingDelta, LevelCode,
     ExpectedMinLevelCode, ExpectedMaxLevelCode, AssessmentDate, EnteredByStaffKey,
     SubmissionTimestamp, LastUpdated)
SELECT
    h.StudentKey, w.AssessmentWindowID, sc.ReadingScaleID,
    CASE WHEN o.ord < rb.MinOrd THEN o.ord - rb.MinOrd
         WHEN o.ord > rb.MaxOrd THEN o.ord - rb.MaxOrd ELSE 0 END,
    sc.LevelCode, rb.ExpectedMinLevel, rb.ExpectedMaxLevel,
    @SC1Date, @SeedStaff, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM Half h
JOIN dbo.DimProgram p ON p.ProgramCode = h.ProgramCode
JOIN dbo.DimGrade  cg ON cg.GradeCode = h.Grade
JOIN dbo.DimAssessmentWindow w
      ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Reading'
     AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
JOIN RB rb ON rb.ScaleSystem = w.ScaleSystem AND rb.GradeCode = h.Grade
          AND rb.AssessmentMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate))
JOIN SM sm ON sm.ScaleSystem = w.ScaleSystem
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'rsc1') )) hb(h2)
CROSS APPLY (VALUES ( rb.AvgOrd + ( (((CONVERT(BIGINT,SUBSTRING(hb.h2,1,8))%100000)+100000)%100000)/100000.0
                                  + (((CONVERT(BIGINT,SUBSTRING(hb.h2,9,8))%100000)+100000)%100000)/100000.0
                                  + (((CONVERT(BIGINT,SUBSTRING(hb.h2,17,8))%100000)+100000)%100000)/100000.0 - 1.5 ) * @ReadSpread )) r(raw)
CROSS APPLY (VALUES ( FLOOR(r.raw) )) f(n0)
CROSS APPLY (VALUES ( CASE WHEN r.raw - f.n0 < 0.5 THEN f.n0
                           WHEN r.raw - f.n0 > 0.5 THEN f.n0 + 1
                           ELSE f.n0 + (CONVERT(INT, f.n0) % 2) END )) rd(rord)
CROSS APPLY (VALUES ( CASE WHEN rd.rord < 0 THEN 0 WHEN rd.rord > sm.MaxLvlOrd THEN sm.MaxLvlOrd ELSE rd.rord END )) o(ord)
JOIN dbo.DimReadingScale sc ON sc.ScaleSystem = w.ScaleSystem AND sc.LevelOrder = o.ord
WHERE h.HalfBucket = 1
  AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
  AND NOT EXISTS (SELECT 1 FROM dbo.FactAssessmentReading fr
                  WHERE fr.StudentKey = h.StudentKey AND fr.AssessmentWindowID = w.AssessmentWindowID);

-- ============================================================================
-- 3c. WRITING — JUNE (grade P excluded), then SC1 (half). Each trait = one seeded
--     bell draw around level 2, clamped 1..4. One row per writing instance.
-- ============================================================================
INSERT INTO dbo.FactAssessmentWriting
    (StudentKey, AssessmentWindowID, AssessmentLanguage, IdeasScore, OrganizationScore,
     LanguageScore, ConventionsScore, WritingAverage, AssessmentDate, EnteredByStaffKey,
     SubmissionTimestamp, LastUpdated)
SELECT
    s.StudentKey, w.AssessmentWindowID, w.AssessmentLanguage,
    ti.v, torg.v, tl.v, CONVERT(VARCHAR(10), tc.v),
    CONVERT(DECIMAL(4,2), (ti.v + torg.v + tl.v + tc.v) / 4.0),
    @JuneDate, @SeedStaff, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM dbo.DimStudent s
JOIN dbo.DimProgram p ON p.ProgramCode = s.ProgramCode
JOIN dbo.DimGrade  cg ON cg.GradeCode = s.Grade
JOIN dbo.DimAssessmentWindow w
      ON w.CycleGroupID = @JuneCGID AND w.AssessmentType = 'Writing'
     AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), s.StudentKey) + 'wji') )) hi(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) ti(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), s.StudentKey) + 'wjo') )) ho(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) torg(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), s.StudentKey) + 'wjl') )) hl(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) tl(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), s.StudentKey) + 'wjc') )) hc(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) tc(v)
WHERE s.IsCurrent = 1 AND s.Grade <> 'P'
  AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder;

-- WRITING — SHORT CYCLE 1 (half of each homeroom)
;WITH Half AS (
    SELECT s.StudentKey, s.Grade, s.ProgramCode,
           NTILE(2) OVER (PARTITION BY COALESCE(NULLIF(s.Homeroom, ''), CONCAT(s.SchoolID, '|', s.Grade))
                          ORDER BY s.StudentKey) AS HalfBucket
    FROM dbo.DimStudent s
    WHERE s.IsCurrent = 1
)
INSERT INTO dbo.FactAssessmentWriting
    (StudentKey, AssessmentWindowID, AssessmentLanguage, IdeasScore, OrganizationScore,
     LanguageScore, ConventionsScore, WritingAverage, AssessmentDate, EnteredByStaffKey,
     SubmissionTimestamp, LastUpdated)
SELECT
    h.StudentKey, w.AssessmentWindowID, w.AssessmentLanguage,
    ti.v, torg.v, tl.v, CONVERT(VARCHAR(10), tc.v),
    CONVERT(DECIMAL(4,2), (ti.v + torg.v + tl.v + tc.v) / 4.0),
    @SC1Date, @SeedStaff, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM Half h
JOIN dbo.DimProgram p ON p.ProgramCode = h.ProgramCode
JOIN dbo.DimGrade  cg ON cg.GradeCode = h.Grade
JOIN dbo.DimAssessmentWindow w
      ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Writing'
     AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'wsi') )) hi(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hi.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hi.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) ti(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'wso') )) ho(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(ho.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(ho.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) torg(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'wsl') )) hl(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hl.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hl.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) tl(v)
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'wsc') )) hc(h)
CROSS APPLY (VALUES ( CONVERT(INT, CASE WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread < 1 THEN 1 WHEN 2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread > 4 THEN 4 ELSE ROUND(2 + ((((CONVERT(BIGINT,SUBSTRING(hc.h,1,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,9,8))%100000)+100000)%100000)/100000.0+(((CONVERT(BIGINT,SUBSTRING(hc.h,17,8))%100000)+100000)%100000)/100000.0-1.5)*@WriteSpread, 0) END) )) tc(v)
WHERE h.HalfBucket = 1
  AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
  AND NOT EXISTS (SELECT 1 FROM dbo.FactAssessmentWriting fw
                  WHERE fw.StudentKey = h.StudentKey AND fw.AssessmentWindowID = w.AssessmentWindowID
                    AND ISNULL(fw.AssessmentLanguage, '~') = ISNULL(w.AssessmentLanguage, '~'));

-- ============================================================================
-- 3d. MATH — SHORT CYCLE 1 ONLY (half of each homeroom). Per-student mastery rate
--     ~N(0.65) seeded by StudentKey; each task then 1 with prob = rate, seeded by
--     (StudentKey, MathTaskKey) so a student's per-task pattern varies but is stable.
-- ============================================================================
;WITH Half AS (
    SELECT s.StudentKey, s.Grade, s.ProgramCode,
           NTILE(2) OVER (PARTITION BY COALESCE(NULLIF(s.Homeroom, ''), CONCAT(s.SchoolID, '|', s.Grade))
                          ORDER BY s.StudentKey) AS HalfBucket
    FROM dbo.DimStudent s
    WHERE s.IsCurrent = 1
),
MStud AS (
    SELECT h.StudentKey, h.Grade,
           CASE WHEN rate.v < 0.05 THEN 0.05 WHEN rate.v > 0.98 THEN 0.98 ELSE rate.v END AS Rate
    FROM Half h
    JOIN dbo.DimProgram p ON p.ProgramCode = h.ProgramCode
    JOIN dbo.DimAssessmentWindow w
          ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Math'
         AND (',' + w.ProgramScope + ',') LIKE ('%,' + p.ScopeBucket + ',%')
    JOIN dbo.DimGrade wmin ON wmin.GradeCode = w.MinGrade
    JOIN dbo.DimGrade wmax ON wmax.GradeCode = w.MaxGrade
    JOIN dbo.DimGrade cg   ON cg.GradeCode = h.Grade
    CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(60), h.StudentKey) + 'mrate') )) hb(h)
    CROSS APPLY (VALUES ( 0.65 + ( (((CONVERT(BIGINT,SUBSTRING(hb.h,1,8))%100000)+100000)%100000)/100000.0
                                 + (((CONVERT(BIGINT,SUBSTRING(hb.h,9,8))%100000)+100000)%100000)/100000.0
                                 + (((CONVERT(BIGINT,SUBSTRING(hb.h,17,8))%100000)+100000)%100000)/100000.0 - 1.5 ) * @MathSpread )) rate(v)
    WHERE h.HalfBucket = 1
      AND cg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
)
INSERT INTO dbo.FactAssessmentMath
    (StudentKey, AssessmentWindowID, MathTaskKey, Result, AssessmentDate,
     EnteredByStaffKey, SubmissionTimestamp, LastUpdated)
SELECT
    ms.StudentKey, w.AssessmentWindowID, mt.MathTaskKey,
    CASE WHEN (((CONVERT(BIGINT,SUBSTRING(bt.h,1,8))%100000)+100000)%100000)/100000.0 < ms.Rate
         THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END,
    @SC1Date, @SeedStaff, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM MStud ms
JOIN dbo.DimAssessmentWindow w ON w.CycleGroupID = @SC1CGID AND w.AssessmentType = 'Math'
JOIN dbo.DimMathTask mt
      ON mt.GradeCode = ms.Grade
     AND mt.AssessmentMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate))
     AND mt.ActiveFlag = 1
CROSS APPLY (VALUES ( HASHBYTES('SHA2_256', CONVERT(VARCHAR(20), ms.StudentKey) + ':' + CONVERT(VARCHAR(20), mt.MathTaskKey) + 'mt') )) bt(h)
WHERE NOT EXISTS (SELECT 1 FROM dbo.FactAssessmentMath fm
                  WHERE fm.StudentKey = ms.StudentKey
                    AND fm.AssessmentWindowID = w.AssessmentWindowID
                    AND fm.MathTaskKey = mt.MathTaskKey);

------------------------------------------------------------------------------
-- 4. Summary — what landed (seeded rows only).
------------------------------------------------------------------------------
SELECT 'Reading' AS Subject, w.DisplayName AS Cycle, COUNT(*) AS Rows
FROM dbo.FactAssessmentReading f
JOIN dbo.DimAssessmentWindow aw ON aw.AssessmentWindowID = f.AssessmentWindowID
JOIN dbo.DimShortCycle w ON w.CycleGroupID = aw.CycleGroupID
WHERE aw.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff
GROUP BY w.DisplayName
UNION ALL
SELECT 'Writing', w.DisplayName, COUNT(*)
FROM dbo.FactAssessmentWriting f
JOIN dbo.DimAssessmentWindow aw ON aw.AssessmentWindowID = f.AssessmentWindowID
JOIN dbo.DimShortCycle w ON w.CycleGroupID = aw.CycleGroupID
WHERE aw.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff
GROUP BY w.DisplayName
UNION ALL
SELECT 'Math', w.DisplayName, COUNT(*)
FROM dbo.FactAssessmentMath f
JOIN dbo.DimAssessmentWindow aw ON aw.AssessmentWindowID = f.AssessmentWindowID
JOIN dbo.DimShortCycle w ON w.CycleGroupID = aw.CycleGroupID
WHERE aw.CycleGroupID IN (@JuneCGID, @SC1CGID) AND f.EnteredByStaffKey = @SeedStaff
GROUP BY w.DisplayName
ORDER BY Subject, Cycle;
