/*******************************************************************************
 * Seed: DimReadingBenchmark — French reading scale, French Immersion only
 *                              Grades P-7, Sept-Jun
 * Purpose: TCRCE's expected French reading-level ranges for French Immersion
 *          students. Source: assessment team (provided 2026-05-12 as two
 *          grade × month matrices, Expected Min and Expected Max).
 *          User-verified.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * AssessmentMonth uses calendar month numbers (1-12). Academic year months
 * covered: Sept=9, Oct=10, Nov=11, Dec=12, Jan=1, Feb=2, Mar=3, Apr=4,
 * May=5, Jun=6.
 *
 * ProgramFamily = 'French Immersion' for all rows. French Second Language
 * is NOT covered by this scale (decided 2026-05-12 — separate batch may
 * arrive later if FSL is ever assessed).
 *
 * Special level handling:
 *   - 'TD' = Texte Dicté (pre-emergent), submittable, LevelOrder=0
 *   - '1'-'30' = numeric levels, LevelOrder = level number
 *   - '30+' = no-upper-bound marker for strong readers in Grade 6 from Nov
 *             onward, LevelOrder=31. ExpectedMaxLevel = '30+' means a
 *             student at any level >= 30 produces ReadingDelta=0.
 *
 * Grade 7 carry-over: Mirrors English pattern. FI students who didn't reach
 * 30+ by end of Grade 6 continue being assessed against the Grade 6 June
 * expectation (30 to 30+) for all months in Grade 7. Grade 8+ extension TBD
 * pending assessment-team confirmation.
 *
 * Run order: after DimReadingBenchmark.sql has created the table; can run
 * before or after seed_DimReadingBenchmark_EN.sql.
 ******************************************************************************/

INSERT INTO DimReadingBenchmark
    (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, ExpectedMinLevel, ExpectedMaxLevel, LastUpdated)
VALUES
    -- ============== Grade P (Primary) ==============
    ('FR_Reading', 'French Immersion', 'P',  9, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 10, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 11, 'TD', 'TD', GETDATE()),
    ('FR_Reading', 'French Immersion', 'P', 12, '1',  '1',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  1, '1',  '1',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  2, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  3, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  4, '1',  '2',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  5, '2',  '3',  GETDATE()),
    ('FR_Reading', 'French Immersion', 'P',  6, '3',  '4',  GETDATE()),

    -- ============== Grade 1 ==============
    ('FR_Reading', 'French Immersion', '1',  9, '2',  '3',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 10, '3',  '4',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 11, '4',  '5',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1', 12, '5',  '5',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  1, '5',  '6',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  2, '6',  '7',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  3, '7',  '8',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  4, '7',  '8',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  5, '8',  '9',  GETDATE()),
    ('FR_Reading', 'French Immersion', '1',  6, '9',  '10', GETDATE()),

    -- ============== Grade 2 ==============
    ('FR_Reading', 'French Immersion', '2',  9, '8',  '9',  GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 10, '9',  '10', GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 11, '10', '11', GETDATE()),
    ('FR_Reading', 'French Immersion', '2', 12, '11', '12', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  1, '12', '13', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  2, '12', '13', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  3, '13', '14', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  4, '13', '14', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  5, '14', '15', GETDATE()),
    ('FR_Reading', 'French Immersion', '2',  6, '15', '16', GETDATE()),

    -- ============== Grade 3 ==============
    ('FR_Reading', 'French Immersion', '3',  9, '14', '15', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 10, '15', '16', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 11, '16', '17', GETDATE()),
    ('FR_Reading', 'French Immersion', '3', 12, '17', '18', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  1, '17', '18', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  2, '18', '19', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  3, '19', '20', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  4, '19', '20', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  5, '20', '21', GETDATE()),
    ('FR_Reading', 'French Immersion', '3',  6, '21', '22', GETDATE()),

    -- ============== Grade 4 ==============
    ('FR_Reading', 'French Immersion', '4',  9, '20', '21', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 10, '21', '22', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 11, '22', '23', GETDATE()),
    ('FR_Reading', 'French Immersion', '4', 12, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  1, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  2, '23', '24', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  3, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  4, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  5, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '4',  6, '25', '26', GETDATE()),

    -- ============== Grade 5 ==============
    ('FR_Reading', 'French Immersion', '5',  9, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 10, '24', '25', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 11, '25', '26', GETDATE()),
    ('FR_Reading', 'French Immersion', '5', 12, '26', '27', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  1, '26', '27', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  2, '27', '28', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  3, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  4, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  5, '28', '29', GETDATE()),
    ('FR_Reading', 'French Immersion', '5',  6, '29', '30', GETDATE()),

    -- ============== Grade 6 ==============
    ('FR_Reading', 'French Immersion', '6',  9, '29', '30',  GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 10, '29', '30',  GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 11, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6', 12, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  1, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  2, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  3, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  4, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  5, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '6',  6, '30', '30+', GETDATE()),

    -- ============== Grade 7 carry-over (Grade 6 end-of-year expectation) ==============
    -- FI students who didn't reach grade level by end of Grade 6 continue
    -- being assessed against the Grade 6 June expectation (30 to 30+)
    -- regardless of the actual month. Mirrors the English EN_Reading carry-
    -- over pattern. Open question 2026-05-12: Grade 8+ extension?
    ('FR_Reading', 'French Immersion', '7',  9, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 10, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 11, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7', 12, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  1, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  2, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  3, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  4, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  5, '30', '30+', GETDATE()),
    ('FR_Reading', 'French Immersion', '7',  6, '30', '30+', GETDATE());
