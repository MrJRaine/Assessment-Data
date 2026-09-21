/*******************************************************************************
 * Script: set_cycle_grade_ranges_by_subject.sql
 * Purpose: Split the grade band of EXISTING assessment cycles (Short Cycles of
 *          Response rows in DimAssessmentWindow) by subject:
 *            Reading -> P .. 8   (Primary through Grade 8)
 *            Writing -> P .. RG  (Primary through Returning Graduate)
 *            Math    -> P .. 6   (Primary through Grade 6)
 *          MinGrade moves to 'P' (Primary) for all three (previously the
 *          whole-population default 'PP'/Pre-Primary).
 * SCD Type: N/A (DimAssessmentWindow rows are managed manually)
 * Created: 2026-09-04
 * Region:  Canada East (PIIDPA compliant)
 *
 * Scope: cycles are REGION-WIDE (one row per subject, ProgramFamily NULL), so
 *        filtering by AssessmentType alone updates every cycle of that subject,
 *        including the per-subject rows of multi-subject cycles that share a
 *        CycleGroupID. Grade codes join DimGrade.GradeCode; ordering is by
 *        DimGrade.GradeOrder (P=0, 8=8, 6=6, RG=13).
 *
 * Idempotent: safe to re-run (sets absolute values, not deltas).
 ******************************************************************************/

-- ---- Reading: P .. 8 --------------------------------------------------------
UPDATE DimAssessmentWindow
SET MinGrade    = 'P',
    MaxGrade    = '8',
    LastUpdated = GETDATE()
WHERE AssessmentType = 'Reading';

-- ---- Writing: P .. RG -------------------------------------------------------
UPDATE DimAssessmentWindow
SET MinGrade    = 'P',
    MaxGrade    = 'RG',
    LastUpdated = GETDATE()
WHERE AssessmentType = 'Writing';

-- ---- Math: P .. 6 -----------------------------------------------------------
UPDATE DimAssessmentWindow
SET MinGrade    = 'P',
    MaxGrade    = '6',
    LastUpdated = GETDATE()
WHERE AssessmentType = 'Math';

-- ---- Verify -----------------------------------------------------------------
SELECT AssessmentType, MinGrade, MaxGrade, COUNT(*) AS CycleRows
FROM DimAssessmentWindow
GROUP BY AssessmentType, MinGrade, MaxGrade
ORDER BY AssessmentType, MinGrade, MaxGrade;
