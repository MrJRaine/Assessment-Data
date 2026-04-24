/*******************************************************************************
 * Table: DimAssessmentWindow
 * Purpose: Defines when assessments are collected, for which grades and programs
 * SCD Type: N/A (managed manually; rows are inserted per pull, not updated)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE DimAssessmentWindow (
    AssessmentWindowID  BIGINT          NOT NULL IDENTITY,
    WindowName          VARCHAR(100)   NOT NULL,   -- e.g. 'June 2025 Reading - French Immersion Pilot'
    AssessmentType      VARCHAR(20)    NOT NULL,   -- 'Reading' or 'Writing'
    SchoolYear          VARCHAR(9)     NOT NULL,   -- e.g. '2024-2025'
    StartDate           DATE            NOT NULL,
    EndDate             DATE            NOT NULL,
    AppliesTo           VARCHAR(50)    NULL,        -- e.g. 'Primary', 'Elementary', 'All'
    MinGrade            VARCHAR(10)    NULL,        -- e.g. 'P', '1', '7'
    MaxGrade            VARCHAR(10)    NULL,        -- e.g. '6', '12'
    ProgramCode         VARCHAR(10)    NULL,        -- 'FR', 'EN', or NULL for all programs
    ActiveFlag          BIT             NOT NULL,
    IsCurrentWindow     BIT             NOT NULL,
    CreatedDate         DATETIME2(0)        NOT NULL,
    CreatedBy           VARCHAR(100)   NULL
);
