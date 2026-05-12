/*******************************************************************************
 * Seed: DimReadingScale — French reading scale (FR_Reading)
 * Purpose: Populate the 32 valid French-reading levels — TD (Texte Dicté,
 *          pre-emergent) plus numeric levels 1-30 plus 30+ (no-upper-bound
 *          marker for strong readers).
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * LevelOrder semantics:
 *   - 0  = TD  (Texte Dicté — pre-emergent reader, parallel to English DT)
 *   - 1  to 30 = numeric reading levels (LevelOrder = level number)
 *   - 31 = 30+ (submittable level for strong readers past 30; also used as
 *               ExpectedMaxLevel in DimReadingBenchmark to mean "no upper
 *               bound" — student at any level >= 30 is in range)
 *
 * Both TD and 30+ are submittable — teachers can record them as a student's
 * actual level. ActiveFlag = 1 for all rows; the dropdown filter in
 * cmbNewLevel will use ScaleSystem + ActiveFlag, no additional gating needed.
 *
 * ReadingDelta computation matches the English path:
 *   - 0 when min <= student <= max
 *   - student - min when student < min (negative)
 *   - student - max when student > max (positive)
 * Pre-CASE NULL validation throws 51001 if any LevelOrder failed to resolve.
 *
 * Run order: after DimReadingScale.sql has created the table; can run before
 * or after seed_DimReadingScale_EN.sql (different ScaleSystem values, no
 * key collision).
 ******************************************************************************/

INSERT INTO DimReadingScale (LevelCode, LevelOrder, ScaleSystem, Description, ActiveFlag, LastUpdated) VALUES
    ('TD',   0, 'FR_Reading', 'Texte Dicté (pre-emergent French reader)',     1, GETDATE()),
    ('1',    1, 'FR_Reading', 'French Reading Level 1',                        1, GETDATE()),
    ('2',    2, 'FR_Reading', 'French Reading Level 2',                        1, GETDATE()),
    ('3',    3, 'FR_Reading', 'French Reading Level 3',                        1, GETDATE()),
    ('4',    4, 'FR_Reading', 'French Reading Level 4',                        1, GETDATE()),
    ('5',    5, 'FR_Reading', 'French Reading Level 5',                        1, GETDATE()),
    ('6',    6, 'FR_Reading', 'French Reading Level 6',                        1, GETDATE()),
    ('7',    7, 'FR_Reading', 'French Reading Level 7',                        1, GETDATE()),
    ('8',    8, 'FR_Reading', 'French Reading Level 8',                        1, GETDATE()),
    ('9',    9, 'FR_Reading', 'French Reading Level 9',                        1, GETDATE()),
    ('10',  10, 'FR_Reading', 'French Reading Level 10',                       1, GETDATE()),
    ('11',  11, 'FR_Reading', 'French Reading Level 11',                       1, GETDATE()),
    ('12',  12, 'FR_Reading', 'French Reading Level 12',                       1, GETDATE()),
    ('13',  13, 'FR_Reading', 'French Reading Level 13',                       1, GETDATE()),
    ('14',  14, 'FR_Reading', 'French Reading Level 14',                       1, GETDATE()),
    ('15',  15, 'FR_Reading', 'French Reading Level 15',                       1, GETDATE()),
    ('16',  16, 'FR_Reading', 'French Reading Level 16',                       1, GETDATE()),
    ('17',  17, 'FR_Reading', 'French Reading Level 17',                       1, GETDATE()),
    ('18',  18, 'FR_Reading', 'French Reading Level 18',                       1, GETDATE()),
    ('19',  19, 'FR_Reading', 'French Reading Level 19',                       1, GETDATE()),
    ('20',  20, 'FR_Reading', 'French Reading Level 20',                       1, GETDATE()),
    ('21',  21, 'FR_Reading', 'French Reading Level 21',                       1, GETDATE()),
    ('22',  22, 'FR_Reading', 'French Reading Level 22',                       1, GETDATE()),
    ('23',  23, 'FR_Reading', 'French Reading Level 23',                       1, GETDATE()),
    ('24',  24, 'FR_Reading', 'French Reading Level 24',                       1, GETDATE()),
    ('25',  25, 'FR_Reading', 'French Reading Level 25',                       1, GETDATE()),
    ('26',  26, 'FR_Reading', 'French Reading Level 26',                       1, GETDATE()),
    ('27',  27, 'FR_Reading', 'French Reading Level 27',                       1, GETDATE()),
    ('28',  28, 'FR_Reading', 'French Reading Level 28',                       1, GETDATE()),
    ('29',  29, 'FR_Reading', 'French Reading Level 29',                       1, GETDATE()),
    ('30',  30, 'FR_Reading', 'French Reading Level 30',                       1, GETDATE()),
    ('30+', 31, 'FR_Reading', 'French Reading Level 30+ (above grade ceiling)',1, GETDATE());
