/*******************************************************************************
 * Staging: Stg_PriorReading + Stg_PriorWriting
 * Purpose: All-VARCHAR landing tables for the prior-year baseline CSVs (converted
 *          from the ELA/FLA Reading & Writing workbooks). Columns are in the CSV
 *          column order so COPY INTO maps positionally. AssessmentLanguage is the last
 *          column, left out of COPY INTO and set by an UPDATE after each program's
 *          file loads (the file has no program column — it's implied by the sheet).
 * Created: 2026-09-09
 * Region:  Canada East (PIIDPA compliant)
 *
 * Load-as-text: everything VARCHAR; validation/typing happens in the merge
 * (load_prior_year_baseline.sql). See PriorYearBaseline.sql for the target.
 ******************************************************************************/

DROP TABLE IF EXISTS Stg_PriorReading;
GO
-- CSV order: Student Number, Name, School, HomeRoom, Literacy IPP, Grade, Gender,
--            Self-ID African, Self-ID Indigenous, Current IPP, Current Adaptations,
--            Instructional Reading Level
CREATE TABLE Stg_PriorReading (
    StudentNumber       VARCHAR(20)  NULL,
    StudentName         VARCHAR(120) NULL,   -- PII; not carried into PriorYearBaseline
    School              VARCHAR(100) NULL,
    Homeroom            VARCHAR(50)  NULL,
    LiteracyIPP         VARCHAR(10)  NULL,
    Grade               VARCHAR(4)   NULL,
    Gender              VARCHAR(4)   NULL,
    SelfIDAfrican       VARCHAR(10)  NULL,
    SelfIDIndigenous    VARCHAR(10)  NULL,
    CurrentIPP          VARCHAR(10)  NULL,
    CurrentAdaptations  VARCHAR(10)  NULL,
    ReadingLevel        VARCHAR(10)  NULL,
    AssessmentLanguage       VARCHAR(20)  NULL    -- set by UPDATE after each COPY INTO
);
GO

DROP TABLE IF EXISTS Stg_PriorWriting;
GO
-- CSV order: Student Number, Name, School, HomeRoom, Grade, Gender, Self-ID African,
--            Self-ID Indigenous, Current IPP, Current Adaptations, Literacy IPP,
--            Conventions, Organization, Ideas, Language Use
CREATE TABLE Stg_PriorWriting (
    StudentNumber       VARCHAR(20)  NULL,
    StudentName         VARCHAR(120) NULL,   -- PII; not carried into PriorYearBaseline
    School              VARCHAR(100) NULL,
    Homeroom            VARCHAR(50)  NULL,
    Grade               VARCHAR(4)   NULL,
    Gender              VARCHAR(4)   NULL,
    SelfIDAfrican       VARCHAR(10)  NULL,
    SelfIDIndigenous    VARCHAR(10)  NULL,
    CurrentIPP          VARCHAR(10)  NULL,
    CurrentAdaptations  VARCHAR(10)  NULL,
    LiteracyIPP         VARCHAR(10)  NULL,
    Conventions         VARCHAR(10)  NULL,
    Organization        VARCHAR(10)  NULL,
    Ideas               VARCHAR(10)  NULL,
    LanguageUse         VARCHAR(10)  NULL,
    AssessmentLanguage       VARCHAR(20)  NULL    -- set by UPDATE after each COPY INTO
);
GO
