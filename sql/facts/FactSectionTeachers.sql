/*******************************************************************************
 * Table: FactSectionTeachers
 * Purpose: Many-to-many bridge of teacher-to-section assignments, supporting
 *          co-teaching and secondary teacher arrangements.
 * SCD Type: N/A (temporal bridge — uses EffectiveStartDate/EndDate/IsCurrent)
 * Created: 2026-04-23
 * Modified: 2026-04-23 - Initial creation
 *            2026-04-28 - Decoupled from DimSection and DimStaff versioning.
 *                       Replaced SectionKey -> SectionID (business key) and
 *                       StaffKey -> TeacherEmail (business key). DimSection
 *                       Type 2 versions no longer cascade here; FactSectionTeachers
 *                       reconciles independently by (SectionID, TeacherEmail,
 *                       TeacherRole) triple. Rationale: with the all-Type-2
 *                       policy on DimSection, EnrollmentCount and other fields
 *                       version DimSection frequently — cascading would churn
 *                       this table for changes that have nothing to do with
 *                       teacher assignments. Email-keyed reconciliation also
 *                       simplifies RLS (vw_TeacherStudents matches email
 *                       directly, no DimStaff join required for access checks).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Contains EVERY teacher-section assignment, including primary teachers AND co-teachers.
-- This is the authoritative source for section-level RLS — vw_TeacherStudents matches
-- TeacherEmail directly against USERPRINCIPALNAME().
--
-- DimSection.TeacherStaffKey is kept as a denormalization of "primary teacher of record"
-- for convenient reporting, but should NOT be used for access control.
--
-- Foreign-style references (no enforced constraints in Fabric):
--   * SectionID  -> DimSection.SectionID   (business key, stable across DimSection versions)
--   * TeacherEmail -> DimStaff.Email      (business key, stable across DimStaff versions)
-- Queries needing current dim attributes join on (SectionID + IsCurrent=1) /
-- (Email + IsCurrent=1).
--
-- Rebuild rules on staff/section ingest (independent of DimSection / DimStaff merges):
--   Pass 1 — for each (SectionID, TeacherEmail, TeacherRole) row from staging:
--     * Match found, IsCurrent=1               -> no-op (touch LastUpdated)
--     * No match (new triple)                  -> INSERT with EffectiveStartDate
--                                                 = import date, IsCurrent=1
--   Pass 2 — anti-join: triples currently IsCurrent=1 but absent from staging:
--     * UPDATE EffectiveEndDate = import date - 1, IsCurrent = 0
--   Rows are never deleted.
--
-- Primary teacher (from PowerSchool teacher-of-record field) gets TeacherRole = 'Primary'.
-- Additional teachers (co-teaching arrangements) get their respective TeacherRole values.

CREATE TABLE FactSectionTeachers (
    SectionTeacherID    BIGINT          NOT NULL IDENTITY,
    SectionID           VARCHAR(50)     NOT NULL,   -- DimSection business key (NOT the surrogate)
    TeacherEmail        VARCHAR(255)    NOT NULL,   -- DimStaff business key (lowercased); also the SCD trigger field
    TeacherRole         VARCHAR(50)     NOT NULL,   -- 'Primary', 'CoTeacher', 'Support', 'Substitute'
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current assignment
    IsCurrent           BIT             NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL,        -- PowerSchool assignment ID if available
    LastUpdated         DATETIME2(0)    NOT NULL
);
