/*******************************************************************************
 * Script: fix_enrollment_close_dates_2026-10-30
 * Purpose: One-time repair for defensively-closed enrollments whose EndDate was
 *          left at PS's SCHEDULED exit date (term/year end). usp_MergeEnrollment
 *          step 5 set ActiveFlag=0 but never touched EndDate, so the roster-
 *          membership date-overlap (deliberately ActiveFlag-blind since
 *          2026-10-13) carried departed students into every later cycle through
 *          term end. The proc is fixed as of 2026-10-30 (EndDate capped at the
 *          closing ingest's @EffectiveDate); this script repairs the rows closed
 *          BEFORE that fix, then rebuilds roster membership so rosters reflect
 *          it immediately.
 *
 * Repair rule: ActiveFlag = 0 AND (EndDate IS NULL OR EndDate > the Atlantic
 *          date of LastUpdated)  ->  EndDate = the Atlantic date of LastUpdated.
 *          A step-5-closed row is absent from every later import, so its
 *          LastUpdated froze at the closing ingest — the best available
 *          "we learned they were gone" date. The guard EXCLUDES closed rows
 *          whose EndDate is already past (real PS exit dates — rows still in
 *          PS's rolling export keep getting LastUpdated touched, so a blanket
 *          overwrite would drag correct history forward).
 *
 * Reads:  FactEnrollment.
 * Writes: FactEnrollment (EndDate, LastUpdated) on matching rows only;
 *         then EXEC usp_RebuildRosterMembership (TRUNCATE+INSERT of
 *         SectionRosterMembership / TeacherRosterMembership / StudentExpectedAssessment).
 *
 * Idempotent: after the UPDATE the guard no longer matches the repaired rows.
 * Run on DEV first, then LIVE (the bad rows are on live).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ---------------------------------------------------------------------------
-- PART 1 — PREVIEW (read-only). RowsToFix = how many rows PART 2 will change,
-- split by NULL vs future EndDate, with the close-date range for sanity.
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*)                                                           AS RowsToFix,
    SUM(CASE WHEN EndDate IS NULL THEN 1 ELSE 0 END)                   AS NullEndDate,
    SUM(CASE WHEN EndDate IS NOT NULL THEN 1 ELSE 0 END)               AS FutureEndDate,
    MIN(CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)) AS EarliestCloseDate,
    MAX(CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)) AS LatestCloseDate
FROM FactEnrollment
WHERE ActiveFlag = 0
  AND (EndDate IS NULL
       OR EndDate > CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE));

-- ---------------------------------------------------------------------------
-- PART 2 — REPAIR. EndDate <- the Atlantic date of the closing ingest.
-- ---------------------------------------------------------------------------
UPDATE FactEnrollment
SET EndDate     = CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE),
    LastUpdated = GETDATE()
WHERE ActiveFlag = 0
  AND (EndDate IS NULL
       OR EndDate > CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE));

-- ---------------------------------------------------------------------------
-- PART 3 — REBUILD the materialized rosters so the fix is visible now
-- (otherwise it waits for the next ingest).
-- ---------------------------------------------------------------------------
EXEC dbo.usp_RebuildRosterMembership;

-- ---------------------------------------------------------------------------
-- PART 4 — VERIFY: both counts must be 0.
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM FactEnrollment
     WHERE ActiveFlag = 0
       AND (EndDate IS NULL
            OR EndDate > CAST(LastUpdated AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE))) AS RemainingBadRows,
    (SELECT COUNT(*) FROM FactEnrollment
     WHERE ActiveFlag = 0 AND EndDate IS NULL)                         AS RemainingNullEndDates;
