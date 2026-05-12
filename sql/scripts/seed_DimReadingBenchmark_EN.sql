/*******************************************************************************
 * Seed: DimReadingBenchmark — English reading scale, Grades P-7, Sept-Jun
 * Purpose: TCRCE's expected reading-level ranges for English instruction.
 *          Source: assessment team (provided 2026-05-12 as two grade × month
 *          matrices, Expected Min and Expected Max). User-verified.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * AssessmentMonth uses calendar month numbers (1-12). Academic year months
 * covered: Sept=9, Oct=10, Nov=11, Dec=12, Jan=1, Feb=2, Mar=3, Apr=4,
 * May=5, Jun=6. Rows are ordered Sept-Jun within each grade for readability.
 *
 * ProgramFamily = 'English' for all rows in this batch. The matrix applies
 * to students whose instructional program is in the English family.
 *
 * Grade 7 carry-over: Students who didn't reach grade level by end of Grade 6
 * continue to be assessed in Grade 7 against the Grade 6 end-of-year
 * expectation (Z to Z). The Grade 7 rows here mirror that fixed expectation
 * across all months. Confirmation pending on whether Grade 8+ extends this
 * pattern (open question 2026-05-12).
 *
 * Pending future seed batches:
 *   - Grade 8+ carry-over (if used)
 *   - French Immersion French-literacy scale (different ScaleSystem, different
 *     level codes — likely 'FR_Reading' or similar; awaiting team input)
 *   - French Second Language scale
 *
 * Run order: after DimReadingBenchmark.sql has created the table.
 ******************************************************************************/

INSERT INTO DimReadingBenchmark
    (ScaleSystem, ProgramFamily, GradeCode, AssessmentMonth, ExpectedMinLevel, ExpectedMaxLevel, LastUpdated)
VALUES
    -- ============== Grade P (Primary) ==============
    ('EN_Reading', 'English', 'P',  9, 'DT', 'DT', GETDATE()),
    ('EN_Reading', 'English', 'P', 10, 'DT', 'DT', GETDATE()),
    ('EN_Reading', 'English', 'P', 11, 'DT', 'A',  GETDATE()),
    ('EN_Reading', 'English', 'P', 12, 'A',  'A',  GETDATE()),
    ('EN_Reading', 'English', 'P',  1, 'A',  'A',  GETDATE()),
    ('EN_Reading', 'English', 'P',  2, 'A',  'B',  GETDATE()),
    ('EN_Reading', 'English', 'P',  3, 'B',  'B',  GETDATE()),
    ('EN_Reading', 'English', 'P',  4, 'C',  'C',  GETDATE()),
    ('EN_Reading', 'English', 'P',  5, 'C',  'C',  GETDATE()),
    ('EN_Reading', 'English', 'P',  6, 'C',  'D',  GETDATE()),

    -- ============== Grade 1 ==============
    ('EN_Reading', 'English', '1',  9, 'C',  'D',  GETDATE()),
    ('EN_Reading', 'English', '1', 10, 'D',  'D',  GETDATE()),
    ('EN_Reading', 'English', '1', 11, 'D',  'E',  GETDATE()),
    ('EN_Reading', 'English', '1', 12, 'E',  'E',  GETDATE()),
    ('EN_Reading', 'English', '1',  1, 'E',  'F',  GETDATE()),
    ('EN_Reading', 'English', '1',  2, 'F',  'F',  GETDATE()),
    ('EN_Reading', 'English', '1',  3, 'G',  'G',  GETDATE()),
    ('EN_Reading', 'English', '1',  4, 'G',  'G',  GETDATE()),
    ('EN_Reading', 'English', '1',  5, 'H',  'H',  GETDATE()),
    ('EN_Reading', 'English', '1',  6, 'I',  'I',  GETDATE()),

    -- ============== Grade 2 ==============
    ('EN_Reading', 'English', '2',  9, 'I',  'I',  GETDATE()),
    ('EN_Reading', 'English', '2', 10, 'I',  'I',  GETDATE()),
    ('EN_Reading', 'English', '2', 11, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2', 12, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2',  1, 'J',  'J',  GETDATE()),
    ('EN_Reading', 'English', '2',  2, 'K',  'K',  GETDATE()),
    ('EN_Reading', 'English', '2',  3, 'K',  'K',  GETDATE()),
    ('EN_Reading', 'English', '2',  4, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '2',  5, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '2',  6, 'L',  'L',  GETDATE()),

    -- ============== Grade 3 ==============
    ('EN_Reading', 'English', '3',  9, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '3', 10, 'L',  'L',  GETDATE()),
    ('EN_Reading', 'English', '3', 11, 'M',  'M',  GETDATE()),
    ('EN_Reading', 'English', '3', 12, 'M',  'M',  GETDATE()),
    ('EN_Reading', 'English', '3',  1, 'N',  'N',  GETDATE()),
    ('EN_Reading', 'English', '3',  2, 'O',  'O',  GETDATE()),
    ('EN_Reading', 'English', '3',  3, 'O',  'O',  GETDATE()),
    ('EN_Reading', 'English', '3',  4, 'O',  'P',  GETDATE()),
    ('EN_Reading', 'English', '3',  5, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '3',  6, 'P',  'P',  GETDATE()),

    -- ============== Grade 4 ==============
    ('EN_Reading', 'English', '4',  9, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 10, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 11, 'P',  'P',  GETDATE()),
    ('EN_Reading', 'English', '4', 12, 'Q',  'Q',  GETDATE()),
    ('EN_Reading', 'English', '4',  1, 'Q',  'Q',  GETDATE()),
    ('EN_Reading', 'English', '4',  2, 'Q',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  3, 'R',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  4, 'R',  'R',  GETDATE()),
    ('EN_Reading', 'English', '4',  5, 'R',  'S',  GETDATE()),
    ('EN_Reading', 'English', '4',  6, 'S',  'S',  GETDATE()),

    -- ============== Grade 5 ==============
    ('EN_Reading', 'English', '5',  9, 'S',  'S',  GETDATE()),
    ('EN_Reading', 'English', '5', 10, 'S',  'S',  GETDATE()),
    ('EN_Reading', 'English', '5', 11, 'S',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5', 12, 'T',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5',  1, 'T',  'T',  GETDATE()),
    ('EN_Reading', 'English', '5',  2, 'T',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  3, 'U',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  4, 'U',  'U',  GETDATE()),
    ('EN_Reading', 'English', '5',  5, 'U',  'V',  GETDATE()),
    ('EN_Reading', 'English', '5',  6, 'V',  'V',  GETDATE()),

    -- ============== Grade 6 ==============
    ('EN_Reading', 'English', '6',  9, 'V',  'V',  GETDATE()),
    ('EN_Reading', 'English', '6', 10, 'V',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6', 11, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6', 12, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6',  1, 'W',  'W',  GETDATE()),
    ('EN_Reading', 'English', '6',  2, 'X',  'X',  GETDATE()),
    ('EN_Reading', 'English', '6',  3, 'X',  'Y',  GETDATE()),
    ('EN_Reading', 'English', '6',  4, 'Y',  'Y',  GETDATE()),
    ('EN_Reading', 'English', '6',  5, 'Y',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '6',  6, 'Z',  'Z',  GETDATE()),

    -- ============== Grade 7 carry-over (Grade 6 end-of-year expectation) ==============
    -- Students who didn't reach grade level by end of Grade 6 continue being
    -- assessed against the Grade 6 June expectation (Z to Z) regardless of
    -- the actual month. Open question 2026-05-12: does Grade 8+ extend
    -- this pattern? If yes, add corresponding rows.
    ('EN_Reading', 'English', '7',  9, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 10, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 11, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7', 12, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  1, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  2, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  3, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  4, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  5, 'Z',  'Z',  GETDATE()),
    ('EN_Reading', 'English', '7',  6, 'Z',  'Z',  GETDATE());
