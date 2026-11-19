/*******************************************************************************
 * Table: DimHomeroomComposition
 * Purpose: Catalog of homeroom GRADE COMBINATIONS (e.g. '2', '2,3', '1,2,3', '1,3').
 *          A split class is identified by its HOMEROOM's grade set - PowerSchool has
 *          no split flag, and each math section is a single grade. Split-grade math
 *          pacing (1.5.0) keys the regional pacing guide on CompositionKey.
 * SCD Type: N/A (catalog; rows are only ever added)
 * Created: 2026-11-19 (1.5.0)
 * Region: Canada East (PIIDPA compliant)
 *
 * CompositionGrades is the canonical string: the distinct grades in GRADE ORDER
 * (P first), comma-separated, no spaces. It is matched WHOLE - never parsed.
 * SplitType: 'Straight'     - one grade
 *            'AdjacentPair' - two grades next to each other (the regional guide applies)
 *            'TeacherPaced' - three or more grades, or two grades that are not adjacent
 *                             (no regional guide exists; the teacher sets the pacing)
 * Written by usp_RebuildHomerooms (CreatedByStaffKey NULL = discovered on ingest).
 ******************************************************************************/

IF OBJECT_ID('dbo.DimHomeroomComposition', 'U') IS NULL
    CREATE TABLE DimHomeroomComposition (
        CompositionKey      BIGINT          NOT NULL IDENTITY,  -- Surrogate key
        CompositionGrades   VARCHAR(50)     NOT NULL,           -- canonical grade list, e.g. 'P,1' / '1,3'; unique by convention
        GradeCount          INT             NOT NULL,           -- number of grades in the combination
        SplitType           VARCHAR(20)     NOT NULL,           -- 'Straight' | 'AdjacentPair' | 'TeacherPaced'
        DisplayName         VARCHAR(100)    NULL,               -- optional friendly label
        CreatedByStaffKey   BIGINT          NULL,               -- NULL = discovered by ingest; set = authored in the app
        LastUpdated         DATETIME2(0)    NOT NULL
    );
GO
