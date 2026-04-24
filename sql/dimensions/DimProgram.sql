/*******************************************************************************
 * Table: DimProgram
 * Purpose: Reference dimension for PowerSchool program codes. Categorizes each
 *          code into grade band, program family, and specialty overlay.
 * SCD Type: N/A (static reference data, seeded once)
 * Created: 2026-04-24
 * Modified: 2026-04-24 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Code structure: Letter (grade band) + 3 digits
--   P = Pre-Primary, E = Elementary, J = Junior High, S = Senior High
--   100s = Options and Opportunities (O2) variant
--   200s = International Baccalaureate (IB) variant
--
-- Excluded from this table (intentionally):
--   - CSAP programs (P010, E010, J010, S010, S110, S210) — French-first-language
--     school board, not part of this platform's scope
--   - Adult High School (S050) and Vocational (S060, S061) — not in assessment scope
--   - TAP / Technology Advantage Program (S305) — program was discontinued

CREATE TABLE DimProgram (
    ProgramCode     VARCHAR(10)     NOT NULL,   -- Natural key, e.g. 'E015'
    ProgramName     VARCHAR(200)    NOT NULL,
    GradeBand       VARCHAR(50)     NOT NULL,   -- 'Pre-Primary', 'Elementary', 'Junior High', 'Senior High'
    ProgramFamily   VARCHAR(50)     NOT NULL,   -- 'English', 'French Immersion', 'French Second Language'
    IsImmersion     BIT             NOT NULL,   -- Quick filter flag: 1 = French Immersion program
    SpecialtyType   VARCHAR(50)     NULL,       -- 'O2' (Options and Opportunities), 'IB' (International Baccalaureate), NULL otherwise
    ActiveFlag      BIT             NOT NULL,
    LastUpdated     DATETIME2(0)    NOT NULL
);

-- Seed with all supported program codes in a single set-based INSERT
INSERT INTO DimProgram (ProgramCode, ProgramName, GradeBand, ProgramFamily, IsImmersion, SpecialtyType, ActiveFlag, LastUpdated)
VALUES
    -- Pre-Primary
    ('P005', 'Pre-Primary English',                         'Pre-Primary',  'English',                   0, NULL,  1, GETDATE()),

    -- Elementary
    ('E005', 'Elementary English',                          'Elementary',   'English',                   0, NULL,  1, GETDATE()),
    ('E015', 'Elementary French Immersion',                 'Elementary',   'French Immersion',          1, NULL,  1, GETDATE()),
    ('E025', 'Intensive French',                            'Elementary',   'French Second Language',    0, NULL,  1, GETDATE()),

    -- Junior High
    ('J005', 'Junior High English',                         'Junior High',  'English',                   0, NULL,  1, GETDATE()),
    ('J015', 'Junior High Early French Immersion',          'Junior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('J020', 'Junior High Late French Immersion',           'Junior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('J025', 'Junior High Integrated French',               'Junior High',  'French Second Language',    0, NULL,  1, GETDATE()),

    -- Senior High - Standard
    ('S005', 'Senior High English',                         'Senior High',  'English',                   0, NULL,  1, GETDATE()),
    ('S015', 'Senior High Early French Immersion',          'Senior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('S020', 'Senior High Late French Immersion',           'Senior High',  'French Immersion',          1, NULL,  1, GETDATE()),
    ('S025', 'Senior High Integrated French',               'Senior High',  'French Second Language',    0, NULL,  1, GETDATE()),

    -- Senior High - Options and Opportunities (O2) overlay
    ('S105', 'Senior High English O2',                      'Senior High',  'English',                   0, 'O2',  1, GETDATE()),
    ('S115', 'Senior High Early French Immersion O2',       'Senior High',  'French Immersion',          1, 'O2',  1, GETDATE()),
    ('S120', 'Senior High Late French Immersion O2',        'Senior High',  'French Immersion',          1, 'O2',  1, GETDATE()),
    ('S125', 'Senior High Integrated French O2',            'Senior High',  'French Second Language',    0, 'O2',  1, GETDATE()),

    -- Senior High - International Baccalaureate (IB) overlay
    ('S205', 'Senior High English IB',                      'Senior High',  'English',                   0, 'IB',  1, GETDATE()),
    ('S215', 'Senior High Early French Immersion IB',       'Senior High',  'French Immersion',          1, 'IB',  1, GETDATE()),
    ('S220', 'Senior High Late French Immersion IB',        'Senior High',  'French Immersion',          1, 'IB',  1, GETDATE()),
    ('S225', 'Senior High Integrated French IB',            'Senior High',  'French Second Language',    0, 'IB',  1, GETDATE());
