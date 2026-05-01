/*******************************************************************************
 * Procedure: usp_YearEndCloseOut
 * Purpose: Scheduled close-out for a completed school year. Closes any rows
 *          that are still flagged active/current for sections in the closing
 *          school year (or earlier). Independent of the regular ingest
 *          merges — runs as a standalone job after the school year ends.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Why this proc exists:
 *   The regular ingest's anti-join logic naturally closes out old sections,
 *   FactSectionTeachers triples, and active FactEnrollment rows when the
 *   NEXT school year's data lands (typically September). That leaves a
 *   Jun-Aug window where Spring rosters are still flagged current/active
 *   and surface in Power Apps and Power BI reports. Year-end close-out
 *   removes that gap by running on (or shortly after) June 30.
 *
 * What it closes (three tables, one transaction):
 *   1. FactEnrollment — currently-active rows (ActiveFlag = 1) whose
 *      SectionKey resolves to a DimSection row in the closing year.
 *      Sets ActiveFlag = 0 and fills EndDate when NULL using the section's
 *      canonical term-end date (DimTerm-derived). Existing non-NULL EndDate
 *      values are preserved.
 *   2. FactSectionTeachers — currently-active triples (IsCurrent = 1)
 *      whose SectionID belongs to a closing-year section. Closed via
 *      standard SCD Type 2 close pattern (EffectiveEndDate, IsCurrent = 0).
 *      No replacement insert (close-only).
 *   3. DimSection — currently-active rows (IsCurrent = 1) whose TermID
 *      falls in the closing year(s). Standard SCD Type 2 close (close-only).
 *
 * Closing-year scope:
 *   Any DimTerm row with SchoolYearEnd <= @ClosingSchoolYearEnd. Uses <=
 *   rather than = so a re-run that catches a missed prior year still works.
 *   In normal operation only the latest year is in scope.
 *
 * Order of operations:
 *   FactEnrollment first (joins through SectionKey to DimSection regardless
 *   of IsCurrent), then FactSectionTeachers (joins through SectionID), then
 *   DimSection itself. Each step's scope is independent, so the order is
 *   for audit clarity, not correctness. All three steps see the same
 *   pre-close DimSection state because UPDATEs commit at end of statement.
 *
 * Parameters:
 *   @ClosingSchoolYearEnd INT (default NULL):
 *      The SchoolYearEnd value to close (e.g. 2026 for the 2025-2026 year).
 *      If NULL, derived from today's date: if the current month is July or
 *      later, the closing year is the current calendar year (we're after
 *      the June 30 cutoff of the year that just ended); otherwise the
 *      closing year is the previous calendar year. Override only if the
 *      auto-derivation would pick the wrong year (e.g. running a backfill
 *      for a missed prior-year close-out).
 *
 *   @EffectiveDate DATE (default NULL):
 *      Used as the close-out date for SCD Type 2 rows
 *      (EffectiveEndDate = @EffectiveDate - 1 day, new rows would start at
 *      @EffectiveDate but no inserts happen here). Defaults to today.
 *
 * Idempotence:
 *   Safe to re-run. If everything in scope has already been closed, the
 *   UPDATE statements match nothing and counters return 0. Audit row still
 *   gets written with a "no-op" message.
 *
 * SAFETY NOTE:
 *   This proc closes rows en masse based on TermID/SchoolYearEnd. Passing
 *   @ClosingSchoolYearEnd = (current school year) by mistake would close
 *   all currently-active assessment data for the year still in progress.
 *   Job scheduler should pass the value explicitly, derived from a stable
 *   source (e.g. last completed school year per academic calendar table).
 *   Auto-derivation is for ad-hoc admin runs, not scheduled production use.
 *
 * Term-end date used to fill NULL EndDate (when DateLeft was empty in PS):
 *   Year Long  (TermCode 0): June 30 of SchoolYearEnd
 *   Semester 1 (TermCode 1): January 30 of SchoolYearEnd
 *   Semester 2 (TermCode 2): June 30 of SchoolYearEnd
 *   ISO date format used (YYYY-MM-DD via CONVERT style 23) for portability.
 ******************************************************************************/

CREATE PROCEDURE usp_YearEndCloseOut
    @ClosingSchoolYearEnd INT  = NULL,
    @EffectiveDate        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Defaults
    IF @ClosingSchoolYearEnd IS NULL
        SET @ClosingSchoolYearEnd =
            CASE WHEN MONTH(GETDATE()) >= 7 THEN YEAR(GETDATE())
                 ELSE YEAR(GETDATE()) - 1 END;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AS DATE);

    DECLARE @RunStart           DATETIME2(0) = GETDATE();
    DECLARE @EnrollmentsClosed  INT = 0;
    DECLARE @TeachersClosed     INT = 0;
    DECLARE @SectionsClosed     INT = 0;
    DECLARE @SchoolYearLabel    VARCHAR(20) =
        CONCAT(CAST(@ClosingSchoolYearEnd - 1 AS VARCHAR(4)),
               '-',
               CAST(@ClosingSchoolYearEnd     AS VARCHAR(4)));

    -- ------------------------------------------------------------------------
    -- Step 1: Close FactEnrollment rows still active for closing-year sections.
    -- Joins via SectionKey to ANY DimSection version (IsCurrent agnostic) so
    -- enrollments whose section has already versioned still get caught.
    -- EndDate = COALESCE(existing, canonical term-end).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET ActiveFlag  = 0,
        EndDate     = COALESCE(
                          f.EndDate,
                          CONVERT(
                              DATE,
                              CONCAT(
                                  CAST(t.SchoolYearEnd AS VARCHAR(4)),
                                  CASE t.TermCode
                                      WHEN 0 THEN '-06-30'
                                      WHEN 1 THEN '-01-30'
                                      WHEN 2 THEN '-06-30'
                                  END
                              ),
                              23
                          )
                      ),
        LastUpdated = GETDATE()
    FROM FactEnrollment f
    INNER JOIN DimSection sec ON sec.SectionKey = f.SectionKey
    INNER JOIN DimTerm    t   ON t.TermID       = sec.TermID
    WHERE f.ActiveFlag = 1
      AND t.SchoolYearEnd <= @ClosingSchoolYearEnd;

    SET @EnrollmentsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close FactSectionTeachers triples for closing-year sections.
    -- Bridge keys on SectionID (business key, decoupled from DimSection SCD),
    -- so this joins to any DimSection version with that SectionID. Using
    -- EXISTS (not INNER JOIN) avoids fan-out from multiple DimSection
    -- versions of the same section.
    -- ------------------------------------------------------------------------
    UPDATE fst
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactSectionTeachers fst
    WHERE fst.IsCurrent = 1
      AND EXISTS (
          SELECT 1
          FROM DimSection sec
          INNER JOIN DimTerm t ON t.TermID = sec.TermID
          WHERE sec.SectionID = fst.SectionID
            AND t.SchoolYearEnd <= @ClosingSchoolYearEnd
      );

    SET @TeachersClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: Close DimSection rows for closing-year terms. Standard
    -- SCD Type 2 close-only.
    -- ------------------------------------------------------------------------
    UPDATE sec
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection sec
    INNER JOIN DimTerm t ON t.TermID = sec.TermID
    WHERE sec.IsCurrent = 1
      AND t.SchoolYearEnd <= @ClosingSchoolYearEnd;

    SET @SectionsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'YearEndCloseOut',
        'system',
        'system',
        @RunStart,
        'Accepted',
        CONCAT(
            'usp_YearEndCloseOut: closing school year ', @SchoolYearLabel,
            ' (SchoolYearEnd <= ', CAST(@ClosingSchoolYearEnd AS VARCHAR(10)), ') | ',
            CAST(@EnrollmentsClosed AS VARCHAR(20)), ' enrollments closed (ActiveFlag -> 0) | ',
            CAST(@TeachersClosed    AS VARCHAR(20)), ' section-teacher triples closed | ',
            CAST(@SectionsClosed    AS VARCHAR(20)), ' sections closed'
        ),
        @EnrollmentsClosed + @TeachersClosed + @SectionsClosed,
        GETDATE()
    );
END;
