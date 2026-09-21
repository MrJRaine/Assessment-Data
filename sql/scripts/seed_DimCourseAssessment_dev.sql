/*******************************************************************************
 * Script: seed_DimCourseAssessment_dev.sql
 * Purpose: DEV-ONLY seed of DimCourseAssessment using the SYNTHETIC course codes
 *          that dev's DimSection actually carries (dev has no real PS codes and no
 *          English-LA sections). Lets course-scoped entry be exercised on dev for
 *          French literacy + Math; the English side is verified on live once the
 *          real list (seed_DimCourseAssessment_live.sql) is seeded there.
 *          Mapped dev codes (literacy/math only; homeroom/history/science excluded):
 *            FRA-1-FI, LET-K-FI, LIT-12-FI  -> French literacy
 *            MTH-1-FI, MTH-K-FI, MTH-10-FI  -> Math (MTH-10-FI out of P-6 range; harmless)
 * Idempotent: clears then re-seeds. Run on DEV only.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DELETE FROM DimCourseAssessment;

INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES
    ('FRA-1-FI',  'French', 'Literacy', 1, 'dev synthetic (FLA)',  GETDATE()),
    ('LET-K-FI',  'French', 'Literacy', 1, 'dev synthetic (FLA)',  GETDATE()),
    ('LIT-12-FI', 'French', 'Literacy', 1, 'dev synthetic (FLA)',  GETDATE()),
    ('MTH-K-FI',  NULL,     'Math',     1, 'dev synthetic (Math)', GETDATE()),
    ('MTH-1-FI',  NULL,     'Math',     1, 'dev synthetic (Math)', GETDATE()),
    ('MTH-10-FI', NULL,     'Math',     1, 'dev synthetic (Math)', GETDATE());

SELECT Language, Kind, COUNT(*) AS Courses FROM DimCourseAssessment GROUP BY Language, Kind ORDER BY Kind, Language;
