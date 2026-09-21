/*******************************************************************************
 * Table: DimCourseAssessment
 * Purpose: Maps a PowerSchool course code (DimSection.CourseCode) to the
 *          assessment it lets a teacher enter -- the LANGUAGE and KIND. Drives
 *          course-scoped entry: a teacher only enters for sections whose course is
 *          in this table, and the course supplies the language (so no EN/FR toggle).
 *
 *          Data-driven on PURPOSE: add/remove a course = insert/delete a row here,
 *          never a code change. Seed the real course list on live
 *          (seed_DimCourseAssessment_live.sql) and the synthetic dev codes on dev
 *          (seed_DimCourseAssessment_dev.sql); the app/TVF logic is identical.
 *
 *   Kind = 'Literacy' -> the course teacher enters BOTH Reading and Writing in
 *          Language ('English' | 'French'). A Language-Arts course covers both.
 *   Kind = 'Math'     -> Math (Language NULL; Math is single-track P-6).
 * SCD Type: N/A (reference/config; managed manually)
 * Created: 2026-09-17
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimCourseAssessment (
    CourseCode    VARCHAR(50)   NOT NULL,   -- matches DimSection.CourseCode
    Language      VARCHAR(10)   NULL,       -- 'English' | 'French' | NULL (Math)
    Kind          VARCHAR(20)   NOT NULL,   -- 'Literacy' (Reading+Writing) | 'Math'
    ActiveFlag    BIT           NOT NULL,
    Notes         VARCHAR(200)  NULL,       -- e.g. bucket name ('ELA P-12', 'FLA', 'Immersion ELA 3-6', 'Math P-6')
    LastUpdated   DATETIME2(0)  NOT NULL
);
