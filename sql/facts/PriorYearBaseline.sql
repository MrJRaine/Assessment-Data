/*******************************************************************************
 * Table: PriorYearBaseline
 * Purpose: DENORMALIZED prior-year (2025-2026) end-of-June reading + writing
 *          baseline, so teachers can see where their new students started. One
 *          wide row per student, keyed by provincial StudentNumber (stable
 *          across years); the display read joins it to the CURRENT roster by
 *          StudentNumber. This is the lightweight "option B" — NOT integrated
 *          into the star schema (no historical DimStudent versions / facts);
 *          full historical integration ("option A") is deferred.
 * SCD Type: N/A (static one-time backfill, refreshed by re-running the load).
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * Historical demographic columns are AS OF last June (grade/homeroom/school can
 * all differ from the current PowerSchool values). AssessmentLanguage is the
 * LANGUAGE of the assessment (ELA sheet -> 'English', FLA sheet -> 'French'), NOT
 * the student's program; it fixes the reading scale (EN A-Z vs FR 1-30). A French
 * Immersion student assessed in BOTH languages appears in the ELA AND FLA sheets
 * and correctly gets TWO baseline rows (one per language) — the grain is
 * (StudentNumber, AssessmentLanguage), so the two never collide.
 *
 * Scores are VARCHAR, not numeric: a trait/level may carry a NON-NUMERIC code —
 * historical ABS (Absent) / INS (Insufficient evidence) / EAL (English as an
 * Additional Language Learner), or the go-forward SCR (Scribed). Any average/
 * band computed later must skip codes (sum/count over numeric values only).
 * See memory project_writing_scribed_score_code.
 ******************************************************************************/

DROP TABLE IF EXISTS PriorYearBaseline;
GO

CREATE TABLE PriorYearBaseline (
    StudentNumber           BIGINT       NOT NULL,   -- join key to current DimStudent.StudentNumber
    SchoolYear              VARCHAR(9)   NOT NULL,    -- '2025-2026'
    AssessmentLanguage      VARCHAR(10)  NOT NULL,    -- 'English' (ELA) / 'French' (FLA) — language of assessment, NOT program
    -- historical demographic context (as recorded last June) --------------------
    HistGrade               VARCHAR(2)   NULL,
    HistHomeroom            VARCHAR(50)  NULL,
    HistSchool              VARCHAR(100) NULL,         -- stored as school NAME (context only)
    HistGender              VARCHAR(3)   NULL,
    HistSelfIDAfrican       VARCHAR(10)  NULL,
    HistSelfIDIndigenous    VARCHAR(10)  NULL,
    HistCurrentIPP          VARCHAR(3)   NULL,
    HistCurrentAdaptations  VARCHAR(3)   NULL,
    HistLiteracyIPP         VARCHAR(3)   NULL,
    -- June assessment values (VARCHAR — may hold a numeric OR a code) -----------
    ReadingLevel            VARCHAR(10)  NULL,         -- EN A-Z / FR 1-30, or ABS/INS/EAL
    WritingConventions      VARCHAR(10)  NULL,         -- '1'-'4' or a code
    WritingOrganization     VARCHAR(10)  NULL,
    WritingIdeas            VARCHAR(10)  NULL,
    WritingLanguage         VARCHAR(10)  NULL,         -- sheet "Language Use"
    LastUpdated             DATETIME2(0) NOT NULL
);
GO

GRANT SELECT ON [dbo].[PriorYearBaseline] TO [StudentDataAssessment];
GO
