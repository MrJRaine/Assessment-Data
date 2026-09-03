/*******************************************************************************
 * Table: FactAssessmentMath
 * Purpose: Per-task math results entered by teachers — one bit per student per
 *          task per cycle: 1 = can do the task, 0 = cannot. Everything the
 *          reports need (grade, term, unit, outcome, task text) derives through
 *          MathTaskKey -> DimMathTask; the fact stays a thin (who, which task,
 *          got-it?) grain.
 * SCD Type: N/A (fact).
 * Created: 2026-09-02
 * Region: Canada East (PIIDPA compliant)
 *
 * Grain: Student x Window x Task x DATE — one row per (StudentKey,
 *   AssessmentWindowID, MathTaskKey, AssessmentDate). KEEPS CHANGE HISTORY like
 *   FactAssessmentReading/Writing's ongoing-assessment model: usp_UpsertMathAssessment
 *   INSERTS a new dated row (AssessmentDate capped at MIN(today, window EndDate) so
 *   late entry bins into the window's month); a same-date re-entry for the same task
 *   UPDATES that day's row. Every read that resolves a per-(student, task) result
 *   MUST pick the LATEST — ROW_NUMBER() OVER (PARTITION BY StudentKey,
 *   AssessmentWindowID, MathTaskKey ORDER BY AssessmentDate DESC, MathAssessmentID DESC)
 *   = 1 — or a student/task fans out to one row per entry (see the fabric-warehouse-sql
 *   skill's "ongoing-assessment / multiple-entry fact patterns" note).
 *
 * Key resolution: StudentKey / EnteredByStaffKey are the surrogate values
 *   current at entry time (assessment-fact insert-time resolution — see
 *   project_assessment_fact_scd_policy). Reads join back to DimStudent /
 *   DimStaff / DimMathTask; no business keys are stored on the fact.
 *
 * Derived layers (computed in the read views over each student's LATEST result per
 * task, NOT stored here):
 *   - by task:            SUM(Result) / #students assessed -> proportion -> colour band
 *   - by student, unit:   AVG(Result) over the unit's tasks -> comprehension band
 *                         ('Incomplete' when < 80% of the unit's tasks are scored)
 *   - class distribution: COUNT of students in each comprehension band, per unit
 *   Band labels/colours come from DimMathComprehensionBand (join by code);
 *   the exact thresholds live in the view (mirrors the Writing avg->band pattern).
 ******************************************************************************/

CREATE TABLE FactAssessmentMath (
    MathAssessmentID    BIGINT          NOT NULL IDENTITY,   -- Surrogate key
    StudentKey          BIGINT          NOT NULL,   -- References DimStudent.StudentKey (current at entry)
    AssessmentWindowID  BIGINT          NOT NULL,   -- References DimAssessmentWindow.AssessmentWindowID (the Math Short Cycle window)
    MathTaskKey         BIGINT          NOT NULL,   -- References DimMathTask.MathTaskKey
    Result              BIT             NOT NULL,   -- 1 = can do the task, 0 = cannot
    AssessmentDate      DATE            NOT NULL,   -- date the result was recorded (Atlantic)
    EnteredByStaffKey   BIGINT          NOT NULL,   -- References DimStaff.StaffKey
    SubmissionTimestamp DATETIME2(0)    NOT NULL,   -- UTC (storage convention)
    LastUpdated         DATETIME2(0)    NOT NULL    -- Set on insert / bit correction
);
