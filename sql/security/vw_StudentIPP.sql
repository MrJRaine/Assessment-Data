/*******************************************************************************
 * View: vw_StudentIPP
 * Purpose: Power-Apps-facing view of per-student IPP status, RLS-filtered to
 *          the calling user's scope. Long format: one row per (Student,
 *          Subject, ProgramFamily) where a current FactStudentIPP row exists.
 *          Non-applicable combinations (e.g. English Reading IPP for an FI
 *          grade-1 student) simply don't appear -- the screen renders those
 *          cells as "n/a" by absence.
 *
 *          Consumed by:
 *            - scrIPP (the bulk IPP management screen): primary data source.
 *            - scrRosterGrid: inline IPP gating check (does this row's matching
 *              (Subject, ProgramFamily) have IsIPP = NULL?).
 *            - scrGroupSelect: red alert when any student in a section has a
 *              matching NULL IsIPP for the current assessment context.
 *
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * RLS branching (role-branched via OR across three EXISTS clauses):
 *   Regional Analyst:  sees all current IPP rows (no school/student filter)
 *   Admin / SpecialistTeacher: sees rows for students in their schools
 *                              (StaffSchoolAccess.AccessLevel IN
 *                              'Administrator','SpecialistTeacher')
 *   Teacher: sees rows for students on their current section roster
 *            (FactSectionTeachers matching CURRENT_USER, joined through
 *            DimSection / FactEnrollment to DimStudent)
 *
 *   Uses CURRENT_USER (not USERPRINCIPALNAME() -- the latter is not supported
 *   in Fabric Warehouse SQL; CURRENT_USER returns the same UPN under Entra
 *   auth).
 *
 * Power Apps binding notes:
 *   - StudentKey and StudentIPPID are CAST to VARCHAR(20) to dodge Power Fx's
 *     16-digit precision ceiling on 19-digit BIGINT IDENTITY values (see
 *     project_powerapps_bigint_precision memory).
 *   - StudentNumber stays BIGINT (10-digit provincial number; within Power
 *     Fx safe range).
 *
 * After deploying this view: Power Apps users MUST remove + re-add the
 * Assessment_Warehouse data source so the connector picks up the new view
 * (per feedback_powerapps_data_source_refresh memory).
 ******************************************************************************/

DROP VIEW IF EXISTS vw_StudentIPP;
GO

CREATE VIEW vw_StudentIPP AS
SELECT
    CAST(s.StudentKey AS VARCHAR(20))         AS StudentKey,
    s.StudentNumber,
    s.FirstName,
    s.MiddleName,
    s.LastName,
    s.Grade,
    s.Homeroom,
    s.SchoolID,
    s.ProgramCode,
    p.ProgramFamily                            AS StudentProgramFamily,
    fsi.Subject,
    fsi.ProgramFamily                          AS IPPProgramFamily,
    fsi.IsIPP,
    CAST(fsi.StudentIPPID AS VARCHAR(20))      AS StudentIPPID,
    fsi.EffectiveStartDate                     AS IPPEffectiveStartDate,
    fsi.ChangedBy                              AS IPPChangedBy
FROM DimStudent s
JOIN DimProgram p
    ON p.ProgramCode = s.ProgramCode
JOIN FactStudentIPP fsi
    ON  fsi.StudentKey = s.StudentKey
    AND fsi.IsCurrent  = 1
WHERE s.IsCurrent = 1
  AND (
        -- Regional Analyst: full visibility
        EXISTS (
            SELECT 1 FROM DimStaff staff
            WHERE LOWER(staff.Email) = LOWER(CURRENT_USER)
              AND staff.IsCurrent  = 1
              AND staff.AccessLevel = 'RegionalAnalyst'
        )
        OR
        -- Administrator / SpecialistTeacher: school-scoped
        EXISTS (
            SELECT 1 FROM StaffSchoolAccess ssa
            WHERE LOWER(ssa.Email) = LOWER(CURRENT_USER)
              AND ssa.SchoolID     = s.SchoolID
              AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher')
        )
        OR
        -- Teacher: section-roster-scoped
        EXISTS (
            SELECT 1
            FROM   FactSectionTeachers fst
            JOIN   DimSection sec
                ON sec.SectionID = fst.SectionID
               AND sec.IsCurrent = 1
            JOIN   FactEnrollment e
                ON e.SectionKey  = sec.SectionKey
               AND e.ActiveFlag  = 1
            WHERE LOWER(fst.TeacherEmail) = LOWER(CURRENT_USER)
              AND fst.IsCurrent = 1
              AND e.StudentKey  = s.StudentKey
        )
      );
GO
