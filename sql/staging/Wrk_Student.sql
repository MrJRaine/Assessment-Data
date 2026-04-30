/*******************************************************************************
 * Table: Wrk_Student
 * Purpose: Typed working set for student merge. Populated by usp_MergeStudent
 *          from Stg_Student with all source-value translations applied:
 *            - Grade_Level '0'  -> 'P', '-1' -> 'PP', else verbatim
 *            - SchoolID zero-padded to 4 chars
 *            - DOB MM/DD/YYYY -> DATE
 *            - NS_AssigndIdentity_African: 'Yes' -> 1, '' -> NULL
 *            - NS_aboriginal: '1' -> 1, '2' -> 0, '' -> NULL
 *            - CurrentIPP / CurrentAdap: 'Y' -> 1, 'N' -> 0, '' -> NULL
 *            - Numerics cast to BIGINT / INT
 *
 *          Persisting the translated set as a real table (vs inline CTE)
 *          gives us a single, inspectable, NULL-safe payload that the SCD
 *          merge statements can JOIN against repeatedly without re-evaluating
 *          translations.
 *
 *          Column shape mirrors DimStudent business columns + StudentNumber +
 *          SourceSystemID. No SCD lifecycle columns here.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_Student (
    StudentNumber       BIGINT          NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,           -- PowerSchool DCID (carried for audit)
    FirstName           VARCHAR(100)    NOT NULL,
    MiddleName          VARCHAR(100)    NULL,
    LastName            VARCHAR(100)    NOT NULL,
    DateOfBirth         DATE            NULL,
    CurrentGrade        VARCHAR(10)     NOT NULL,
    CurrentSchoolID     VARCHAR(10)     NOT NULL,
    ProgramCode         VARCHAR(10)     NOT NULL,
    EnrollStatus        INT             NOT NULL,
    Homeroom            VARCHAR(50)     NULL,
    Gender              VARCHAR(10)     NOT NULL,
    SelfIDAfrican       BIT             NULL,
    SelfIDIndigenous    BIT             NULL,
    CurrentIPP          BIT             NULL,
    CurrentAdap         BIT             NULL
);
