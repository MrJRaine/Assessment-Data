/*******************************************************************************
 * Diagnostic: departed student still appearing in later cycles' rosters
 * Created: 2026-10-30
 * Region: Canada East (PIIDPA compliant)
 *
 * READ-ONLY. Pulls one student's enrollment picture to confirm (or rule out)
 * the suspected mechanism: usp_RebuildRosterMembership keeps a student on a
 * window's roster by DATE OVERLAP alone (no ActiveFlag filter — deliberate,
 * 2026-10-13 paper-backfill decision), so if FactEnrollment.EndDate is NOT the
 * student's actual departure date (defensive close leaves it at the scheduled
 * term end; PS DateLeft may hold the scheduled date), the student overlaps
 * every later window through term end and bleeds into cycle 2+.
 *
 * Reads: DimStudent, FactEnrollment, DimSection, DimAssessmentWindow,
 *        SectionRosterMembership. Writes: nothing.
 *
 * BEFORE RUNNING: set @StudentNumber below to the student's provincial number.
 * Leave the committed value 0 — don't commit a real student number to the repo.
 ******************************************************************************/

DECLARE @StudentNumber BIGINT = 0;   -- <<< SET ME, don't commit the real value

-- ---------------------------------------------------------------------------
-- 1) DimStudent versions. If no IsCurrent = 1 row exists, the rebuild's
--    INNER JOIN to the current student would EXCLUDE them entirely — so if
--    they still show on a roster, either a current row exists (e.g. school
--    transfer re-version) or the membership predates the close.
-- ---------------------------------------------------------------------------
SELECT 'DimStudent versions' AS ResultSet,
       ds.StudentKey, ds.Grade, ds.SchoolID, ds.ProgramCode, ds.Homeroom,
       ds.EffectiveStartDate, ds.EffectiveEndDate, ds.IsCurrent
FROM DimStudent ds
WHERE ds.StudentNumber = @StudentNumber
ORDER BY ds.EffectiveStartDate;

-- ---------------------------------------------------------------------------
-- 2) Every FactEnrollment row for the student (via ALL DimStudent versions,
--    since closed enrollments freeze on old StudentKeys). THE KEY COLUMN IS
--    EnrolEndDate:
--      - ~the actual departure date  -> enrollment data is fine; bug is in
--        the read path / a stale membership rebuild.
--      - NULL or a term-end date (e.g. Jan/Jun) with ActiveFlag = 0 -> the
--        defensive close (merge step 5) or a scheduled PS DateLeft left
--        EndDate wrong -> date overlap keeps them in every later cycle.
-- ---------------------------------------------------------------------------
SELECT 'FactEnrollment rows' AS ResultSet,
       fe.EnrollmentID, fe.SourceSystemID, fe.StudentKey,
       sec.SectionID, sec.CourseCode, sec.SchoolID,
       fe.StartDate AS EnrolStartDate, fe.EndDate AS EnrolEndDate,
       fe.ActiveFlag, fe.LastUpdated
FROM FactEnrollment fe
INNER JOIN DimStudent ds ON ds.StudentKey = fe.StudentKey
                        AND ds.StudentNumber = @StudentNumber
LEFT  JOIN DimSection sec ON sec.SectionKey = fe.SectionKey
ORDER BY fe.StartDate, sec.SectionID;

-- ---------------------------------------------------------------------------
-- 3) What the materialized roster CURRENTLY holds for the student (ground
--    truth of what the app shows), with each window's cycle + dates.
-- ---------------------------------------------------------------------------
SELECT 'SectionRosterMembership now' AS ResultSet,
       w.WindowName, w.CycleGroupID, w.AssessmentType,
       w.StartDate AS WindowStart, w.EndDate AS WindowEnd,
       srm.SectionID, srm.GroupKey, srm.Grade, srm.SchoolName, srm.LastRebuiltAt
FROM SectionRosterMembership srm
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = srm.AssessmentWindowID
WHERE srm.StudentNumber = @StudentNumber
ORDER BY w.StartDate, w.AssessmentType, srm.SectionID;

-- ---------------------------------------------------------------------------
-- 4) The rebuild's own overlap test, replayed: which ACTIVE windows each of
--    the student's enrollment episodes matches, and why. Any row here whose
--    WindowStart is AFTER the student's real departure = the bleed, and
--    WhyKept names the mechanism.
-- ---------------------------------------------------------------------------
SELECT 'Rebuild overlap replay' AS ResultSet,
       w.WindowName, w.CycleGroupID, w.AssessmentType,
       w.StartDate AS WindowStart, w.EndDate AS WindowEnd,
       sec.SectionID, fe.EnrollmentID,
       fe.StartDate AS EnrolStartDate, fe.EndDate AS EnrolEndDate, fe.ActiveFlag,
       CASE WHEN fe.EndDate IS NULL
            THEN 'EndDate NULL -> overlaps every window'
            ELSE 'EndDate ' + CONVERT(VARCHAR(10), fe.EndDate, 120)
                 + ' >= window start -> kept by date overlap' END AS WhyKept
FROM FactEnrollment fe
INNER JOIN DimStudent ds ON ds.StudentKey = fe.StudentKey
                        AND ds.StudentNumber = @StudentNumber
LEFT  JOIN DimSection sec ON sec.SectionKey = fe.SectionKey
INNER JOIN DimAssessmentWindow w
        ON w.ActiveFlag = 1
       AND fe.StartDate <= w.EndDate
       AND (fe.EndDate IS NULL OR fe.EndDate >= w.StartDate)
ORDER BY w.StartDate, w.AssessmentType, sec.SectionID;
