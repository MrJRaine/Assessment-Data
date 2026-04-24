/*******************************************************************************
 * Table: FactEnrollment
 * Purpose: Student membership in sections over time
 * SCD Type: N/A (fact table — rows added/expired, not versioned)
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Students typically have 6-10 concurrent enrollments per school year.
-- ActiveFlag = 1 for current enrollments; EndDate = NULL if still enrolled.

CREATE TABLE FactEnrollment (
    EnrollmentID    BIGINT  NOT NULL IDENTITY,
    StudentKey      BIGINT  NOT NULL,   -- References DimStudent.StudentKey
    SectionKey      BIGINT  NOT NULL,   -- References DimSection.SectionKey
    StartDate       DATE    NOT NULL,
    EndDate         DATE    NULL,       -- NULL = currently enrolled
    ActiveFlag      BIT     NOT NULL
);
