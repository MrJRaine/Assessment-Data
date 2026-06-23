/*******************************************************************************
 * Procedure: usp_MergeStudent
 * Purpose: SCD Type 2 reconciliation from Stg_Student into DimStudent.
 *          All 14 business attributes are Type 2 triggers — any change to
 *          any of them produces a new versioned row. Also reconciles
 *          FactStudentIPP rows for students whose DimStudent.IPP = 1, creating
 *          NULL-status placeholders that teachers/admins resolve via scrIPP.
 * Created: 2026-04-30
 * Modified: 2026-05-13 — Grade_Level '13' -> 'RG' translation for Step 18
 *           2026-05-26 — Step 6 added: FactStudentIPP reconciliation. Audit
 *                       renumbered to Step 7 and gained two IPP counters.
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
 *   6. Reconcile FactStudentIPP against the current DimStudent state. For
 *      students with DimStudent.IPP = 1, ensure the applicable
 *      (Subject, ProgramFamily) triples have a current FactStudentIPP row.
 *      Close rows whose triple is no longer applicable (student lost IPP,
 *      changed program, dropped below grade 3 as an FI student, or was
 *      deactivated). New rows are inserted with IsIPP = NULL (unresolved
 *      gate) and ChangedBy = 'system'; teachers/admins flip these via
 *      usp_UpsertStudentIPP from scrIPP / scrRosterGrid.
 *
 *      Applicability rules:
 *        English-program student:           {Reading, Writing} x {English}
 *        French-Immersion student (all):    {Reading, Writing} x {French Immersion}
 *        French-Immersion grade >= 3:       additionally {Reading, Writing} x {English}
 *   7. Append one summary row to FactSubmissionAudit.
 *
 * Change detection: a row counts as CHANGED if any of the 14 Type 2 trigger
 * fields differs. NULL-safe comparison via SELECT...EXCEPT...SELECT subquery
 * (EXCEPT treats NULLs as equal — much cleaner than 14× ISNULL/CASE pairs).
 *
 * Translation rules (locked in 2026-04-29 against actual PS export;
 *                    Grade_Level '13' -> 'RG' added 2026-05-13 for Step 18):
 *   Grade_Level:  '0' -> 'P', '-1' -> 'PP', '13' -> 'RG', else verbatim string
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

DROP PROCEDURE IF EXISTS usp_MergeStudent;
GO

CREATE PROCEDURE usp_MergeStudent
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);

    DECLARE @RunStart        DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount     INT = 0;
    DECLARE @InsertedNew     INT = 0;   -- New students (no prior row)
    DECLARE @InsertedVersion INT = 0;   -- Existing students with at least one Type 2 field change
    DECLARE @ClosedRows      INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows     INT = 0;   -- Existing students unchanged this run (LastUpdated only)
    DECLARE @MissingClosed   INT = 0;   -- Currently-active students in DimStudent absent from this import
    DECLARE @IPPRowsClosed   INT = 0;   -- FactStudentIPP rows closed because no longer applicable
    DECLARE @IPPRowsCreated  INT = 0;   -- FactStudentIPP rows inserted with IsIPP = NULL
    DECLARE @SameDayUpdated  INT = 0;   -- Current rows updated IN PLACE (same-day correction; no new version)

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
             WHEN '13' THEN 'RG'
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
    -- Step 2: Close out current DimStudent rows whose business attributes differ
    -- from the incoming Wrk row AND that started on an EARLIER day (normal SCD
    -- versioning). EXCEPT is NULL-safe. Same-day changes are handled in Step 2b:
    -- a close+insert on the same day the current row was created would set
    -- EffectiveEndDate = @EffectiveDate-1 < EffectiveStartDate (reversed window)
    -- AND leave two same-key rows sharing today (self-overlap) — both DQ violations.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate
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
    -- Step 2b: SAME-DAY correction. Current row was created TODAY
    -- (EffectiveStartDate = @EffectiveDate), so update it IN PLACE rather than
    -- close+insert — no spurious 0-day version, no reversed/overlapping window,
    -- and StudentKey is preserved so FactEnrollment / FactAssessmentReading /
    -- FactStudentIPP references stay valid. (A re-run of today's ingest after a
    -- correction collapses into today's row, which is the right semantics.)
    -- ------------------------------------------------------------------------
    UPDATE d
    SET FirstName = w.FirstName, MiddleName = w.MiddleName, LastName = w.LastName,
        DateOfBirth = w.DateOfBirth, Grade = w.Grade, SchoolID = w.SchoolID,
        ProgramCode = w.ProgramCode, EnrollStatus = w.EnrollStatus, Homeroom = w.Homeroom,
        Gender = w.Gender, SelfIDAfrican = w.SelfIDAfrican, SelfIDIndigenous = w.SelfIDIndigenous,
        IPP = w.IPP, Adap = w.Adap, LastUpdated = GETDATE()
    FROM DimStudent d
    INNER JOIN Wrk_Student w
            ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate = @EffectiveDate
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

    SET @SameDayUpdated = @@ROWCOUNT;

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
    -- Step 4: Touch LastUpdated on unchanged current rows.
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
    -- Step 5: Close out current DimStudent rows absent from this import. EndDate is
    -- guarded so a row created TODAY but already missing (same-day add-then-remove)
    -- closes as a valid 0-day window (End = Start) rather than a reversed one.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = CASE WHEN d.EffectiveStartDate > DATEADD(DAY, -1, @EffectiveDate)
                                THEN d.EffectiveStartDate
                                ELSE DATEADD(DAY, -1, @EffectiveDate) END,
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimStudent d
    LEFT JOIN Wrk_Student w
           ON w.StudentNumber = d.StudentNumber
    WHERE d.IsCurrent = 1
      AND w.StudentNumber IS NULL;

    SET @MissingClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6a: Close FactStudentIPP rows whose (StudentKey, Subject,
    -- ProgramFamily) triple is no longer in the "expected current" set.
    -- The expected set is derived live from the post-step-5 DimStudent state,
    -- restricted to IsCurrent=1 students with IPP=1, applying the
    -- program/grade applicability rules.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        -- English-program students: {Reading, Writing} x {English}
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'English'

        UNION ALL

        -- French-Immersion students (any grade): {Reading, Writing} x {French Immersion}
        SELECT s.StudentKey, sub.Subject, CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'

        UNION ALL

        -- French-Immersion students grade >= 3: additionally {Reading, Writing} x {English}
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
    )
    UPDATE fsi
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactStudentIPP fsi
    WHERE fsi.IsCurrent = 1
      AND NOT EXISTS (
          SELECT 1 FROM ExpectedIPP e
          WHERE e.StudentKey    = fsi.StudentKey
            AND e.Subject       = fsi.Subject
            AND e.ProgramFamily = fsi.ProgramFamily
      );

    SET @IPPRowsClosed = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 6b: Insert new FactStudentIPP rows (IsIPP = NULL) for every
    -- (StudentKey, Subject, ProgramFamily) in the expected set that does not
    -- yet have a current row. ChangedBy = 'system' marks these as auto-created.
    -- ------------------------------------------------------------------------
    ;WITH ExpectedIPP AS (
        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50)) AS ProgramFamily
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'English'

        UNION ALL

        SELECT s.StudentKey, sub.Subject, CAST('French Immersion' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'

        UNION ALL

        SELECT s.StudentKey, sub.Subject, CAST('English' AS VARCHAR(50))
        FROM   DimStudent s
        JOIN   DimProgram p ON p.ProgramCode = s.ProgramCode
        JOIN   DimGrade   g ON g.GradeCode   = s.Grade
        CROSS JOIN (VALUES ('Reading'), ('Writing')) AS sub(Subject)
        WHERE  s.IsCurrent = 1
          AND  s.IPP       = 1
          AND  p.ProgramFamily = 'French Immersion'
          AND  g.GradeOrder >= 3
    )
    INSERT INTO FactStudentIPP (
        StudentKey, Subject, ProgramFamily, IsIPP,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, ChangedBy, LastUpdated
    )
    SELECT
        e.StudentKey, e.Subject, e.ProgramFamily, NULL,
        @EffectiveDate, NULL, 1, 'system', GETDATE()
    FROM ExpectedIPP e
    WHERE NOT EXISTS (
        SELECT 1 FROM FactStudentIPP fsi
        WHERE fsi.StudentKey    = e.StudentKey
          AND fsi.Subject       = e.Subject
          AND fsi.ProgramFamily = e.ProgramFamily
          AND fsi.IsCurrent     = 1
    );

    SET @IPPRowsCreated = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 7: Audit. One summary row per run.
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
            CAST(@SameDayUpdated  AS VARCHAR(20)), ' same-day in-place | ',
            CAST(@TouchedRows     AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed   AS VARCHAR(20)), ' deactivated (missing from import)',
            ' || FactStudentIPP: ',
            CAST(@IPPRowsCreated  AS VARCHAR(20)), ' rows created (NULL) | ',
            CAST(@IPPRowsClosed   AS VARCHAR(20)), ' rows closed (no longer applicable)'
        ),
        @StgRowCount,
        GETDATE()
    );
END;
GO
