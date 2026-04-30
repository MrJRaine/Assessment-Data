/*******************************************************************************
 * Table: Stg_Student
 * Purpose: Landing zone for raw PowerSchool Students export. All columns are
 *          VARCHAR — load-as-text, then validate/translate downstream in
 *          usp_MergeStudent. This is the COPY INTO target.
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Column order MUST match the PowerSchool Students export header exactly:
 *   Student_Number, ID, First_Name, Middle_Name, Last_Name, SchoolID,
 *   Grade_Level, NS_Program, Home_Room, Gender, DOB,
 *   NS_AssigndIdentity_African, NS_aboriginal, CurrentIPP, CurrentAdap,
 *   Enroll_Status
 *
 * Field-name spelling note: NS_AssigndIdentity_African contains the literal
 * extra 'd' between 'Assign' and 'Identity' — that is the actual PS column
 * name, do not "correct" it.
 ******************************************************************************/

CREATE TABLE Stg_Student (
    Student_Number              VARCHAR(50)     NULL,   -- Provincial 10-digit student number
    ID                          VARCHAR(50)     NULL,   -- PowerSchool DCID (preserved as SourceSystemID, not used for matching)
    First_Name                  VARCHAR(100)    NULL,
    Middle_Name                 VARCHAR(100)    NULL,
    Last_Name                   VARCHAR(100)    NULL,
    SchoolID                    VARCHAR(10)     NULL,   -- 4-digit provincial school number; PS may strip leading zeros — pad in merge
    Grade_Level                 VARCHAR(10)     NULL,   -- PS emits '0' for Primary, '-1' for Pre-Primary; merge translates to 'P'/'PP'
    NS_Program                  VARCHAR(10)     NULL,   -- e.g. 'E015', 'S115'
    Home_Room                   VARCHAR(50)     NULL,
    Gender                      VARCHAR(10)     NULL,   -- M, F, X
    DOB                         VARCHAR(20)     NULL,   -- MM/DD/YYYY format from PS
    NS_AssigndIdentity_African  VARCHAR(10)     NULL,   -- 'Yes' or empty (no 'No' observed)
    NS_aboriginal               VARCHAR(10)     NULL,   -- '1', '2', or empty
    CurrentIPP                  VARCHAR(10)     NULL,   -- 'Y', 'N', or empty
    CurrentAdap                 VARCHAR(10)     NULL,   -- 'Y', 'N', or empty
    Enroll_Status               VARCHAR(10)     NULL    -- 0=Active, 2=Inactive, 3=Graduated, -1=Pre-Enrolled
);
