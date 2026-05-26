/*******************************************************************************
 * Table: FactStudentIPP
 * Purpose: Tracks per-student, per-subject, per-program-family IPP status with
 *          SCD Type 2 versioning. Replaces the predecessor Excel's single
 *          school-wide "Literacy IPP" column with teacher-managed fine-grained
 *          tracking: a student can have a Reading IPP but no Writing IPP, or
 *          a French Reading IPP but no English Reading IPP (the latter
 *          applicable only to French Immersion students grade 3+).
 *
 *          Designed for future extension: the Subject column accommodates
 *          'Math' or other subjects without schema change.
 * SCD Type: Type 2 (close + insert pattern on IsIPP changes)
 * Created: 2026-05-26
 * Region: Canada East (PIIDPA compliant)
 *
 * Reconciliation key (triple): (StudentKey, Subject, ProgramFamily)
 *
 * IsIPP semantics:
 *   NULL = unresolved gate. Auto-created by usp_MergeStudent when a student
 *          first appears with PS-IPP = 1. Blocks downstream displays
 *          (achievement-level coloring, aggregate stats) and gates UI entry
 *          on scrRosterGrid (inline "Confirmation Required" prompt forces the
 *          teacher to flip it to 1 or 0 before continuing).
 *      1 = student has an IPP for this subject + program family. Their level
 *          is still tracked for personal progress, but they are excluded from
 *          achievement-level comparisons and aggregate stats.
 *      0 = student has no IPP for this subject + program family. Standard
 *          achievement-level evaluation applies.
 *
 * Auto-create applicability rules (handled in usp_MergeStudent):
 *   ProgramFamily 'English' student with DimStudent.IPP=1:
 *     -> Insert ('Reading','English') and ('Writing','English') rows, IsIPP=NULL
 *   ProgramFamily 'French Immersion' student with DimStudent.IPP=1:
 *     -> Insert ('Reading','French Immersion') and ('Writing','French Immersion')
 *        rows, IsIPP=NULL (always, regardless of grade)
 *     -> If grade >= 3, ALSO insert ('Reading','English') and
 *        ('Writing','English') rows, IsIPP=NULL
 *
 * Closure rules:
 *   When DimStudent.IPP changes from 1 to 0, close all current FactStudentIPP
 *   rows for that student (IsCurrent=0, EffectiveEndDate=@EffectiveDate-1).
 *   If the student re-acquires PS-IPP later, fresh NULL rows are created
 *   by the next merge; prior IsIPP=1/0 history is preserved in closed rows.
 *
 * Power Apps binding: Power Apps does NOT read this table directly. It binds
 *          to vw_StudentIPP (separate file) which casts StudentIPPID and
 *          StudentKey from BIGINT to VARCHAR(20) to dodge Power Fx's 16-digit
 *          precision ceiling (per project_powerapps_bigint_precision memory).
 *
 * ChangedBy convention:
 *   'system'                          -> row created by usp_MergeStudent auto-create
 *   '<email>'                         -> row created by usp_UpsertStudentIPP from
 *                                        teacher/admin action on scrIPP or scrRosterGrid
 ******************************************************************************/

CREATE TABLE FactStudentIPP (
    StudentIPPID        BIGINT          NOT NULL IDENTITY,
    StudentKey          BIGINT          NOT NULL,    -- FK-style ref to DimStudent surrogate
    Subject             VARCHAR(20)     NOT NULL,    -- 'Reading', 'Writing'; future-proof for 'Math' etc.
    ProgramFamily       VARCHAR(50)     NOT NULL,    -- 'English', 'French Immersion'
    IsIPP               BIT             NULL,        -- NULL = unresolved gate; 1 = has IPP; 0 = no IPP
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    ChangedBy           VARCHAR(255)    NULL,        -- 'system' or caller email (lowercased)
    LastUpdated         DATETIME2(0)    NOT NULL
);
