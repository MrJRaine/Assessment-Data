/*******************************************************************************
 * Script: load_prior_year_baseline.sql
 * Purpose: One-time (re-runnable) load of the 2025-2026 June reading + writing
 *          baseline from the four ELA/FLA CSVs into PriorYearBaseline.
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * PREREQUISITES:
 *   1. Run PriorYearBaseline.sql and Stg_PriorYearBaseline.sql first.
 *   2. Convert the four workbooks to CSV (scratchpad\xlsx_to_csv.ps1) and upload
 *      to OneLake  Files/imports/prior-year-baseline/  :
 *        reading-ela.csv  reading-fla.csv  writing-ela.csv  writing-fla.csv
 *   3. The abfss paths below use the LIVE workspace/lakehouse GUIDs (same as the
 *      usp_Load*Staging loaders). For a DEV test, swap the lakehouse GUID to the
 *      _Dev lakehouse (as the dev loaders do).
 *
 * The CSVs are comma-delimited, double-quote qualified, CRLF, header on row 1.
 * AssessmentLanguage is not in the files (implied by the sheet) — set by UPDATE after
 * each program's COPY INTO. Idempotent: TRUNCATEs staging + target each run.
 ******************************************************************************/

-- ==== READING: load both programs into Stg_PriorReading, tag AssessmentLanguage ====
TRUNCATE TABLE Stg_PriorReading;
GO

COPY INTO Stg_PriorReading
    (StudentNumber, StudentName, School, Homeroom, LiteracyIPP, Grade, Gender,
     SelfIDAfrican, SelfIDIndigenous, CurrentIPP, CurrentAdaptations, ReadingLevel)
FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/prior-year-baseline/reading-ela.csv'
WITH (FILE_TYPE = 'CSV', FIELDTERMINATOR = ',', FIELDQUOTE = '"', FIRSTROW = 2);
GO
UPDATE Stg_PriorReading SET AssessmentLanguage = 'English' WHERE AssessmentLanguage IS NULL;
GO

COPY INTO Stg_PriorReading
    (StudentNumber, StudentName, School, Homeroom, LiteracyIPP, Grade, Gender,
     SelfIDAfrican, SelfIDIndigenous, CurrentIPP, CurrentAdaptations, ReadingLevel)
FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/prior-year-baseline/reading-fla.csv'
WITH (FILE_TYPE = 'CSV', FIELDTERMINATOR = ',', FIELDQUOTE = '"', FIRSTROW = 2);
GO
UPDATE Stg_PriorReading SET AssessmentLanguage = 'French' WHERE AssessmentLanguage IS NULL;
GO

-- ==== WRITING: load both programs into Stg_PriorWriting, tag AssessmentLanguage =====
TRUNCATE TABLE Stg_PriorWriting;
GO

COPY INTO Stg_PriorWriting
    (StudentNumber, StudentName, School, Homeroom, Grade, Gender, SelfIDAfrican,
     SelfIDIndigenous, CurrentIPP, CurrentAdaptations, LiteracyIPP,
     Conventions, Organization, Ideas, LanguageUse)
FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/prior-year-baseline/writing-ela.csv'
WITH (FILE_TYPE = 'CSV', FIELDTERMINATOR = ',', FIELDQUOTE = '"', FIRSTROW = 2);
GO
UPDATE Stg_PriorWriting SET AssessmentLanguage = 'English' WHERE AssessmentLanguage IS NULL;
GO

COPY INTO Stg_PriorWriting
    (StudentNumber, StudentName, School, Homeroom, Grade, Gender, SelfIDAfrican,
     SelfIDIndigenous, CurrentIPP, CurrentAdaptations, LiteracyIPP,
     Conventions, Organization, Ideas, LanguageUse)
FROM 'abfss://a1b49041-0855-46de-8aca-86762132eefb@onelake.dfs.fabric.microsoft.com/b3819971-8ef8-448b-b0b3-58a6fc7985ef/Files/imports/prior-year-baseline/writing-fla.csv'
WITH (FILE_TYPE = 'CSV', FIELDTERMINATOR = ',', FIELDQUOTE = '"', FIRSTROW = 2);
GO
UPDATE Stg_PriorWriting SET AssessmentLanguage = 'French' WHERE AssessmentLanguage IS NULL;
GO

-- ==== MERGE: one wide row per (StudentNumber, AssessmentLanguage) ===================
TRUNCATE TABLE PriorYearBaseline;
GO

WITH Rd AS (
    SELECT AssessmentLanguage,
           TRY_CAST(StudentNumber AS BIGINT) AS StudentNumber,
           School, Homeroom, Grade, Gender, SelfIDAfrican, SelfIDIndigenous,
           CurrentIPP, CurrentAdaptations, LiteracyIPP, ReadingLevel
    FROM Stg_PriorReading
    WHERE TRY_CAST(StudentNumber AS BIGINT) IS NOT NULL
),
Wr AS (
    SELECT AssessmentLanguage,
           TRY_CAST(StudentNumber AS BIGINT) AS StudentNumber,
           School, Homeroom, Grade, Gender, SelfIDAfrican, SelfIDIndigenous,
           CurrentIPP, CurrentAdaptations, LiteracyIPP,
           Conventions, Organization, Ideas, LanguageUse
    FROM Stg_PriorWriting
    WHERE TRY_CAST(StudentNumber AS BIGINT) IS NOT NULL
)
INSERT INTO PriorYearBaseline (
    StudentNumber, SchoolYear, AssessmentLanguage,
    HistGrade, HistHomeroom, HistSchool, HistGender,
    HistSelfIDAfrican, HistSelfIDIndigenous,
    HistCurrentIPP, HistCurrentAdaptations, HistLiteracyIPP,
    ReadingLevel, WritingConventions, WritingOrganization, WritingIdeas, WritingLanguage,
    LastUpdated
)
SELECT
    COALESCE(r.StudentNumber, w.StudentNumber),
    '2025-2026',
    COALESCE(r.AssessmentLanguage, w.AssessmentLanguage),
    COALESCE(r.Grade, w.Grade),
    COALESCE(r.Homeroom, w.Homeroom),
    COALESCE(r.School, w.School),
    COALESCE(r.Gender, w.Gender),
    COALESCE(r.SelfIDAfrican, w.SelfIDAfrican),
    COALESCE(r.SelfIDIndigenous, w.SelfIDIndigenous),
    COALESCE(r.CurrentIPP, w.CurrentIPP),
    COALESCE(r.CurrentAdaptations, w.CurrentAdaptations),
    COALESCE(r.LiteracyIPP, w.LiteracyIPP),
    r.ReadingLevel,
    w.Conventions, w.Organization, w.Ideas, w.LanguageUse,
    GETDATE()
FROM Rd r
FULL OUTER JOIN Wr w
    ON  w.StudentNumber = r.StudentNumber
    AND w.AssessmentLanguage = r.AssessmentLanguage;
GO

-- ==== VERIFY (counts only — PII-safe) =========================================
-- Loaded totals + how many baseline students match a CURRENT DimStudent.
-- Non-matching = students not currently enrolled (graduated / moved) — EXPECTED,
-- they simply won't surface on any current roster.
-- (scalar subqueries — Fabric rejects an aggregate over a subquery)
SELECT
    (SELECT COUNT(*) FROM Stg_PriorReading)                                        AS StgReadingRows,
    (SELECT COUNT(*) FROM Stg_PriorWriting)                                        AS StgWritingRows,
    (SELECT COUNT(*) FROM PriorYearBaseline)                                       AS BaselineRows,
    (SELECT COUNT(*) FROM PriorYearBaseline WHERE ReadingLevel IS NOT NULL)        AS WithReading,
    (SELECT COUNT(*) FROM PriorYearBaseline WHERE WritingIdeas IS NOT NULL)        AS WithWriting,
    (SELECT COUNT(*) FROM PriorYearBaseline b
       WHERE EXISTS (SELECT 1 FROM DimStudent d
                     WHERE d.StudentNumber = b.StudentNumber AND d.IsCurrent = 1)) AS MatchesCurrentStudent,
    (SELECT COUNT(DISTINCT StudentNumber) FROM PriorYearBaseline)                   AS DistinctStudents,
    -- students with BOTH an English and a French row (immersion, assessed both languages)
    (SELECT COUNT(*) FROM (SELECT StudentNumber FROM PriorYearBaseline
                           GROUP BY StudentNumber HAVING COUNT(*) > 1) x)           AS StudentsWithBothLanguages;
