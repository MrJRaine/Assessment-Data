/*******************************************************************************
 * Procedure: usp_MergeStudent
 * Purpose: SCD Type 2 reconciliation from Stg_Student into DimStudent.
 *          All 14 business attributes are Type 2 triggers — any change to
 *          any of them produces a new versioned row.
 * Created: 2026-04-30
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout — no row-by-row WHILE loops):
 *   1. TRUNCATE + populate Wrk_Student from Stg_Student with translations
 *      applied (Grade, SchoolID padding, DOB parse, boolean normalization,
 *      numeric casts).
 *   2. Close out current DimStudent rows whose business attributes differ
 *      from the incoming Wrk row (EffectiveEndDate = @EffectiveDate - 1,
 *      IsCurrent = 0).
 *   3. INSERT new versions for two cases at once: NEW students (no prior
 *      DimStudent row) and CHANGED students (current row was just closed).
 *   4. Touch LastUpdated on UNCHANGED current rows so audit can distinguish
 *      "still here, unchanged" from "no longer in import".
 *   5. Close out current DimStudent rows whose StudentNumber is absent from
 *      this import. The PS Students export is filtered upstream to
 *      Enroll_Status IN (0, -1) (Active + Pre-Enrolled) — so absence from
 *      the export means the student is no longer in either of those states.
 *      No replacement row is inserted: we don't know which absent state
 *      (Inactive=2 or Graduated=3) they're in, and IsCurrent=1 filters
 *      everywhere already exclude them. Returning students get a fresh
 *      current row from Step 3 on the next ingest.
 *   6. Append one summary row to FactSubmissionAudit.
 *
 * Change detection: a row counts as CHANGED if any of the 14 Type 2 trigger
 * fields differs. NULL-safe comparison via SELECT...EXCEPT...SELECT subquery
 * (EXCEPT treats NULLs as equal — much cleaner than 14× ISNULL/CASE pairs).
 *
 * Translation rules (locked in 2026-04-29 against actual PS export):
 *   Grade_Level:  '0' -> 'P', '-1' -> 'PP', else verbatim string
 *   SchoolID:     LEFT-PAD with zeros to 4 chars (PS strips leading zeros)
 *   DOB:          MM/DD/YYYY parsed via CONVERT(DATE, val, 101); '' -> NULL
 *   SelfIDAfrican (NS_AssigndIdentity_African):
 *                 'Yes' -> 1, '' -> NULL
 *   SelfIDIndigenous (NS_aboriginal):
 *                 '1' -> 1, '2' -> 0, '' -> NULL
 *   CurrentIPP / CurrentAdap:
 *                 'Y' -> 1, 'N' -> 0, '' -> NULL
 *   EnrollStatus: cast Enroll_Status string to INT
 *   StudentNumber: cast Student_Number string to BIGINT
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill or
 * point-in-time replay. Used for both EffectiveStartDate of new versions and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeStudent
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AS DATE);

    DECLARE @RunStart        DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount     INT = 0;
    DECLARE @InsertedNew     INT = 0;   -- New students (no prior row)
    DECLARE @InsertedVersion INT = 0;   -- Existing students with at least one Type 2 field change
    DECLARE @ClosedRows      INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows     INT = 0;   -- Existing students unchanged this run (LastUpdated only)
    DECLARE @MissingClosed   INT = 0;   -- Currently-active students in DimStudent absent from this import (closed, no replacement)

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations applied.
    -- ------------------------------------------------------------------------
    TRUNCATE TABLE Wrk_Student;

    INSERT INTO Wrk_Student (
        StudentNumber, SourceSystemID, FirstName, MiddleName, LastName,
        DateOfBirth, Grade, SchoolID, ProgramCode, EnrollStatus,
        Homeroom, Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap
    )
    SELECT
        CAST(s.Student_Number AS BIGINT)                            AS StudentNumber,
        s.ID                                                        AS SourceSystemID,
        s.First_Name                                                AS FirstName,
        NULLIF(s.Middle_Name, '')                                   AS MiddleName,
        s.Last_Name                                                 AS LastName,
        CASE WHEN NULLIF(s.DOB, '') IS NULL THEN NULL
             ELSE CONVERT(DATE, s.DOB, 101) END                     AS DateOfBirth,
        CASE s.Grade_Level
             WHEN '0'  THEN 'P'
             WHEN '-1' THEN 'PP'
             ELSE s.Grade_Level END                                 AS Grade,
        RIGHT('0000' + s.SchoolID, 4)                               AS SchoolID,
        s.NS_Program                                                AS ProgramCode,
        CAST(s.Enroll_Status AS INT)                                AS EnrollStatus,
        NULLIF(s.Home_Room, '')                                     AS Homeroom,
        s.Gender                                                    AS Gender,
        CASE s.NS_AssigndIdentity_African
             WHEN 'Yes' THEN CAST(1 AS BIT)
             WHEN ''    THEN NULL
             ELSE NULL END                                          AS SelfIDAfrican,
        CASE s.NS_aboriginal
             WHEN '1' THEN CAST(1 AS BIT)
             WHEN '2' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS SelfIDIndigenous,
        CASE s.CurrentIPP
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS IPP,
        CASE s.CurrentAdap
             WHEN 'Y' THEN CAST(1 AS BIT)
             WHEN 'N' THEN CAST(0 AS BIT)
             WHEN ''  THEN NULL
             ELSE NULL END                                          AS Adap
    FROM Stg_Student s;

    SELECT @StgRowCount = COUNT(*) FROM Wrk_Student;

    -- ------------------------------------------------------------------------
    -- Step 2: Close out current DimStudent rows whose business attributes
    -- differ from the incoming Wrk row. EXCEPT is NULL-safe.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND EXISTS (
          SELECT w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
                 w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus,
                 w.Homeroom, w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous,
                 w.IPP, w.Adap
          EXCEPT
          SELECT d.FirstName, d.MiddleName, d.LastName, d.DateOfBirth,
                 d.Grade, d.SchoolID, d.ProgramCode, d.EnrollStatus,
                 d.Homeroom, d.Gender, d.SelfIDAfrican, d.SelfIDIndigenous,
                 d.IPP, d.Adap
      );

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new versions. Two populations covered in one pass:
    --   (a) NEW: StudentNumber not present in DimStudent at all.
    --   (b) CHANGED: StudentNumber present, but no current row remains for it
    --       (because Step 2 just closed the prior current row).
    -- After this INSERT, every Wrk row has a current DimStudent row.
    -- ------------------------------------------------------------------------
    INSERT INTO DimStudent (
        StudentNumber, FirstName, MiddleName, LastName, DateOfBirth,
        Grade, SchoolID, ProgramCode, EnrollStatus, Homeroom,
        Gender, SelfIDAfrican, SelfIDIndigenous, IPP, Adap,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.StudentNumber, w.FirstName, w.MiddleName, w.LastName, w.DateOfBirth,
        w.Grade, w.SchoolID, w.ProgramCode, w.EnrollStatus, w.Homeroom,
        w.Gender, w.SelfIDAfrican, w.SelfIDIndigenous, w.IPP, w.Adap,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_Student w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimStudent d
        WHERE d.StudentNumber = w.StudentNumber
          AND d.IsCurrent = 1
    );

    SET @InsertedNew = @@ROWCOUNT - @ClosedRows;
    SET @InsertedVersion = @ClosedRows;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows (everything in Wrk
    -- whose StudentNumber maps to a current DimStudent row that was NOT just
    -- inserted — i.e. predates this run).
    -- ------------------------------------------------------------------------
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close out current DimStudent rows whose StudentNumber is absent
    -- from this import. The PS export is pre-filtered to Enroll_Status IN
    -- (0, -1) (Active + Pre-Enrolled), so absence == no longer in either of
    -- those states. No replacement row is inserted because we don't know
    -- which absent state (Inactive=2 or Graduated=3) the student moved to.
    -- Returning students get a fresh row via Step 3 on the next ingest.
    --
    -- Anti-join uses LEFT JOIN with NULL guard rather than NOT EXISTS so the
    -- @@ROWCOUNT after this UPDATE is reliable across all T-SQL flavours.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    LEFT JOIN Wrk_Student w
           ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND w.StudentNumber IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6: Audit. One summary row per run.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message,
        RecordCount, LastUpdated
    )
    VALUES (
        'CSVImport',
        'PowerSchool',
        'system',
        @RunStart,
        'Accepted',
        CONCAT(
            'usp_MergeStudent: ',
            CAST(@StgRowCount     AS VARCHAR(20)), ' staged | ',
            CAST(@InsertedNew     AS VARCHAR(20)), ' new | ',
            CAST(@InsertedVersion AS VARCHAR(20)), ' versioned (',
            CAST(@ClosedRows      AS VARCHAR(20)), ' closed) | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)'
        ),
        @StgRowCount,
        GETDATE()
    );
END;
