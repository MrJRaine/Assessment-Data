/*******************************************************************************
 * Script: seed_mover_sentinel_dev  —  DEV WAREHOUSE ONLY. NEVER RUN ON LIVE.
 * Purpose: Simulate a mid-year school TRANSFER so the 2026-10-30 historical
 *          school attribution can be verified on dev (the generator produces no
 *          movers). Re-versions one student to a different school the way a PS
 *          ingest would (close current version + insert new version at school B),
 *          closes their enrolments with today's date (as the fixed merge step 5
 *          now does), and rebuilds roster membership.
 *
 *          Expected after running (student assessed in a CLOSED cycle at school A):
 *            - Cycle-filtered reports (that cycle): student under SCHOOL A
 *              (old grade/homeroom); school A's admin sees them, school B's doesn't.
 *            - "Current" (no cycle) reports: student under SCHOOL B.
 *            - The old section's entry roster for that cycle still lists them
 *              (paper backfill); they're absent from later cycles' rosters.
 *            - A LATE entry saved into the old section's closed cycle binds to the
 *              school-A version (section-school binding in the upsert procs).
 *
 * Reads:  DimStudent, DimSchool, FactAssessmentReading, DimAssessmentWindow, FactEnrollment.
 * Writes: DimStudent (close + insert one version), FactEnrollment (close the
 *         student's active rows), then EXEC usp_RebuildRosterMembership.
 * NOT idempotent — running twice re-versions the (already moved) student again,
 * which is harmless but noisy. Pick a different student by setting @StudentNumber.
 * Region: Canada East (PIIDPA compliant) — synthetic dev data only.
 ******************************************************************************/

DECLARE @StudentNumber BIGINT = 0;   -- 0 = auto-pick a student with a reading result in a CLOSED cycle
DECLARE @Today DATE = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- Auto-pick: a currently-enrolled student with a reading result in a closed cycle window.
IF @StudentNumber = 0
    SELECT TOP 1 @StudentNumber = s.StudentNumber
    FROM DimStudent s
    WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1)
      AND EXISTS (SELECT 1
                  FROM FactAssessmentReading far
                  INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = far.AssessmentWindowID
                  WHERE far.StudentNumber = s.StudentNumber
                    AND w.ActiveFlag = 1 AND w.EndDate < @Today)
    ORDER BY s.StudentNumber;

-- New school = any other school that already has current students (so the tree shows it).
DECLARE @OldSchoolID VARCHAR(10), @NewSchoolID VARCHAR(10), @NewAbbrev VARCHAR(20);
SELECT @OldSchoolID = SchoolID FROM DimStudent WHERE StudentNumber = @StudentNumber AND IsCurrent = 1;
SELECT TOP 1 @NewSchoolID = s.SchoolID
FROM DimStudent s
WHERE s.IsCurrent = 1 AND s.SchoolID <> @OldSchoolID
GROUP BY s.SchoolID
ORDER BY COUNT(*) DESC;
SELECT @NewAbbrev = Abbreviation FROM DimSchool WHERE SchoolID = @NewSchoolID;

-- PREVIEW: who is being moved, from where to where.
SELECT @StudentNumber AS StudentNumber, @OldSchoolID AS FromSchool, @NewSchoolID AS ToSchool, @Today AS MoveDate;

-- 1) Close the current version (yesterday), exactly as usp_MergeStudent would on a transfer.
UPDATE DimStudent
SET EffectiveEndDate = DATEADD(DAY, -1, @Today),
    IsCurrent        = 0,
    LastUpdated      = GETDATE()
WHERE StudentNumber = @StudentNumber AND IsCurrent = 1;

-- 2) Insert the new version at the new school (new homeroom 'M1'; GroupKey = abbrev + '-M1').
INSERT INTO DimStudent (
    StudentNumber, FirstName, MiddleName, LastName, DateOfBirth, Grade, SchoolID, ProgramCode,
    EnrollStatus, Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap, GroupKey,
    EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
)
SELECT TOP 1
    StudentNumber, FirstName, MiddleName, LastName, DateOfBirth, Grade, @NewSchoolID, ProgramCode,
    EnrollStatus, 'M1', Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap,
    CASE WHEN @NewAbbrev IS NOT NULL THEN @NewAbbrev + '-M1' END,
    @Today, NULL, 1, SourceSystemID, GETDATE()
FROM DimStudent
WHERE StudentNumber = @StudentNumber AND EffectiveEndDate = DATEADD(DAY, -1, @Today)
ORDER BY StudentKey DESC;

-- 3) Close the student's active enrolments as the fixed defensive close now would
--    (ActiveFlag 0 + EndDate capped at today). All versions' keys covered via StudentNumber.
UPDATE fe
SET ActiveFlag  = 0,
    EndDate     = CASE WHEN fe.EndDate IS NULL OR fe.EndDate > @Today THEN @Today ELSE fe.EndDate END,
    LastUpdated = GETDATE()
FROM FactEnrollment fe
INNER JOIN DimStudent ds ON ds.StudentKey = fe.StudentKey
WHERE ds.StudentNumber = @StudentNumber AND fe.ActiveFlag = 1;

-- 4) Rebuild the materialized rosters (old-section closed-cycle roster keeps the student by
--    date overlap; they drop off later cycles).
EXEC dbo.usp_RebuildRosterMembership;

-- 5) VERIFY: version chain + where each recorded result is frozen.
SELECT 'Versions' AS ResultSet, StudentKey, Grade, SchoolID, Homeroom, GroupKey,
       EffectiveStartDate, EffectiveEndDate, IsCurrent
FROM DimStudent WHERE StudentNumber = @StudentNumber ORDER BY EffectiveStartDate;

SELECT 'Reading facts (frozen school)' AS ResultSet, far.ReadingAssessmentID, far.AssessmentDate,
       w.WindowName, w.CycleGroupID, ds.SchoolID AS FrozenSchoolID, ds.StudentKey AS FrozenStudentKey
FROM FactAssessmentReading far
INNER JOIN DimStudent ds ON ds.StudentKey = far.StudentKey
INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = far.AssessmentWindowID
WHERE far.StudentNumber = @StudentNumber
ORDER BY far.AssessmentDate;
