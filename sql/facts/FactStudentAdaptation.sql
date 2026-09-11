/*******************************************************************************
 * Table: FactStudentAdaptation
 * Purpose: Tracks per-student, per-subject, per-program-family ADAPTATION status
 *          with SCD Type 2 versioning. Structural MIRROR of FactStudentIPP,
 *          keyed on the PowerSchool "has adaptations" flag (DimStudent.Adap)
 *          instead of DimStudent.IPP. PowerSchool records only ONE global
 *          "has adaptations" yes/no per student; this table breaks that out by
 *          SUBJECT so teachers can record which subjects a student's adaptation
 *          applies to (Reading / Writing / Math) -- the "Adaptations" half of
 *          the Programming section. No adaptation-type/focus detail is stored:
 *          the grain is simply (student, subject) yes/no.
 *
 *          RECORD-ONLY for now: unlike IPP, an adaptation does NOT alter any
 *          achievement/aggregate computation or data-entry gating. It is
 *          captured to be used as a data FILTER later. (project_programming_makeover)
 * SCD Type: Type 2 (close + insert pattern on HasAdaptation changes)
 * Created: 2026-09-11
 * Region: Canada East (PIIDPA compliant)
 *
 * Reconciliation key (triple): (StudentKey, Subject, ProgramFamily)
 *
 * HasAdaptation semantics (mirrors FactStudentIPP.IsIPP):
 *   NULL = unresolved gate. Auto-created by usp_MergeStudent when a student
 *          appears with PS-Adap = 1. Awaits teacher/admin confirmation.
 *      1 = student has an adaptation for this subject + program family.
 *      0 = student has no adaptation for this subject + program family.
 *
 * Auto-create applicability rules (handled in usp_MergeStudent, mirroring IPP,
 * plus Math which literacy IPP does not yet seed):
 *   ProgramFamily 'English' student with DimStudent.Adap=1:
 *     -> ('Reading','English'), ('Writing','English'), HasAdaptation=NULL
 *   ProgramFamily 'French Immersion' student with DimStudent.Adap=1:
 *     -> ('Reading','French Immersion'), ('Writing','French Immersion') (any grade)
 *     -> If grade >= 3, ALSO ('Reading','English'), ('Writing','English')
 *   Math (any program) with DimStudent.Adap=1 AND grade P-6 (GradeOrder <= 6):
 *     -> ('Math', <the student's own ProgramFamily>)  -- SINGLE row; Math is not
 *        language-split, and Math cycles are P-6 only.
 *
 * Closure rules: when DimStudent.Adap changes 1 -> 0 (or the student is
 *   deactivated / changes program / drops applicability), close all current
 *   rows no longer in the expected set (IsCurrent=0, EffectiveEndDate=@EffectiveDate-1).
 *   History of prior 1/0 values is preserved on the closed rows.
 *
 * Web app binding: the web app reads this via tvf_StudentAdaptation (@UPN-scoped
 *   iTVF) / vw_StudentAdaptation, which cast BIGINT keys to VARCHAR(20) per the
 *   project_powerapps_bigint_precision convention. Writes go through
 *   usp_UpsertStudentAdaptation (wrapper proc; no OUTPUT clause).
 *
 * ChangedBy convention:
 *   'system'   -> row created by usp_MergeStudent auto-create
 *   '<email>'  -> row created by usp_UpsertStudentAdaptation (teacher/admin action)
 ******************************************************************************/

CREATE TABLE FactStudentAdaptation (
    StudentAdaptationID BIGINT          NOT NULL IDENTITY,
    StudentKey          BIGINT          NOT NULL,    -- ref to DimStudent surrogate
    Subject             VARCHAR(20)     NOT NULL,    -- 'Reading', 'Writing', 'Math'
    ProgramFamily       VARCHAR(50)     NOT NULL,    -- 'English', 'French Immersion'
    HasAdaptation       BIT             NULL,        -- NULL = unresolved gate; 1 = has; 0 = none
    EffectiveStartDate  DATE            NOT NULL,
    EffectiveEndDate    DATE            NULL,        -- NULL = current version
    IsCurrent           BIT             NOT NULL,
    ChangedBy           VARCHAR(255)    NULL,        -- 'system' or caller email (lowercased)
    LastUpdated         DATETIME2(0)    NOT NULL
);
