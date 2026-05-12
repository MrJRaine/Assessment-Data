/*******************************************************************************
 * Table: DimGrade
 * Purpose: Static reference dimension for grade codes used in DimStudent.Grade,
 *          DimAssessmentWindow.MinGrade/MaxGrade, DimReadingBenchmark.GradeCode,
 *          and any other grade-keyed table. Provides GradeOrder for arithmetic
 *          ordering — solves the lexicographic-ordering bug on bare VARCHAR
 *          grade comparisons (e.g. 'P' > '12' as strings).
 * SCD Type: N/A (static reference data)
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Key: GradeCode is the natural business key (no surrogate IDENTITY) — matches
 *      the convention used by DimGender, DimRole, DimProgram.
 *
 * GradeOrder semantics:
 *   - -1 = PP (Pre-Primary)
 *   -  0 = P  (Primary)
 *   -  1 to 12 = numbered grades, GradeOrder = grade number
 *   - 13 = RG (Returning Graduate — PowerSchool emits grade_level=13)
 *
 * GradeBand groups grades into Elementary / Junior High / Senior High per
 * Nova Scotia's standard tiering. Convenient for filtering / reporting.
 *
 * Used by window-applicability filters in vw_UserAssessmentWindows /
 * vw_TeacherGroups / vw_TeacherRoster:
 *   sg.GradeOrder BETWEEN wmin.GradeOrder AND wmax.GradeOrder
 ******************************************************************************/

CREATE TABLE DimGrade (
    GradeCode    VARCHAR(10)   NOT NULL,    -- Business key: 'PP', 'P', '1'-'12', 'RG'
    GradeOrder   INT           NOT NULL,    -- Sort order: -1, 0, 1-12, 13
    GradeName    VARCHAR(50)   NOT NULL,    -- 'Pre-Primary', 'Primary', 'Grade 1', ..., 'Returning Graduate'
    GradeBand    VARCHAR(20)   NOT NULL,    -- 'Elementary', 'Junior High', 'Senior High'
    ActiveFlag   BIT           NOT NULL,
    LastUpdated  DATETIME2(0)  NOT NULL
);
