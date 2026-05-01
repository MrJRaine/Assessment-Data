/*******************************************************************************
 * Procedure: usp_MergeSectionTeachers
 * Purpose: Type 2 reconciliation into FactSectionTeachers from the UNION of
 *          Stg_Section (primary teachers) and Stg_CoTeacher (co-teachers).
 *          Independent of DimSection / DimStaff versioning per the
 *          2026-04-28 decoupling decision — the bridge keys on business
 *          keys (SectionID, TeacherEmail) directly.
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 *
 * Pipeline (set-based throughout — no row-by-row WHILE loops):
 *   1. Build Wrk_SectionTeacher from the UNION of:
 *        - Stg_Section primary teacher rows (TeacherRole = 'Primary')
 *        - Stg_CoTeacher rows (TeacherRole normalized — 'Co-teacher' ->
 *          'CoTeacher'; 'Support' / 'Substitute' / others kept verbatim)
 *      Translations:
 *        - Lowercased email (matches DimStaff business key + RLS UPN)
 *        - Empty/whitespace email rows EXCLUDED, counted as warnings
 *        - DISTINCT on (SectionID, TeacherEmail, TeacherRole) for defensive
 *          dedup in case the same triple appears in both source tables
 *      No JOINs — the bridge uses business keys, not surrogates.
 *
 *   2. Close current rows whose triple is missing from Wrk (anti-join):
 *      EffectiveEndDate = @EffectiveDate - 1, IsCurrent = 0.
 *      No replacement insert (close-only) — absent state means "assignment
 *      ended", a single known interpretation. Returning teachers get fresh
 *      current rows from step 3 on the next ingest.
 *
 *   3. INSERT new triples (NOT EXISTS in current rows of FactSectionTeachers).
 *      Covers:
 *        - First-time assignments (no history at all for this triple)
 *        - Returning assignments (only inactive history exists)
 *      Note: a "role change" (e.g. CoTeacher -> Support on the same section
 *      for the same teacher) appears as TWO triples — old closed in step 2,
 *      new inserted in step 3. Each role is its own bridge row.
 *
 *   4. Touch LastUpdated on UNCHANGED current rows (whose triple is in Wrk
 *      AND was not just inserted this run). Strict less-than on
 *      EffectiveStartDate gives the documented same-day re-run quirk
 *      (TouchedRows reads 0 on a same-day re-run of unchanged data).
 *
 *   5. Append one summary row to FactSubmissionAudit.
 *
 * Source-table dependency:
 *   This proc reads from Stg_Section AND Stg_CoTeacher. Both staging tables
 *   must be loaded before calling this proc. The recommended ingest order
 *   for a full cycle is:
 *     1. usp_LoadStudentsStaging  -> usp_MergeStudent
 *     2. usp_LoadStaffStaging     -> usp_MergeStaff
 *     3. usp_LoadSectionStaging   -> usp_MergeSection
 *     4. usp_LoadEnrollmentStaging -> usp_MergeEnrollment
 *     5. usp_LoadCoTeacherStaging -> (no separate merge — feeds step 6)
 *     6. usp_MergeSectionTeachers  (reads Stg_Section + Stg_CoTeacher)
 *   If Stg_CoTeacher is empty (PS doesn't track co-teaching), step 5 may
 *   be skipped — the merge tolerates an empty Stg_CoTeacher.
 *
 * Anti-join semantics: close-only, no replacement. The absent state for a
 * teacher-section assignment is binary in concept ("the assignment ended")
 * but there's no "what is the new value" to materialize — a missing triple
 * just stops being current. IsCurrent=1 filters in vw_TeacherStudents
 * already exclude it.
 *
 * @EffectiveDate parameter: defaults to today. Override only for backfill
 * or replay. Used for both EffectiveStartDate of new rows and
 * EffectiveEndDate (= @EffectiveDate - 1 day) of closed rows.
 ******************************************************************************/

CREATE PROCEDURE usp_MergeSectionTeachers
    @EffectiveDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EffectiveDate IS NULL
        SET @EffectiveDate = CAST(GETDATE() AS DATE);

    DECLARE @RunStart            DATETIME2(0) = GETDATE();
    DECLARE @PrimaryStg          INT = 0;
    DECLARE @CoTeacherStg        INT = 0;
    DECLARE @EmptyEmailExcluded  INT = 0;   -- Stg rows with empty/whitespace email — cannot be keyed
    DECLARE @WrkRowCount         INT = 0;   -- Distinct triples landing in Wrk
    DECLARE @InsertedNew         INT = 0;   -- Triples not currently active in FactSectionTeachers
    DECLARE @ClosedRows          INT = 0;   -- Current rows whose triple is missing from Wrk
    DECLARE @TouchedRows         INT = 0;   -- Unchanged current rows (LastUpdated only; subject to same-day re-run quirk)

    SELECT @PrimaryStg   = COUNT(*) FROM Stg_Section;
    SELECT @CoTeacherStg = COUNT(*) FROM Stg_CoTeacher;

    -- ------------------------------------------------------------------------
    -- Step 1: Build the unified Wrk set (primary + co-teacher), with role
    -- normalization, email lowercasing, empty-email exclusion, and dedup.
    -- ------------------------------------------------------------------------
    SELECT @EmptyEmailExcluded = (
        SELECT COUNT(*) FROM Stg_Section   WHERE NULLIF(LTRIM(RTRIM(Email_Addr)), '') IS NULL
    ) + (
        SELECT COUNT(*) FROM Stg_CoTeacher WHERE NULLIF(LTRIM(RTRIM(Email)),       '') IS NULL
    );

    TRUNCATE TABLE Wrk_SectionTeacher;

    INSERT INTO Wrk_SectionTeacher (SectionID, TeacherEmail, TeacherRole, SourceSystemID)
    SELECT DISTINCT
        u.SectionID,
        u.TeacherEmail,
        u.TeacherRole,
        u.SourceSystemID
    FROM (
        -- Primary teachers from Stg_Section
        SELECT
            s.ID                                AS SectionID,
            LOWER(LTRIM(RTRIM(s.Email_Addr)))   AS TeacherEmail,
            'Primary'                           AS TeacherRole,
            s.ID                                AS SourceSystemID
        FROM Stg_Section s
        WHERE NULLIF(LTRIM(RTRIM(s.Email_Addr)), '') IS NOT NULL

        UNION ALL

        -- Co-teachers from Stg_CoTeacher
        SELECT
            c.SectionID                         AS SectionID,
            LOWER(LTRIM(RTRIM(c.Email)))        AS TeacherEmail,
            CASE
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'co-teacher' THEN 'CoTeacher'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'coteacher'  THEN 'CoTeacher'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'support'    THEN 'Support'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'substitute' THEN 'Substitute'
                WHEN LOWER(LTRIM(RTRIM(c.Role))) = 'primary'    THEN 'Primary'
                ELSE LTRIM(RTRIM(c.Role))
            END                                 AS TeacherRole,
            NULL                                AS SourceSystemID
        FROM Stg_CoTeacher c
        WHERE NULLIF(LTRIM(RTRIM(c.Email)), '') IS NOT NULL
    ) u;

    SET @WrkRowCount = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 2: Close current rows whose triple is missing from Wrk.
    -- Close-only, no replacement insert.
    -- ------------------------------------------------------------------------
    UPDATE f
    SET EffectiveEndDate = DATEADD(DAY, -1, @EffectiveDate),
        IsCurrent        = 0,
        LastUpdated      = GETDATE()
    FROM FactSectionTeachers f
    LEFT JOIN Wrk_SectionTeacher w
           ON w.SectionID    = f.SectionID
          AND w.TeacherEmail = f.TeacherEmail
          AND w.TeacherRole  = f.TeacherRole
    WHERE f.IsCurrent = 1
      AND w.SectionID IS NULL;

    SET @ClosedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 3: INSERT new triples (no current row exists for this triple).
    -- Covers both first-time assignments and returning assignments.
    -- ------------------------------------------------------------------------
    INSERT INTO FactSectionTeachers (
        SectionID, TeacherEmail, TeacherRole,
        EffectiveStartDate, EffectiveEndDate, IsCurrent, SourceSystemID, LastUpdated
    )
    SELECT
        w.SectionID, w.TeacherEmail, w.TeacherRole,
        @EffectiveDate, NULL, 1, w.SourceSystemID, GETDATE()
    FROM Wrk_SectionTeacher w
    WHERE NOT EXISTS (
        SELECT 1 FROM FactSectionTeachers f
        WHERE f.SectionID    = w.SectionID
          AND f.TeacherEmail = w.TeacherEmail
          AND f.TeacherRole  = w.TeacherRole
          AND f.IsCurrent    = 1
    );

    SET @InsertedNew = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 4: Touch LastUpdated on unchanged current rows (predate this run).
    -- Strict less-than gives the documented same-day re-run quirk (touched
    -- reads 0 if everything in Wrk was inserted today).
    -- ------------------------------------------------------------------------
    UPDATE f
    SET LastUpdated = GETDATE()
    FROM FactSectionTeachers f
    INNER JOIN Wrk_SectionTeacher w
            ON w.SectionID    = f.SectionID
           AND w.TeacherEmail = f.TeacherEmail
           AND w.TeacherRole  = f.TeacherRole
    WHERE f.IsCurrent = 1
      AND f.EffectiveStartDate < @EffectiveDate;

    SET @TouchedRows = @@ROWCOUNT;

    -- ------------------------------------------------------------------------
    -- Step 5: Audit. One summary row per run.
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
        CASE WHEN @EmptyEmailExcluded > 0 THEN 'AcceptedWithWarnings'
             ELSE 'Accepted' END,
        CONCAT(
            'usp_MergeSectionTeachers: ',
            CAST(@PrimaryStg          AS VARCHAR(20)), ' primary | ',
            CAST(@CoTeacherStg        AS VARCHAR(20)), ' co-teacher | ',
            CAST(@WrkRowCount         AS VARCHAR(20)), ' triples (deduped) | ',
            CAST(@InsertedNew         AS VARCHAR(20)), ' new | ',
            CAST(@ClosedRows          AS VARCHAR(20)), ' deactivated (missing from import) | ',
            CAST(@TouchedRows         AS VARCHAR(20)), ' unchanged',
            CASE WHEN @EmptyEmailExcluded > 0
                 THEN CONCAT(' | [WARN: ', CAST(@EmptyEmailExcluded AS VARCHAR(20)), ' rows excluded — empty teacher email]')
                 ELSE '' END
        ),
        @PrimaryStg + @CoTeacherStg,
        GETDATE()
    );
END;
