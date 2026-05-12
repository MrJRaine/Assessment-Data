/*******************************************************************************
 * Seed: DimReadingScale
 * Purpose: Populate the 27 valid English-reading levels — DT (pre-emergent
 *          dictated text) plus 26 letter levels A-Z.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * LevelOrder semantics:
 *   - 0 = DT (pre-emergent reader who isn't yet at independent reading)
 *   - 1-26 = letter levels A-Z, ordered by letter position
 *
 * DT is a valid submittable level — teachers can record a student at DT if
 * they haven't progressed to A yet. DT also appears as an expectation level
 * for Primary students early in the school year.
 *
 * ReadingDelta is computed in usp_UpsertReadingAssessment as a signed integer.
 * Three exhaustive cases on validated (non-NULL) inputs:
 *   - delta = 0 when min <= student <= max (explicit AND condition)
 *   - delta = student.LevelOrder - min.LevelOrder when student < min (negative)
 *   - delta = student.LevelOrder - max.LevelOrder when student > max (positive)
 * If any of student/min/max LevelOrder is NULL (failed lookup), the proc
 * THROWs error 51001 before reaching the CASE — no silent wrong answers.
 *
 * Run order: after DimReadingScale.sql has created the table; before any
 * FactAssessmentReading rows reference ReadingScaleID values.
 ******************************************************************************/

INSERT INTO DimReadingScale (LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag, LastUpdated) VALUES
    ('DT',  0, 'EN_Reading', 'Dictated Text (pre-emergent reader)',        1, GETDATE()),
    ('A',   1, 'EN_Reading', 'English Reading Level A',                     1, GETDATE()),
    ('B',   2, 'EN_Reading', 'English Reading Level B',                     1, GETDATE()),
    ('C',   3, 'EN_Reading', 'English Reading Level C',                     1, GETDATE()),
    ('D',   4, 'EN_Reading', 'English Reading Level D',                     1, GETDATE()),
    ('E',   5, 'EN_Reading', 'English Reading Level E',                     1, GETDATE()),
    ('F',   6, 'EN_Reading', 'English Reading Level F',                     1, GETDATE()),
    ('G',   7, 'EN_Reading', 'English Reading Level G',                     1, GETDATE()),
    ('H',   8, 'EN_Reading', 'English Reading Level H',                     1, GETDATE()),
    ('I',   9, 'EN_Reading', 'English Reading Level I',                     1, GETDATE()),
    ('J',  10, 'EN_Reading', 'English Reading Level J',                     1, GETDATE()),
    ('K',  11, 'EN_Reading', 'English Reading Level K',                     1, GETDATE()),
    ('L',  12, 'EN_Reading', 'English Reading Level L',                     1, GETDATE()),
    ('M',  13, 'EN_Reading', 'English Reading Level M',                     1, GETDATE()),
    ('N',  14, 'EN_Reading', 'English Reading Level N',                     1, GETDATE()),
    ('O',  15, 'EN_Reading', 'English Reading Level O',                     1, GETDATE()),
    ('P',  16, 'EN_Reading', 'English Reading Level P',                     1, GETDATE()),
    ('Q',  17, 'EN_Reading', 'English Reading Level Q',                     1, GETDATE()),
    ('R',  18, 'EN_Reading', 'English Reading Level R',                     1, GETDATE()),
    ('S',  19, 'EN_Reading', 'English Reading Level S',                     1, GETDATE()),
    ('T',  20, 'EN_Reading', 'English Reading Level T',                     1, GETDATE()),
    ('U',  21, 'EN_Reading', 'English Reading Level U',                     1, GETDATE()),
    ('V',  22, 'EN_Reading', 'English Reading Level V',                     1, GETDATE()),
    ('W',  23, 'EN_Reading', 'English Reading Level W',                     1, GETDATE()),
    ('X',  24, 'EN_Reading', 'English Reading Level X',                     1, GETDATE()),
    ('Y',  25, 'EN_Reading', 'English Reading Level Y',                     1, GETDATE()),
    ('Z',  26, 'EN_Reading', 'English Reading Level Z',                     1, GETDATE());
