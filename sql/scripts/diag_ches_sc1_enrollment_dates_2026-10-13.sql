/*******************************************************************************
 * Script: diag_ches_sc1_enrollment_dates_2026-10-13.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Clark's Harbour (0511) Short-Cycle-1 rosters/cards show ~1 student for many
 *          sections while SC2–6 are full (see diag_ches_reading_membership). SC1 ran
 *          2026-09-01 → 2026-10-05. A student only counts toward a window if their
 *          enrollment OVERLAPS it (StartDate <= window end AND (EndDate NULL OR >= start)) —
 *          the SAME rule the live cards (tvf_TeacherGroups) and the membership rebuild use.
 *          This confirms whether the sparse SC1 counts are because most of each class has a
 *          FactEnrollment StartDate AFTER 2026-10-05 (i.e. enrollment "started" in October,
 *          typically a PowerSchool scheduling artifact), vs a stale membership rebuild.
 *
 * Reads:  DimSection, FactEnrollment (current rows). COUNTS + dates only — NO student PII.
 * Region: Canada East (PIIDPA compliant)
 *
 * How to read it, per section:
 *   - OverlapSC1  should match that section's SC1 MemberCount in the membership diag.
 *   - StartAfterSC1 ≈ (ActiveNow − OverlapSC1): the students excluded from SC1 ONLY because
 *     their enrollment starts after Oct 5. If this is most of the class, THAT is the cause.
 *   - MinStart / MaxStart: if a whole class clusters on a single October StartDate, the PS
 *     export dated the enrollments at schedule-commit time, not the first day of school
 *     (source-data fix). If OverlapSC1 = ActiveNow but membership SC1 was still 1, the
 *     membership rebuild is stale for the closed window instead (re-run usp_RebuildRosterMembership).
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @SchoolID VARCHAR(10) = '0511';          -- Clark's Harbour Elementary (CHES)
DECLARE @SC1Start DATE = '2026-09-01';           -- Short Cycle 1 window
DECLARE @SC1End   DATE = '2026-10-05';

SELECT
    sec.SectionID,
    sec.SectionNumber,
    sec.CourseName,
    COUNT(DISTINCT e.StudentKey) AS ActiveNow,                 -- current roster size
    COUNT(DISTINCT CASE WHEN e.StartDate <= @SC1End
                         AND (e.EndDate IS NULL OR e.EndDate >= @SC1Start)
                        THEN e.StudentKey END) AS OverlapSC1,  -- counts toward SC1 (should match SC1 MemberCount)
    COUNT(DISTINCT CASE WHEN e.StartDate > @SC1End THEN e.StudentKey END) AS StartAfterSC1,  -- excluded from SC1 only
    MIN(e.StartDate) AS MinStartDate,
    MAX(e.StartDate) AS MaxStartDate
FROM DimSection sec
JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
WHERE sec.SchoolID = @SchoolID
  AND sec.IsCurrent = 1
GROUP BY sec.SectionID, sec.SectionNumber, sec.CourseName
ORDER BY StartAfterSC1 DESC, sec.SectionNumber;
GO
