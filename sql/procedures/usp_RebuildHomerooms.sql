/*******************************************************************************
 * Procedure: usp_RebuildHomerooms
 * Purpose: Work out, from the student data, which homerooms are split classes.
 *          Reads every school homeroom (grades P-9), lists the grades in it, and
 *          keeps that as dated history in DimHomeroom; adds any new grade
 *          combination to DimHomeroomComposition; and rebuilds DimHomeroomSection
 *          (the Math + Literacy sections that make up each homeroom).
 *          Split-grade math pacing (1.5.0) reads these to decide which month a task
 *          falls in for a class. Called from usp_RunFullIngestCycle after the roster
 *          rebuild, and runnable standalone.
 * SCD Type: maintains DimHomeroom as Type 2 on the grade combination
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  DimStudent (current rows), DimGrade, FactEnrollment, DimSection,
 *         DimCourseAssessment.
 * Writes: Wrk_Homeroom (TRUNCATE + INSERT), DimHomeroomComposition (INSERT new
 *         combinations only), DimHomeroom (Type 2 close / insert, in-place refresh),
 *         DimHomeroomSection (TRUNCATE + INSERT).
 *
 * RULES (user decisions 2026-11-19):
 *   - A homeroom is identified by (SchoolID, Homeroom) so two schools with the same
 *     homeroom name never mix.
 *   - Scope: ACTIVE students (EnrollStatus = 0), grades P-9, with a homeroom.
 *   - ONE student in another grade makes the homeroom a split. No minimum count.
 *   - SplitType: 'Straight' (one grade), 'AdjacentPair' (two neighbouring grades -
 *     the regional guide applies), 'TeacherPaced' (three or more grades, or two
 *     grades that are not neighbours - the teacher sets the pacing).
 *
 * The grade list is built with one CASE per grade (not an ordered STRING_AGG) so
 * the string is always in grade order: 'P,1', '2,3', '1,2,3'.
 *
 * SAME-DAY RULES (see the fabric-warehouse-sql skill): a version that started
 * today is corrected IN PLACE, never closed and re-inserted, so two versions of one
 * homeroom never share a day. Re-running on the same day is safe.
 *
 * No result set is returned (it runs inside the ingest cycle).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS dbo.usp_RebuildHomerooms;
GO

CREATE PROCEDURE dbo.usp_RebuildHomerooms
    @EffectiveDate DATE = NULL     -- defaults to today (Atlantic); the ingest cycle passes its own date
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2(0) = GETDATE();
    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    -- ------------------------------------------------------------------------
    -- 1) The homerooms as they stand now: one row per (SchoolID, Homeroom).
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.Wrk_Homeroom;

    INSERT INTO dbo.Wrk_Homeroom
        (SchoolID, Homeroom, GroupKey, CompositionGrades, GradeCount, SplitType, StudentCount)
    SELECT x.SchoolID, x.Homeroom, x.GroupKey,
           LEFT(x.GradeList, LEN(x.GradeList) - 1),            -- drop the trailing comma
           x.GradeCount,
           CASE WHEN x.GradeCount = 1 THEN 'Straight'
                WHEN x.GradeCount = 2 AND x.MaxOrder - x.MinOrder = 1 THEN 'AdjacentPair'
                ELSE 'TeacherPaced' END,
           x.StudentCount
    FROM (
        SELECT s.SchoolID, s.Homeroom,
               MAX(s.GroupKey)          AS GroupKey,
               COUNT(*)                 AS StudentCount,
               COUNT(DISTINCT s.Grade)  AS GradeCount,
               MIN(g.GradeOrder)        AS MinOrder,
               MAX(g.GradeOrder)        AS MaxOrder,
               CONCAT(
                   CASE WHEN MAX(CASE WHEN s.Grade = 'P' THEN 1 ELSE 0 END) = 1 THEN 'P,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '1' THEN 1 ELSE 0 END) = 1 THEN '1,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '2' THEN 1 ELSE 0 END) = 1 THEN '2,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '3' THEN 1 ELSE 0 END) = 1 THEN '3,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '4' THEN 1 ELSE 0 END) = 1 THEN '4,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '5' THEN 1 ELSE 0 END) = 1 THEN '5,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '6' THEN 1 ELSE 0 END) = 1 THEN '6,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '7' THEN 1 ELSE 0 END) = 1 THEN '7,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '8' THEN 1 ELSE 0 END) = 1 THEN '8,' ELSE '' END,
                   CASE WHEN MAX(CASE WHEN s.Grade = '9' THEN 1 ELSE 0 END) = 1 THEN '9,' ELSE '' END
               ) AS GradeList
        FROM DimStudent s
        INNER JOIN DimGrade g ON g.GradeCode = s.Grade
        WHERE s.IsCurrent = 1
          AND s.EnrollStatus = 0
          AND g.GradeOrder BETWEEN 0 AND 9          -- P (0) through grade 9
          AND s.Homeroom IS NOT NULL
          AND LTRIM(RTRIM(s.Homeroom)) <> ''
        GROUP BY s.SchoolID, s.Homeroom
    ) x;

    -- ------------------------------------------------------------------------
    -- 2) Catalog: add any grade combination not seen before.
    -- ------------------------------------------------------------------------
    INSERT INTO dbo.DimHomeroomComposition
        (CompositionGrades, GradeCount, SplitType, DisplayName, CreatedByStaffKey, LastUpdated)
    SELECT n.CompositionGrades, n.GradeCount, n.SplitType,
           CAST(NULL AS VARCHAR(100)), CAST(NULL AS BIGINT), @Now
    FROM (
        SELECT w.CompositionGrades, MAX(w.GradeCount) AS GradeCount, MAX(w.SplitType) AS SplitType
        FROM dbo.Wrk_Homeroom w
        GROUP BY w.CompositionGrades
    ) n
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DimHomeroomComposition c
                      WHERE c.CompositionGrades = n.CompositionGrades);

    -- ------------------------------------------------------------------------
    -- 3) DimHomeroom history.
    -- ------------------------------------------------------------------------

    -- 3a) REVIVE: a homeroom closed earlier TODAY as a same-day row that is back.
    UPDATE d
    SET d.IsCurrent        = 1,
        d.EffectiveEndDate = NULL,
        d.CompositionKey   = c.CompositionKey,
        d.StudentCount     = w.StudentCount,
        d.GroupKey         = w.GroupKey,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 0
      AND d.EffectiveStartDate = @EffectiveDate
      AND d.EffectiveEndDate   = @EffectiveDate
      AND NOT EXISTS (SELECT 1 FROM dbo.DimHomeroom cur
                      WHERE cur.SchoolID = d.SchoolID AND cur.Homeroom = d.Homeroom AND cur.IsCurrent = 1);

    -- 3b) SAME-DAY correction: the current version started today -> fix it in place.
    UPDATE d
    SET d.CompositionKey = c.CompositionKey,
        d.StudentCount   = w.StudentCount,
        d.GroupKey       = w.GroupKey,
        d.LastUpdated    = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate = @EffectiveDate
      AND (d.CompositionKey <> c.CompositionKey
           OR d.StudentCount <> w.StudentCount
           OR COALESCE(d.GroupKey, '') <> COALESCE(w.GroupKey, ''));

    -- 3c) UNCHANGED grade combination: refresh the head count / group key in place.
    UPDATE d
    SET d.StudentCount = w.StudentCount,
        d.GroupKey     = w.GroupKey,
        d.LastUpdated  = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND d.CompositionKey = c.CompositionKey
      AND (d.StudentCount <> w.StudentCount
           OR COALESCE(d.GroupKey, '') <> COALESCE(w.GroupKey, ''));

    -- 3d) CHANGED grade combination (version started on an earlier day): close it.
    --     Step 3f inserts the replacement.
    UPDATE d
    SET d.EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        d.IsCurrent        = 0,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    INNER JOIN dbo.Wrk_Homeroom w ON w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
      AND d.CompositionKey <> c.CompositionKey;

    -- 3e) GONE: a current homeroom with no active students any more -> close only.
    --     End date is guarded so a row created today closes as a valid 0-day window.
    UPDATE d
    SET d.EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                  THEN d.EffectiveStartDate
                                  ELSE DATEADD(DAY, -1, @EffectiveDate) END,
        d.IsCurrent        = 0,
        d.LastUpdated      = @Now
    FROM dbo.DimHomeroom d
    WHERE d.IsCurrent = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Wrk_Homeroom w
                      WHERE w.SchoolID = d.SchoolID AND w.Homeroom = d.Homeroom);

    -- 3f) NEW version: every homeroom that now has no current row (brand new, or
    --     closed in 3d).
    INSERT INTO dbo.DimHomeroom
        (SchoolID, Homeroom, GroupKey, CompositionKey, StudentCount,
         EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
    SELECT w.SchoolID, w.Homeroom, w.GroupKey, c.CompositionKey, w.StudentCount,
           @EffectiveDate, CAST(NULL AS DATE), 1, @Now
    FROM dbo.Wrk_Homeroom w
    INNER JOIN dbo.DimHomeroomComposition c ON c.CompositionGrades = w.CompositionGrades
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DimHomeroom d
                      WHERE d.SchoolID = w.SchoolID AND d.Homeroom = w.Homeroom AND d.IsCurrent = 1);

    -- ------------------------------------------------------------------------
    -- 4) The sections that make up each homeroom (current picture).
    --    Enrolment is matched by the STABLE SectionID / StudentNumber (the same
    --    approach as usp_RebuildRosterMembership), so a re-versioned section or
    --    student does not drop out.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE dbo.DimHomeroomSection;

    INSERT INTO dbo.DimHomeroomSection
        (SchoolID, Homeroom, SectionID, Kind, Language, CourseCode, CourseName, StudentCount, LastRebuiltAt)
    SELECT cur.SchoolID, cur.Homeroom, sec.SectionID, ca.Kind, ca.Language,
           sec.CourseCode, sec.CourseName,
           COUNT(DISTINCT cur.StudentNumber),
           @Now
    FROM FactEnrollment e
    INNER JOIN DimSection esec ON esec.SectionKey = e.SectionKey
    INNER JOIN DimSection sec  ON sec.SectionID = esec.SectionID AND sec.IsCurrent = 1
    INNER JOIN DimCourseAssessment ca ON ca.CourseCode = sec.CourseCode AND ca.ActiveFlag = 1
    INNER JOIN DimStudent ds   ON ds.StudentKey = e.StudentKey
    INNER JOIN DimStudent cur  ON cur.StudentNumber = ds.StudentNumber AND cur.IsCurrent = 1
    INNER JOIN DimGrade g      ON g.GradeCode = cur.Grade
    WHERE e.ActiveFlag = 1
      AND cur.EnrollStatus = 0
      AND g.GradeOrder BETWEEN 0 AND 9
      AND cur.Homeroom IS NOT NULL
      AND LTRIM(RTRIM(cur.Homeroom)) <> ''
    GROUP BY cur.SchoolID, cur.Homeroom, sec.SectionID, ca.Kind, ca.Language,
             sec.CourseCode, sec.CourseName;
END;
GO
