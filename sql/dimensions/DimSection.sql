/*******************************************************************************
 * Table: DimSection
 * Purpose: Instructional sections and their teacher-of-record assignments over time
 * SCD Type: 2
 * Created: 2026-04-22
 * Modified: 2026-04-22 - Initial creation
 *            2026-04-24 - Added TermID (PS 4-digit term value). Joins to DimTerm
 *                         to decode school year and Year Long / S1 / S2.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Type 2 attributes (trigger a new version): TeacherStaffKey
-- Type 1 attributes (update in place): CourseCode, SchoolID, TermID
-- TeacherStaffKey references DimStaff surrogate key — not the business key
-- TermID is effectively immutable per section (PS sections are year/term-specific),
-- so while it's classified Type 1 it should not actually change for a given SectionID.

CREATE TABLE DimSection (
    SectionKey          BIGINT          NOT NULL IDENTITY,  -- Surrogate key, unique per version
    SectionID           VARCHAR(50)     NOT NULL,           -- Business key, same across all versions
    SchoolID            VARCHAR(10)     NOT NULL,           -- 4-digit provincial school number
    TermID              INT             NOT NULL,           -- PS TermID (e.g. 3501); joins to DimTerm
    CourseCode          VARCHAR(50)     NULL,
    TeacherStaffKey     BIGINT          NOT NULL,           -- References DimStaff.StaffKey; triggers new version
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,               -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,               -- PowerSchool section ID
    LastUpdated         DATETIME2(0)    NOT NULL
);
