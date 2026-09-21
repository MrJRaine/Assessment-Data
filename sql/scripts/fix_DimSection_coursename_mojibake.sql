/*******************************************************************************
 * Script: fix_DimSection_coursename_mojibake.sql
 * Purpose: Repair DOUBLE-ENCODED accents in DimSection.CourseName, which render as
 *          "FranÃ§ais 1Ã¨re" instead of "Français 1ère".
 *
 *          The defect, from the stored bytes:
 *              stored  c3 83 c2 a9  = UTF-8 of "Ã©"
 *              correct c3 a9        = UTF-8 of "é"
 *          i.e. the source UTF-8 bytes were decoded as Latin-1 into "Ã©" and then
 *          re-encoded as UTF-8 — ONE round of double-encoding. The fix is one
 *          decode round: collapse each 2-char sequence back to its real character.
 *
 *          NOT a column-type problem: CourseName is VARCHAR(200) and Fabric's
 *          VARCHAR is UTF-8 collated (Latin1_General_100_BIN2_UTF8), so it stores
 *          "é" correctly in 2 bytes. The bytes arrived already broken, so the real
 *          fix is at whatever WRITES the column — this only repairs what is stored.
 *
 * SCD Type: N/A — DimSection is SCD Type 2, but CourseName is display metadata, so
 *          this corrects every version in place rather than opening new ones. A
 *          re-version here would imply the section changed, which it did not.
 * Created: 2026-09-18
 * Region:  Canada East (PIIDPA compliant)
 *
 * SAFE TO RE-RUN: the guard only matches rows that still contain the marker, and a
 * correctly-encoded name contains no bare "Ã".
 *
 * BEFORE running against LIVE, check whether live is even affected (query at the
 * bottom) — live names come through the PS CSV ingest, a different path than the
 * hand-seeded dev rows, so it may be clean.
 ******************************************************************************/

-- Before.
SELECT 'BEFORE' AS Phase, CourseCode, CourseName, LEN(CourseName) AS StoredLen
FROM DimSection
WHERE CourseName LIKE '%Ã%' OR CourseName LIKE '%Â%';

-- One decode round. Ordering matters only in that the two-char sequences are
-- distinct, so a single nested pass is enough. 'Â' + x is the other half of the same
-- defect (it precedes characters in the U+00A0-U+00BF range, e.g. a stray nbsp).
UPDATE DimSection
SET CourseName =
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        REPLACE(REPLACE(REPLACE(REPLACE(
            CourseName,
            'Ã©', 'é'), 'Ã¨', 'è'), 'Ã§', 'ç'), 'Ãª', 'ê'),
            'Ã«', 'ë'), 'Ã ', 'à'), 'Ã¢', 'â'), 'Ã´', 'ô'),
            'Ã®', 'î'), 'Ã¯', 'ï'), 'Ã¹', 'ù'), 'Ã»', 'û'),
            'Ã¼', 'ü'), 'Ã‰', 'É'), 'Ãˆ', 'È'), 'Ã‡', 'Ç'),
    LastUpdated = GETDATE()
WHERE CourseName LIKE '%Ã%';

-- After. StoredLen should now equal the visible character count, and no row should
-- still match the marker.
SELECT 'AFTER' AS Phase, CourseCode, CourseName, LEN(CourseName) AS StoredLen
FROM DimSection
WHERE CourseCode IN (
    SELECT CourseCode FROM DimSection WHERE CourseName LIKE '%[àâçèéêëîïôùûü]%'
);

SELECT 'REMAINING BROKEN' AS Phase, COUNT(*) AS Rows_
FROM DimSection WHERE CourseName LIKE '%Ã%' OR CourseName LIKE '%Â%';
