/*******************************************************************************
 * Procedure: usp_MergeSection
 * Purpose: SCD Type 2 reconciliation from Stg_Section into DimSection.
 *          All 8 business attributes are Type 2 triggers — any change to any
 *          of them produces a new versioned row.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout — no row-by-row WHILE loops):
 *   1. TRUNCATE + populate Wrk_Section from Stg_Section JOIN DimStaff with
 *      translations applied (SchoolID padding, TermID/EnrollmentCount/
 *      MaxEnrollment numeric casts, email lowercasing, teacher resolution).
 *      Sections whose primary teacher email cannot be resolved to a current
 *      ActiveFlag=1 DimStaff row are EXCLUDED from Wrk and counted as a
 *      warning. (DimSection.TeacherStaffKey is NOT NULL — landing a section
 *      without a resolved teacher is impossible.)
 *   2. Close out current DimSection rows whose business attributes differ
 *      from the incoming Wrk row (EffectiveEndDate = @EffectiveDate - 1,
 *      IsCurrent = 0).
 *   3. INSERT new versions for two cases at once: NEW sections (no prior
 *      DimSection row) and CHANGED sections (current row was just closed).
 *      After this INSERT, every Wrk row has a current DimSection row.
 *   4. Touch LastUpdated on UNCHANGED current rows so audit can distinguish
 *      "still here, unchanged" from "no longer in import".
 *   5. Close out current DimSection rows whose SectionID is absent from this
 *      import. The PS Sections export is filtered upstream to current-school-
 *      year sections only — absence means the section is no longer in scope
 *      (year ended, section dissolved, etc.). No replacement row is inserted
 *      because the absent state is multi-valued (could be year-end close,
 *      cancellation, merge into another section); IsCurrent=1 filters
 *      everywhere already exclude it. Same close-only semantic as DimStudent.
 *   6. Append one summary row to FactSubmissionAudit.
 *
 * Type 2 trigger fields (all 8 business attributes):
 *   SchoolID, TermID, CourseCode, SectionNumber, CourseName, EnrollmentCount,
 *   MaxEnrollment, TeacherStaffKey
 *
 * Change detection: NULL-safe via SELECT...EXCEPT...SELECT subquery.
 *
 * EnrollmentCount churn warning: this field versions DimSection whenever
 * student enrollments shift, so DimSection accumulates versions throughout
 * the school year. Acceptable at pilot volume. FactSectionTeachers does NOT
 * cascade off DimSection (it keys on SectionID directly), so high-frequency
 * versioning here is contained.
 *
 * TeacherStaffKey volatility: a teacher's DimStaff row versioning (e.g. from
 * a name correction or HomeSchool change) produces a new StaffKey, which
 * means w.TeacherStaffKey will differ from d.TeacherStaffKey on the next
 * section ingest, triggering a section version. This is the documented
 * trade-off of the all-Type-2 policy applied to a denormalized snapshot key.
 * Sections will accumulate versions for cosmetic teacher attribute changes;
 * RLS uses FactSectionTeachers (keyed on TeacherEmail directly), so this
 * doesn't affect access control.
 *
 * Translation rules:
 *   SchoolID:       LEFT-PAD with zeros to 4 chars (PS strips leading zeros)
 *   TermID:         CAST AS INT
 *   EnrollmentCount, MaxEnrollment: NULLIF '' -> NULL, else CAST AS INT
 *   Email_Addr:     LOWER() (matches DimStaff business key)
 *   CourseCode, SectionNumber, CourseName: NULLIF '' -> NULL
 *
 * Teacher resolution: INNER JOIN DimStaff on lowercased email + IsCurrent=1
 * + ActiveFlag=1. Sections whose teacher is not in that subset are dropped
 * from Wrk. The unresolved count is computed via a separate LEFT JOIN before
 * the INNER JOIN INSERT.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill or
 * point-in-time replay. Used for both EffectiveStartDate of new versions and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed-out versions.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeSection
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @StgRowCount         INT = 0;
    DECLARE @WrkRowCount         INT = 0;
    DECLARE @UnresolvedTeachers  INT = 0;   -- Stg sections whose teacher email did not resolve to a current ActiveFlag=1 DimStaff row
    DECLARE @InsertedNew         INT = 0;   -- New sections (no prior row)
    DECLARE @InsertedVersion     INT = 0;   -- Existing sections with at least one Type 2 field change
    DECLARE @ClosedRows          INT = 0;   -- Current rows closed by this run (== InsertedVersion)
    DECLARE @TouchedRows         INT = 0;   -- Existing sections unchanged this run (LastUpdated only)
    DECLARE @MissingClosed       INT = 0;   -- Currently-active sections in DimSection absent from this import

    SELECT @StgRowCount = COUNT(*) FROM Stg_Section;

    -- ------------------------------------------------------------------------
    -- Step 1: Materialize the typed working set with all translations applied.
    -- INNER JOIN DimStaff filters out sections whose teacher email cannot be
    -- resolved. The unresolved count is captured separately for audit.
    -- ------------------------------------------------------------------------
    SELECT @UnresolvedTeachers = COUNT(*)
    FROM Stg_Section s
    LEFT JOIN DimStaff t
           ON t.Email = LOWER(s.Email_Addr)
          AND t.IsCurrent = 1
          AND t.ActiveFlag = 1
    WHERE t.StaffKey IS NULL;

    TRUNCATE TABLE Wrk_Section;

    INSERT INTO Wrk_Section (
        SectionID, SchoolID, TermID, CourseCode, SectionNumber, CourseName,
        EnrollmentCount, MaxEnrollment, TeacherEmail, TeacherStaffKey,
        SourceSystemID
    )
    SELECT
        s.ID                                                        AS SectionID,
        RIGHT('0000' + s.SchoolID, 4)                               AS SchoolID,
        CAST(s.TermID AS INT)                                       AS TermID,
        NULLIF(s.Course_Number, '')                                 AS CourseCode,
        NULLIF(s.Section_Number, '')                                AS SectionNumber,
        NULLIF(s.course_name, '')                                   AS CourseName,
        CASE WHEN NULLIF(s.No_of_students, '') IS NULL THEN NULL
             ELSE CAST(s.No_of_students AS INT) END                 AS EnrollmentCount,
        CASE WHEN NULLIF(s.MaxEnrollment, '') IS NULL THEN NULL
             ELSE CAST(s.MaxEnrollment AS INT) END                  AS MaxEnrollment,
        LOWER(s.Email_Addr)                                         AS TeacherEmail,
        t.StaffKey                                                  AS TeacherStaffKey,
        s.ID                                                        AS SourceSystemID
    FROM Stg_Section s
    INNER JOIN DimStaff t
            ON t.Email = LOWER(s.Email_Addr)
           AND t.IsCurrent = 1
           AND t.ActiveFlag = 1;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close out current DimSection rows whose business attributes
    -- differ from the incoming Wrk row. EXCEPT is NULL-safe.
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection d
    INNER JOIN Wrk_Section w
            ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND EXISTS (
          SELECT w.SchoolID, w.TermID, w.CourseCode, w.SectionNumber,
                 w.CourseName, w.EnrollmentCount, w.MaxEnrollment,
                 w.TeacherStaffKey
          EXCEPT
          SELECT d.SchoolID, d.TermID, d.CourseCode, d.SectionNumber,
                 d.CourseName, d.EnrollmentCount, d.MaxEnrollment,
                 d.TeacherStaffKey
      );

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new versions. Two populations covered in one pass:
    --   (a) NEW: SectionID not present in DimSection at all.
    --   (b) CHANGED: SectionID present, but no current row remains for it
    --       (because Step 2 just closed the prior current row).
    -- After this INSERT, every Wrk row has a current DimSection row.
    -- ------------------------------------------------------------------------
    INSERT INTO DimSection (
        SectionID, SchoolID, TermID, CourseCode, SectionNumber, CourseName,
        EnrollmentCount, MaxEnrollment, TeacherStaffKey,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.SectionID, w.SchoolID, w.TermID, w.CourseCode, w.SectionNumber, w.CourseName,
        w.EnrollmentCount, w.MaxEnrollment, w.TeacherStaffKey,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_Section w
    WHERE NOT EXISTS (
        SELECT 1 FROM DimSection d
        WHERE d.SectionID = w.SectionID
          AND d.IsCurrent = 1
    );

    SET @InsertedNew = @@ROWCOUNT - @ClosedRows;
    SET @InsertedVersion = @ClosedRows;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows (everything in Wrk
    -- whose SectionID maps to a current DimSection row that was NOT just
    -- inserted — i.e. predates this run).
    -- ------------------------------------------------------------------------
    UPDATE d
    SET LastUpdated = GETDATE()
    FROM DimSection d
    INNER JOIN Wrk_Section w
            ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND d.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Close out current DimSection rows whose SectionID is absent
    -- from this import. The PS export is filtered to current school-year
    -- sections — absence means out of scope. Close-only, no replacement
    -- (multi-valued absent state).
    -- ------------------------------------------------------------------------
    UPDATE d
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM DimSection d
    LEFT JOIN Wrk_Section w
           ON w.SectionID = d.SectionID
    WHERE d.IsCurrent = 1
      AND w.SectionID IS NULL;

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
        CASE WHEN @UnresolvedTeachers > 0 THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeSection: ',
            CAST(@StgRowCount      AS VARCHAR(20)), ' staged | ',
            CAST(@WrkRowCount      AS VARCHAR(20)), ' resolved | ',
            CAST(@InsertedNew      AS VARCHAR(20)), ' new | ',
            CAST(@InsertedVersion  AS VARCHAR(20)), ' versioned (',
            CAST(@ClosedRows       AS VARCHAR(20)), ' closed) | ',
            CAST(@TouchedRows      AS VARCHAR(20)), ' unchanged | ',
            CAST(@MissingClosed    AS VARCHAR(20)), ' deactivated (missing from import)',
            CASE WHEN @UnresolvedTeachers > 0
                 THEN CONCAT(' | [WARN: ', CAST(@UnresolvedTeachers AS VARCHAR(20)), ' sections excluded — primary teacher email did not resolve to a current active DimStaff row]')
                 ELSE '' END
        ),
        @StgRowCount,
        GETDATE()
    );
END;
