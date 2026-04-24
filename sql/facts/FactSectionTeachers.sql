/*******************************************************************************
 * Table: FactSectionTeachers
 * Purpose: Many-to-many bridge of teacher-to-section assignments, supporting
 *          co-teaching and secondary teacher arrangements.
 * SCD Type: N/A (temporal bridge — uses EffectiveStartDate/EndDate/IsCurrent)
 * Created: 2026-04-23
 * Modified: 2026-04-23 - Initial creation
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Contains EVERY teacher-section assignment, including primary teachers AND co-teachers.
-- This is the authoritative source for section-level RLS — vw_TeacherStudents joins
-- through this table rather than DimSection.TeacherStaffKey.
--
-- DimSection.TeacherStaffKey is kept as a denormalization of "primary teacher of record"
-- for convenient reporting, but should NOT be used for access control.
--
-- Rebuild rules on staff/section ingest:
--   - Expire current rows where the assignment no longer appears in the export
--   - Insert new rows for new assignments
--   - Primary teacher (from PowerSchool teacher-of-record field) gets TeacherRole = 'Primary'
--   - Additional teachers (co-teaching arrangements) get their respective TeacherRole values

CREATE TABLE FactSectionTeachers (
    SectionTeacherID    BIGINT          NOT NULL IDENTITY,
    SectionKey          BIGINT          NOT NULL,   -- References DimSection.SectionKey
    StaffKey            BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    TeacherRole         VARCHAR(50)     NOT NULL,   -- 'Primary', 'CoTeacher', 'Support', 'Substitute'
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current assignment
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool assignment ID if available
    LastUpdated         DATETIME2(0)    NOT NULL
);
