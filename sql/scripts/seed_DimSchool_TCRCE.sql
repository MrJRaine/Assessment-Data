/*******************************************************************************
 * Script: seed_DimSchool_TCRCE.sql
 * Purpose: Seed DimSchool with all Tri-County Regional Centre for Education
 *          schools as of the 2024-2025 Directory of Public Schools.
 * Source:  Nova Scotia Department of Education 2024-2025 directory
 *          (abbreviations taken from each school's @tcrce.ca email prefix)
 * Safe to re-run: no — use TRUNCATE TABLE DimSchool first if re-seeding
 * Region:  Canada East (PIIDPA compliant)
 ******************************************************************************/

INSERT INTO DimSchool (SchoolID, SchoolName, Abbreviation, Community, ActiveFlag, LastUpdated)
VALUES
    ('0079', 'Hillcrest Academy',                              'HIA',   'Shelburne',       1, GETDATE()),
    ('0167', 'Barrington Municipal High School',               'BMHS',  'Barrington',      1, GETDATE()),
    ('0199', 'Plymouth School',                                'PS',    'Yarmouth',        1, GETDATE()),
    ('0256', 'Weymouth Consolidated School',                   'WCS',   'Weymouth',        1, GETDATE()),
    ('0257', 'Digby Neck Consolidated Elementary School',      'DNCES', 'Digby Neck',      1, GETDATE()),
    ('0259', 'Islands Consolidated School',                    'ICS',   'Freeport',        1, GETDATE()),
    ('0410', 'Maple Grove Education Centre',                   'MGEC',  'Hebron',          1, GETDATE()),
    ('0497', 'Carleton Consolidated Elementary School',        'CCES',  'Carleton',        1, GETDATE()),
    ('0498', 'Port Maitland Consolidated Elementary School',   'PMCES', 'Port Maitland',   1, GETDATE()),
    ('0511', 'Clark''s Harbour Elementary School',             'CHES',  'Clark''s Harbour', 1, GETDATE()),
    ('0541', 'Digby Elementary School',                        'DES',   'Digby',           1, GETDATE()),
    ('0624', 'Lockeport Elementary School',                    'LES',   'Lockeport',       1, GETDATE()),
    ('0709', 'Digby Regional High School',                     'DRHS',  'Digby',           1, GETDATE()),
    ('0711', 'Lockeport Regional High School',                 'LRHS',  'Lockeport',       1, GETDATE()),
    ('0716', 'Shelburne Regional High School',                 'SRHS',  'Shelburne',       1, GETDATE()),
    ('0733', 'Evelyn Richardson Memorial Elementary School',   'ERMES', 'Shag Harbour',    1, GETDATE()),
    ('0927', 'Forest Ridge Academy',                           'FRA',   'Barrington',      1, GETDATE()),
    ('0928', 'Meadowfields Community School',                  'MCS',   'Yarmouth',        1, GETDATE()),
    ('0977', 'St. Mary''s Bay Academy',                        'SMBA',  'St. Bernard',     1, GETDATE()),
    ('0981', 'Drumlin Heights Consolidated School',            'DHCS',  'Glenwood',        1, GETDATE()),
    ('1178', 'Yarmouth Consolidated Memorial High School',     'YCMHS', 'Yarmouth',        1, GETDATE()),
    ('1199', 'Yarmouth Elementary School',                     'YES',   'Yarmouth',        1, GETDATE());

-- Verify
SELECT COUNT(*) AS SchoolCount FROM DimSchool;   -- Expected: 22
SELECT * FROM DimSchool ORDER BY SchoolID;
