/*******************************************************************************
 * Script: test_slash_homeroom_dev.sql   (DEV synthetic only -- TEST FIXTURE)
 * Purpose: Give one current elementary (grade P-6) synthetic student a homeroom
 *          containing '/' ("5/6") and set its GroupKey accordingly, so the
 *          '/'-in-homeroom fix can be exercised end-to-end in awdev. Run AFTER
 *          deploying the GroupKey migration + merge proc + TVFs to dev.
 * Created: 2026-09-08
 * Region:  Canada East (PIIDPA compliant) — dev synthetic data only.
 ******************************************************************************/

UPDATE d
SET Homeroom    = '5/6',
    GroupKey    = COALESCE(sch.Abbreviation, d.SchoolID) + '-' +
                  REPLACE(REPLACE(REPLACE('5/6', '/', '-'), ' ', '-'), '\', '-'),
    LastUpdated = GETDATE()
FROM DimStudent d
LEFT JOIN DimSchool sch ON sch.SchoolID = d.SchoolID
WHERE d.StudentKey = (
    SELECT MIN(d2.StudentKey)
    FROM DimStudent d2
    INNER JOIN DimGrade g ON g.GradeCode = d2.Grade
    WHERE d2.IsCurrent = 1 AND g.GradeOrder BETWEEN 0 AND 6
);

-- Show the planted row: expect Homeroom '5/6' and a slash-free GroupKey like 'ABBR-5-6'.
SELECT StudentKey, SchoolID, Homeroom, GroupKey
FROM DimStudent
WHERE Homeroom = '5/6' AND IsCurrent = 1;
