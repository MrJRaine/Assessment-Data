/*******************************************************************************
 * Diagnostic: diag_dev_regen_baseline_2026-11-17.sql   (DEV: Assessment_Warehouse_Dev)
 * Purpose: Before re-ingesting the regenerated test set (CHES 2/3 + 3/4 splits),
 *          confirm which version of two drifted values the dev warehouse holds,
 *          and that the assessment windows admit grades 2-3. READ-ONLY.
 *
 * READS: DimStaff, DimStudent, FactStudentIPP, DimAssessmentWindow, DimGrade.
 * WRITES: nothing.
 *
 * Result meanings:
 *   1) P-EN teacher: shows which email variant is current for the 0079
 *      Primary-EN teacher (Pat Willow). 'teach.elem.en.0@...' = dev matches the
 *      OLD files -> regenerating as-is would swap the teacher identity on
 *      MAT-P-EN/ELA-P-EN; 'teach.elem.en.p@...' = dev already matches the
 *      script -> no churn.
 *   2) Student 9200000341: current Grade + IPP rows. Grade '8' and no flagged
 *      IPP = dev matches the OLD (hand-edited) file; Grade '7' = matches the
 *      script. Decides whether the regen re-versions this one student.
 *   3) Window grade bands: every active 2026-2027 window's [MinGrade, MaxGrade]
 *      with the grade-order span. InBand23 = 1 means grades 2 AND 3 fall inside
 *      that window's band (entry gate 51016 passes); 0 on an elementary-band
 *      window means the band must be widened before the new classes can enter
 *      results in it.
 *   4) DimGrade rows for '2' and '3' (both must exist for the entry grade gate).
 ******************************************************************************/

-- 1) Which P-EN teacher identity is current?
SELECT 'P-EN teacher' AS Check_, Email, FirstName, LastName, SchoolID, IsCurrent, EffectiveStartDate
FROM DimStaff
WHERE Email IN ('teach.elem.en.0@tcrce.ca', 'teach.elem.en.p@tcrce.ca')
ORDER BY Email, EffectiveStartDate;

-- 2) The hand-edited student: current version + IPP state
SELECT 'Student 9200000341' AS Check_, s.StudentNumber, s.Grade, s.SchoolID, s.ProgramCode,
       s.IsCurrent, s.EffectiveStartDate, i.Subject, i.IsIPP, i.IsCurrent AS IppIsCurrent
FROM DimStudent s
LEFT JOIN FactStudentIPP i ON i.StudentKey = s.StudentKey AND i.IsCurrent = 1
WHERE s.StudentNumber = 9200000341 AND s.IsCurrent = 1;

-- 3) Do the current-year windows admit grades 2 and 3?
SELECT w.WindowName, w.AssessmentType, w.ScaleSystem, w.ProgramScope,
       w.MinGrade, w.MaxGrade,
       CASE WHEN g2.GradeOrder BETWEEN gmin.GradeOrder AND gmax.GradeOrder
             AND g3.GradeOrder BETWEEN gmin.GradeOrder AND gmax.GradeOrder
            THEN 1 ELSE 0 END AS InBand23
FROM DimAssessmentWindow w
INNER JOIN DimGrade gmin ON gmin.GradeCode = w.MinGrade
INNER JOIN DimGrade gmax ON gmax.GradeCode = w.MaxGrade
CROSS JOIN (SELECT GradeOrder FROM DimGrade WHERE GradeCode = '2') g2
CROSS JOIN (SELECT GradeOrder FROM DimGrade WHERE GradeCode = '3') g3
WHERE w.ActiveFlag = 1 AND w.SchoolYear = '2026-2027'
GROUP BY w.WindowName, w.AssessmentType, w.ScaleSystem, w.ProgramScope, w.MinGrade, w.MaxGrade,
         g2.GradeOrder, g3.GradeOrder, gmin.GradeOrder, gmax.GradeOrder
ORDER BY w.AssessmentType, w.ScaleSystem, w.WindowName;

-- 4) DimGrade has rows for the two new grades
SELECT 'DimGrade' AS Check_, GradeCode, GradeOrder FROM DimGrade WHERE GradeCode IN ('2', '3');
