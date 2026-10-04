/*───────────────────────────────────────────────────────────────────────────
  Table: dbo.IngestRunLog
  Purpose: Running log of ingest cycles. Per cycle: one Started row, one row per
           file (Loaded), and one terminal Completed (or a controlled Failed for
           the DQ gate). Captures WHO ran it (CallerUPN), from WHERE (Source), WHEN
           (CycleStart / LoggedAt), and HOW MANY rows loaded per file (RowsLoaded).
  SCD: none — append-only audit log.
  Created: 2026-10-04
  Region: Canada East (PIIDPA compliant)

  Column value sets:
    Source : App  (via usp_TriggerIngestCycle)  |  FabricSQL  (direct EXEC)
    Phase  : Cycle | Load
    Topic  : students | staff | sections | enrollments | section-teachers   (Load rows; NULL on Cycle rows)
    Status : Started | Loaded | Completed | Failed                          (Skipped no longer used)

  Failure semantics: Fabric Warehouse has no TRY/CATCH, so a failed COPY INTO
  aborts the cycle. A failed run shows a Started row + the Load rows that
  completed but NO terminal row — that absence (plus the last Load topic) tells
  you it died and where. The DQ gate is a controlled THROW, so it logs Failed.

  NON-DESTRUCTIVE: guarded create — safe to re-run; it will NOT drop an existing
  log. Deploy order: this table FIRST, then usp_RunFullIngestCycle (it INSERTs
  here, reached via ownership chaining from usp_TriggerIngestCycle — same pattern
  as FactSubmissionAudit, so no direct SP grant is needed).
───────────────────────────────────────────────────────────────────────────*/

IF OBJECT_ID('dbo.IngestRunLog', 'U') IS NULL
    EXEC('
        CREATE TABLE dbo.IngestRunLog (
            IngestRunLogID BIGINT IDENTITY,
            CycleStart     DATETIME2(0)  NOT NULL,   -- set ONCE per cycle (GETDATE at proc start); the collation key for a run (runs are serialized, so second precision never collides)
            LoggedAt       DATETIME2(0)  NOT NULL,   -- when THIS row was written; orders steps within a run
            CallerUPN      VARCHAR(255)  NULL,
            Source         VARCHAR(20)   NOT NULL,
            Phase          VARCHAR(20)   NOT NULL,
            Topic          VARCHAR(30)   NULL,
            RowsLoaded     INT           NULL,
            Status         VARCHAR(20)   NOT NULL,
            Message        VARCHAR(4000) NULL,
            LastUpdated    DATETIME2(0)  NOT NULL
        );
    ');
GO
