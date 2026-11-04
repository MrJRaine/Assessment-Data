/*******************************************************************************
 * Script: audit_srhs_entries_by_specialists.sql
 * Purpose: Every SRHS result (reading + writing; SRHS is secondary — no math)
 *          whose last saver holds the SpecialistTeacher access level, with
 *          student number, cycle/instance, marks, dates, and who entered it.
 * Created: 2026-11-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  FactAssessmentReading, FactAssessmentWriting, DimStaff, DimStudent,
 *         DimAssessmentWindow, DimShortCycle, DimReadingScale
 * Writes: nothing (read-only)
 *
 * Caveats:
 *   - "Specialist" = the enterer's CURRENT AccessLevel ('SpecialistTeacher',
 *     overrides included). AccessLevel is Type 1 (overwritten, no history), so
 *     someone who was a specialist AT ENTRY but has since changed role won't
 *     appear, and a recent convert's old saves will. No role history exists.
 *   - Facts hold the LATEST saver only; FactSubmissionAudit has the full
 *     event history if a row needs it.
 *   - SRHS scope = the student's school on the FROZEN SCD version (at entry).
 *   - Saves dated on/before 2026-10-13 fall in the specialist entry-scope
 *     defect window (oversight path open since first implementation 2026-05-13,
 *     live-exposed from the 2026-10-02 launch, patched 2026-10-13).
 ******************************************************************************/

DECLARE @SchoolID VARCHAR(10) = '0716';   -- SRHS (Shelburne Regional High School)

SELECT
    r.Subject,
    r.StudentNumber,
    r.GradeAtEntry,
    r.CycleName,
    r.InstanceName,
    r.SchoolYear,
    r.Marks,
    r.AssessmentDate,
    r.SubmittedAtAtlantic,
    r.EnteredByName,
    r.EnteredByEmail,
    r.EnteredByPSTitle
FROM (
    -- ---------------- Reading ----------------
    SELECT
        'Reading'                                  AS Subject,
        f.StudentNumber,
        fv.Grade                                   AS GradeAtEntry,
        COALESCE(sc.DisplayName, w.WindowName)     AS CycleName,
        w.WindowName                               AS InstanceName,
        w.SchoolYear,
        CONCAT('Level ', COALESCE(f.LevelCode, '?'),
               ' [', rs.ScaleSystem, ']',
               ' | expected ', COALESCE(f.ExpectedMinLevelCode, '?'),
               '-',            COALESCE(f.ExpectedMaxLevelCode, '?'),
               ' | delta ',    COALESCE(CAST(f.ReadingDelta AS VARCHAR(10)), 'n/a')) AS Marks,
        f.AssessmentDate,
        CAST(f.SubmissionTimestamp AT TIME ZONE 'UTC'
             AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtAtlantic,
        ds.FirstName + ' ' + ds.LastName           AS EnteredByName,
        ds.Email                                   AS EnteredByEmail,
        ds.Title                                   AS EnteredByPSTitle
    FROM FactAssessmentReading f
    INNER JOIN DimStaff ds           ON ds.StaffKey = f.EnteredByStaffKey
    INNER JOIN DimStudent fv         ON fv.StudentKey = f.StudentKey
    INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
    LEFT  JOIN DimShortCycle sc      ON sc.CycleGroupID = w.CycleGroupID
    LEFT  JOIN DimReadingScale rs    ON rs.ReadingScaleID = f.ReadingScaleID
    WHERE fv.SchoolID = @SchoolID

    UNION ALL

    -- ---------------- Writing ----------------
    SELECT
        'Writing (' + f.AssessmentLanguage + ')'   AS Subject,
        f.StudentNumber,
        fv.Grade                                   AS GradeAtEntry,
        COALESCE(sc.DisplayName, w.WindowName)     AS CycleName,
        w.WindowName                               AS InstanceName,
        w.SchoolYear,
        CONCAT('I/O/L/C = ',
               COALESCE(f.IdeasScore, '?'),        '/',
               COALESCE(f.OrganizationScore, '?'), '/',
               COALESCE(f.LanguageScore, '?'),     '/',
               COALESCE(f.ConventionsScore, '?'),
               ' | avg ', COALESCE(CAST(f.WritingAverage AS VARCHAR(10)), 'n/a')) AS Marks,
        f.AssessmentDate,
        CAST(f.SubmissionTimestamp AT TIME ZONE 'UTC'
             AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtAtlantic,
        ds.FirstName + ' ' + ds.LastName           AS EnteredByName,
        ds.Email                                   AS EnteredByEmail,
        ds.Title                                   AS EnteredByPSTitle
    FROM FactAssessmentWriting f
    INNER JOIN DimStaff ds           ON ds.StaffKey = f.EnteredByStaffKey
    INNER JOIN DimStudent fv         ON fv.StudentKey = f.StudentKey
    INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
    LEFT  JOIN DimShortCycle sc      ON sc.CycleGroupID = w.CycleGroupID
    WHERE fv.SchoolID = @SchoolID
) r
WHERE EXISTS (                                      -- enterer is CURRENTLY SpecialistTeacher
    SELECT 1
    FROM DimStaff cur
    WHERE LOWER(cur.Email) = LOWER(r.EnteredByEmail)
      AND cur.IsCurrent = 1
      AND cur.AccessLevel = 'SpecialistTeacher'
)
ORDER BY r.SubmittedAtAtlantic DESC, r.StudentNumber;
