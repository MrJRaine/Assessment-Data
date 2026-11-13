/*******************************************************************************
 * Script: seed_prior_year_only_result_dev.sql
 * Purpose: DEV ONLY (Assessment_Warehouse_Dev). Seed ONE reading result in the
 *          LAST-school-year June 2026 window for a current grade-4 Hillcrest
 *          (0079) student who has NO reading results at all - the probe for
 *          testing plan 1.4.0 §2 ("Current" = lifetime):
 *            - Reading summary tree + Student list on CURRENT: the student shows
 *              this June 2026 level (with its Expected range), NOT "No data",
 *              and counts as ASSESSED in both donuts (parity intact).
 *            - With Cycle 1 or 2 selected: the student is expected-unassessed
 *              ("-") - a prior-year result never leaks into a selected cycle.
 *
 * Writes: FactAssessmentReading +1 row (June 2026 window, EN_Reading level M,
 *         AssessmentDate 2026-06-15); FactSubmissionAudit +1 seed row.
 * Reads:  SectionRosterMembership + FactStudentIPP (choose an eligible student:
 *         no reading facts, no unresolved/confirmed Reading IPP - so the band
 *         actually renders), DimAssessmentWindow (June 2026 EN_Reading window),
 *         DimReadingScale, DimStudent, DimStaff.
 *
 * Idempotent: guarded by the FactSubmissionAudit seed marker - a re-run prints
 *         the already-seeded student and changes nothing (without the guard a
 *         re-run would pick the NEXT fact-less student and seed again).
 * Revert: delete the inserted fact (its Source message names the student) or
 *         just leave it - it is ordinary synthetic data.
 *
 * Created: 2026-11-13   Region: Canada East (PIIDPA compliant) - synthetic data
 ******************************************************************************/

DECLARE @Marker VARCHAR(100) = 'seed_prior_year_only_result_dev.sql';

IF EXISTS (SELECT 1 FROM FactSubmissionAudit WHERE Source = 'DevSeed' AND Message LIKE 'Prior-year-only probe%' AND SubmittedBy = @Marker)
BEGIN
    SELECT 'ALREADY SEEDED - nothing changed. Existing probe:' AS Result, Message
    FROM FactSubmissionAudit
    WHERE Source = 'DevSeed' AND SubmittedBy = @Marker AND Message LIKE 'Prior-year-only probe%';
END
ELSE
BEGIN
    DECLARE @JuneCycle VARCHAR(36) = '6a11e000-2026-406e-9c17-0de100062026';

    -- The June 2026 (prior school year) English reading window
    DECLARE @WindowId BIGINT =
        (SELECT TOP 1 w.AssessmentWindowID FROM DimAssessmentWindow w
         WHERE w.CycleGroupID = @JuneCycle AND w.AssessmentType = 'Reading'
           AND w.ScaleSystem = 'EN_Reading' AND w.ActiveFlag = 1
         ORDER BY w.AssessmentWindowID);

    -- Level M on the EN scale (a plausible grade-3 June level)
    DECLARE @ScaleId BIGINT =
        (SELECT ReadingScaleID FROM DimReadingScale
         WHERE ScaleSystem = 'EN_Reading' AND LevelCode = 'M');

    -- A current grade-4 student at 0079, expected in reading this year, with NO
    -- reading facts ever and no unresolved/confirmed Reading IPP (band must render)
    DECLARE @StudentNumber BIGINT =
        (SELECT TOP 1 m.StudentNumber
         FROM SectionRosterMembership m
         INNER JOIN DimAssessmentWindow w ON w.AssessmentWindowID = m.AssessmentWindowID
                                         AND w.AssessmentType = 'Reading'
         WHERE m.SchoolID = '0079' AND m.Grade = '4'
           AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading f
                           WHERE f.StudentNumber = m.StudentNumber)
           AND NOT EXISTS (SELECT 1 FROM FactStudentIPP i
                           INNER JOIN DimStudent ds2 ON ds2.StudentKey = i.StudentKey
                           WHERE ds2.StudentNumber = m.StudentNumber
                             AND i.Subject = 'Reading' AND i.IsCurrent = 1
                             AND (i.IsIPP IS NULL OR i.IsIPP = 1))
         ORDER BY m.StudentNumber);

    DECLARE @StudentKey BIGINT =
        (SELECT StudentKey FROM DimStudent WHERE StudentNumber = @StudentNumber AND IsCurrent = 1);
    DECLARE @StaffKey BIGINT =
        (SELECT StaffKey FROM DimStaff WHERE Email = 'analyst.region@tcrce.ca' AND IsCurrent = 1);
    DECLARE @Now DATETIME2(0) = GETDATE();

    IF @WindowId IS NULL OR @ScaleId IS NULL OR @StudentNumber IS NULL OR @StaffKey IS NULL
    BEGIN
        SELECT 'ABORT - a lookup failed; nothing changed.' AS Result,
               @WindowId AS JuneWindow, @ScaleId AS ScaleM,
               @StudentNumber AS StudentNumber, @StaffKey AS StaffKey;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentReading (
            StudentKey, StudentNumber, AssessmentWindowID, ReadingScaleID, ReadingDelta,
            LevelCode, ExpectedMinLevelCode, ExpectedMaxLevelCode,
            AssessmentDate, EnteredByStaffKey, SubmissionTimestamp, LastUpdated
        )
        VALUES
            (@StudentKey, @StudentNumber, @WindowId, @ScaleId, 0, 'M', NULL, NULL,
             '2026-06-15', @StaffKey, @Now, @Now);

        INSERT INTO FactSubmissionAudit (RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated)
        VALUES ('Seed', 'DevSeed', @Marker, @Now, 'Accepted',
                CONCAT('Prior-year-only probe | StudentNumber=', CAST(@StudentNumber AS VARCHAR(20)),
                       ' | EN level M | window ', CAST(@WindowId AS VARCHAR(20)), ' (June 2026)'), 1, @Now);

        SELECT CONCAT('Seeded prior-year-only probe: StudentNumber=', CAST(@StudentNumber AS VARCHAR(20)),
                      ' (', s.FirstName, ' ', s.LastName, ', grade ', s.Grade, ', school 0079)',
                      ' - EN level M dated 2026-06-15 in the June 2026 window.') AS Result
        FROM DimStudent s WHERE s.StudentKey = @StudentKey;
    END;
END
