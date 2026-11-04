/*******************************************************************************
 * Script: audit_writing_entries_nonsection_staff_srhs.sql
 * Purpose: Find WRITING results at SRHS whose last saver was NOT a teacher of
 *          any section that student sat in for that cycle — i.e. entries made
 *          by staff outside the student's own section teacher(s).
 * Created: 2026-11-04
 * Region: Canada East (PIIDPA compliant)
 *
 * Reads:  FactAssessmentWriting, DimStaff, DimStudent, DimAssessmentWindow,
 *         DimShortCycle, TeacherRosterMembership
 * Writes: nothing (read-only)
 *
 * How it decides: TeacherRosterMembership holds one row per (TeacherEmail,
 * AssessmentWindowID, SectionID, Student) for every teacher/co-teacher on the
 * section (FactSectionTeachers). A fact row is flagged when the enterer's email
 * has NO membership row for that (window, StudentNumber).
 *
 * Caveats:
 *   - EnteredByStaffKey = the LATEST saver only; an original save by the section
 *     teacher later corrected by someone else shows the corrector (and vice
 *     versa). FactSubmissionAudit holds the full event history if needed.
 *   - TeacherRosterMembership is a cache rebuilt from CURRENT FactSectionTeachers
 *     each ingest. A teacher reassigned AWAY since a past cycle can FALSE-POSITIVE
 *     for that old cycle (the teacher-axis historical fix is still open).
 *   - A hit is not automatically wrongdoing: admins, coaches with overrides, and
 *     sysadmin corrections legitimately enter for sections they don't teach.
 *   - SRHS scope = the student's school ON THE FROZEN SCD VERSION (school at
 *     entry time), so movers are judged by where they were when it was recorded.
 ******************************************************************************/

DECLARE @SchoolID VARCHAR(10) = '0716';   -- SRHS (Shelburne Regional High School)

SELECT
    f.StudentNumber,
    fv.Grade                                      AS GradeAtEntry,
    COALESCE(sc.DisplayName, w.WindowName)        AS CycleName,
    w.WindowName                                  AS InstanceName,
    w.SchoolYear,
    f.AssessmentLanguage,
    f.IdeasScore,
    f.OrganizationScore,
    f.LanguageScore,
    f.ConventionsScore,
    f.WritingAverage,
    f.AssessmentDate,
    CAST(f.SubmissionTimestamp AT TIME ZONE 'UTC'
         AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtAtlantic,
    ds.FirstName + ' ' + ds.LastName              AS EnteredByName,
    ds.Email                                      AS EnteredByEmail,
    -- who the student's section teacher(s) actually were that cycle (for contrast)
    st.SectionTeachers
FROM FactAssessmentWriting f
INNER JOIN DimStaff ds           ON ds.StaffKey = f.EnteredByStaffKey
INNER JOIN DimStudent fv         ON fv.StudentKey = f.StudentKey        -- frozen version = state at entry
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = f.AssessmentWindowID
LEFT  JOIN DimShortCycle sc      ON sc.CycleGroupID = w.CycleGroupID
OUTER APPLY (
    SELECT STRING_AGG(x.TeacherEmail, ', ') AS SectionTeachers
    FROM (SELECT DISTINCT trm2.TeacherEmail
          FROM TeacherRosterMembership trm2
          WHERE trm2.AssessmentWindowID = f.AssessmentWindowID
            AND trm2.StudentNumber = f.StudentNumber) x
) st
WHERE w.AssessmentType = 'Writing'
  AND fv.SchoolID = @SchoolID
  AND NOT EXISTS (
        SELECT 1
        FROM TeacherRosterMembership trm
        WHERE trm.TeacherEmail = LOWER(ds.Email)
          AND trm.AssessmentWindowID = f.AssessmentWindowID
          AND trm.StudentNumber = f.StudentNumber
  )
ORDER BY f.SubmissionTimestamp DESC, f.StudentNumber;
