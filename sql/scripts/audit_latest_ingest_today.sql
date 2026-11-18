/*******************************************************************************
 * Script: audit_latest_ingest_today  (READ-ONLY, reusable — no values to edit)
 * Purpose: Pull the full audit of TODAY's most recent ingest cycle:
 *   1. The run's IngestRunLog rows — who ran it, from where, each file's
 *      row count, and the terminal Completed/Failed row (a missing terminal
 *      row = the cycle died at the last Loaded topic shown).
 *   2. The merge-proc summaries written to FactSubmissionAudit during that
 *      run's window (per-proc staged/inserted/closed counts + warnings,
 *      maintenance-migration notes).
 * "Today" = Atlantic date. Timestamps are stored UTC; shown both raw (UTC)
 * and converted to Atlantic.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DECLARE @CycleStart DATETIME2(0);
SELECT @CycleStart = MAX(CycleStart)
FROM IngestRunLog
WHERE CAST(CycleStart AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE)
      = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

-- The run's window end: its last logged step (plus a 2-minute tail for the
-- final merge summaries), capped at now.
DECLARE @WindowEnd DATETIME2(0);
SELECT @WindowEnd = DATEADD(MINUTE, 2, MAX(LoggedAt))
FROM IngestRunLog
WHERE CycleStart = @CycleStart;

-- ---------------------------------------------------------------------------
-- 1) The run itself (empty result = NO ingest has run today)
-- ---------------------------------------------------------------------------
SELECT
    CAST(l.CycleStart AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS CycleStartAtlantic,
    CAST(l.LoggedAt   AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS LoggedAtAtlantic,
    l.CallerUPN, l.Source, l.Phase, l.Topic, l.RowsLoaded, l.Status, l.Message
FROM IngestRunLog l
WHERE l.CycleStart = @CycleStart
ORDER BY l.LoggedAt, l.IngestRunLogID;

-- ---------------------------------------------------------------------------
-- 2) Merge summaries + notes written during the run (per-proc counters,
--    DQ/warning text, maintenance migrations)
-- ---------------------------------------------------------------------------
SELECT
    CAST(a.SubmissionTimestamp AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) AS SubmittedAtlantic,
    a.RecordType, a.Source, a.SubmittedBy, a.Status, a.RecordCount, a.Message
FROM FactSubmissionAudit a
WHERE a.SubmissionTimestamp >= @CycleStart
  AND a.SubmissionTimestamp <= COALESCE(@WindowEnd, GETDATE())
ORDER BY a.SubmissionTimestamp, a.LastUpdated;
