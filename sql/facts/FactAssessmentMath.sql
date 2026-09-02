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
 * Grain: one CURRENT row per (StudentKey, AssessmentWindowID, MathTaskKey).
 *   Unlike Reading/Writing's dated multiple-entry model, a math result is a
 *   binary can/cannot, so usp_UpsertMathAssessment OVERWRITES Result in place
 *   (a correction just flips the bit) rather than keeping a dated history.
 *   [DESIGN CHOICE TO CONFIRM — if a per-attempt history is wanted, add
 *   AssessmentDate to the grain and pick latest-by-date like the reading reads.]
 *
 * Key resolution: StudentKey / EnteredByStaffKey are the surrogate values
 *   current at entry time (assessment-fact insert-time resolution — see
 *   project_assessment_fact_scd_policy). Reads join back to DimStudent /
 *   DimStaff / DimMathTask; no business keys are stored on the fact.
 *
 * Derived layers (computed in the read views, NOT stored here):
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
