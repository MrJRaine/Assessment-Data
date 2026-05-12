/*******************************************************************************
 * Seed: DimGrade
 * Purpose: Populate the 15 valid grade codes with their numeric ordering and
 *          band classification.
 * Created: 2026-05-12
 * Region: Canada East (PIIDPA compliant)
 *
 * Grades covered:
 *   PP  (Pre-Primary)         GradeOrder=-1   Elementary
 *   P   (Primary)              GradeOrder= 0   Elementary
 *   1   (Grade 1)              GradeOrder= 1   Elementary
 *   2   (Grade 2)              GradeOrder= 2   Elementary
 *   3   (Grade 3)              GradeOrder= 3   Elementary
 *   4   (Grade 4)              GradeOrder= 4   Elementary
 *   5   (Grade 5)              GradeOrder= 5   Elementary
 *   6   (Grade 6)              GradeOrder= 6   Elementary
 *   7   (Grade 7)              GradeOrder= 7   Junior High
 *   8   (Grade 8)              GradeOrder= 8   Junior High
 *   9   (Grade 9)              GradeOrder= 9   Junior High
 *   10  (Grade 10)             GradeOrder=10   Senior High
 *   11  (Grade 11)             GradeOrder=11   Senior High
 *   12  (Grade 12)             GradeOrder=12   Senior High
 *   RG  (Returning Graduate)   GradeOrder=13   Senior High
 *
 * Source ingest translations (in usp_MergeStudent → Wrk_Student):
 *   PowerSchool grade_level = -1 → 'PP'
 *   PowerSchool grade_level =  0 → 'P'
 *   PowerSchool grade_level = 13 → 'RG'   (added 2026-05-12)
 *   All others stored verbatim ('1' through '12')
 *
 * Run order: after DimGrade.sql has created the table; before any window-
 * applicability views (vw_UserAssessmentWindows etc.) are created.
 ******************************************************************************/

INSERT INTO DimGrade (GradeCode, GradeOrder, GradeName, GradeBand, ActiveFlag, LastUpdated) VALUES
    ('PP', -1, 'Pre-Primary',         'Elementary',  1, GETDATE()),
    ('P',   0, 'Primary',              'Elementary',  1, GETDATE()),
    ('1',   1, 'Grade 1',              'Elementary',  1, GETDATE()),
    ('2',   2, 'Grade 2',              'Elementary',  1, GETDATE()),
    ('3',   3, 'Grade 3',              'Elementary',  1, GETDATE()),
    ('4',   4, 'Grade 4',              'Elementary',  1, GETDATE()),
    ('5',   5, 'Grade 5',              'Elementary',  1, GETDATE()),
    ('6',   6, 'Grade 6',              'Elementary',  1, GETDATE()),
    ('7',   7, 'Grade 7',              'Junior High', 1, GETDATE()),
    ('8',   8, 'Grade 8',              'Junior High', 1, GETDATE()),
    ('9',   9, 'Grade 9',              'Junior High', 1, GETDATE()),
    ('10', 10, 'Grade 10',             'Senior High', 1, GETDATE()),
    ('11', 11, 'Grade 11',             'Senior High', 1, GETDATE()),
    ('12', 12, 'Grade 12',             'Senior High', 1, GETDATE()),
    ('RG', 13, 'Returning Graduate',   'Senior High', 1, GETDATE());
