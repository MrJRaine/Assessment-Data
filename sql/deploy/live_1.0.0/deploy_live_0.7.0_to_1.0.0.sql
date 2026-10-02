/**********************************************************************************************
 * STANDALONE LIVE DEPLOY — Assessment_Warehouse — 0.7.0 -> 1.0.0
 * Feature: data-driven writing TRAIT exclusion (excluded trait recorded as '-').
 *
 * Run ONCE against the LIVE Assessment_Warehouse, under the maintenance window, BEFORE the
 * container swap to assessment-webapp:1.0.0. This file bundles every SQL object that changed
 * between 0.7.0 and 1.0.0, in dependency order. It is the concatenation of the canonical
 * sources (regenerate with scripts/generate_live_deploy_1.0.0.sh) — no edits belong here.
 *
 * ORDER (do not reorder):
 *   1. migrate_FactWriting_traits_varchar  — Ideas/Org/Lang INT -> VARCHAR(10) (gates the '-' sentinel)
 *   2. WritingTraitExclusion               — config table + seed (FI . grade-P . months 9/10/11 . Organization)
 *   3. usp_UpsertWritingAssessment         — stores '-'; average over scored traits only
 *   4. tvf_TeacherRosterWriting            — returns ExcludedTraits; allow-list average
 *   5. tvf_StudentCohortWriting            — allow-list average
 *   6. tvf_StudentAssessmentHistoryWriting — allow-list average
 *   7. tvf_StudentCohortRWM                — allow-list writing average (P-6 includes grade P)
 *   8. tvf_StudentRWMHistory               — allow-list writing average
 *   9. remediate_writing_trait_exclusion   — mark existing excluded cells '-' + recompute stored avg
 *
 * IDEMPOTENT: #1 guards on column type, #2 guards CREATE + NOT-EXISTS seed, #3-#8 are DROP+CREATE,
 * #9 guards on value. Safe to re-run. Steps #1 and #9 contain verify SELECTs (expect: #1 four
 * VARCHAR=167 rows; #9 zero rows) — informational, leave them.
 *
 * NB (Fabric): TRY_CAST('-' AS INT) returns 0 (not NULL), so every average counts a trait only
 * when it is explicitly IN ('1','2','3','4'). Do not "simplify" back to TRY_CAST.
 * Region: Canada East (PIIDPA compliant).
 **********************************************************************************************/


/**********************************************************************
 * 1/9  migrate_FactWriting_traits_varchar.sql
 **********************************************************************/

/*******************************************************************************
 * Script: migrate_FactWriting_traits_varchar.sql
 * Purpose: Change FactAssessmentWriting.IdeasScore / OrganizationScore /
 *          LanguageScore from INT to VARCHAR(10), so a trait can hold the
 *          intentional "-" (NOT assessed this cycle — a DELIBERATE recording,
 *          distinct from NULL = never recorded) alongside '1'-'4'. This mirrors
 *          the earlier ConventionsScore INT->VARCHAR swap (which added 'SCR').
 *          After this, all four writing traits are VARCHAR(10) and carry:
 *            '1'-'4' | 'SCR' (Conventions only) | '-' (excluded) | NULL (never recorded).
 *
 *          Fabric has no ALTER COLUMN (type change) and we avoid a full table
 *          rebuild, so each column does the proven multi-step swap that PRESERVES
 *          existing data and the column NAME:
 *            add temp VARCHAR -> copy INT->VARCHAR -> drop INT col -> re-add VARCHAR
 *            under the original name -> copy back -> drop temp.
 *          Each step is its own batch (GO) and the data-copy steps use EXEC so the
 *          parser never sees a not-yet-existing column (fabric-warehouse-sql skill:
 *          catalog-check-in-same-batch gotcha).
 * Created: 2026-10-02
 * Region: Canada East (PIIDPA compliant)
 *
 * RUN ONCE per warehouse (dev, then live). Idempotent: every batch is guarded on
 * the column's current type (int=56, varchar=167), so once converted the whole
 * script no-ops. Safe on an empty table (the UPDATEs touch 0 rows). The '-' values
 * themselves are written by usp_UpsertWritingAssessment (new entries) and by
 * remediate_writing_trait_exclusion.sql (existing rows) — NOT here.
 ******************************************************************************/

-- ======================= IdeasScore =======================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD IdeasScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET IdeasScoreTmp = CAST(IdeasScore AS VARCHAR(10)) WHERE IdeasScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN IdeasScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD IdeasScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET IdeasScore = IdeasScoreTmp WHERE IdeasScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'IdeasScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN IdeasScoreTmp;
END;
GO

-- ==================== OrganizationScore ====================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD OrganizationScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET OrganizationScoreTmp = CAST(OrganizationScore AS VARCHAR(10)) WHERE OrganizationScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN OrganizationScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD OrganizationScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET OrganizationScore = OrganizationScoreTmp WHERE OrganizationScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'OrganizationScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN OrganizationScoreTmp;
END;
GO

-- ====================== LanguageScore ======================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD LanguageScoreTmp VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET LanguageScoreTmp = CAST(LanguageScore AS VARCHAR(10)) WHERE LanguageScore IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore' AND system_type_id = 56)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN LanguageScore;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScore')
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting ADD LanguageScore VARCHAR(10) NULL;
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    EXEC('UPDATE dbo.FactAssessmentWriting SET LanguageScore = LanguageScoreTmp WHERE LanguageScoreTmp IS NOT NULL;');
END;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting') AND name = 'LanguageScoreTmp')
BEGIN
    ALTER TABLE dbo.FactAssessmentWriting DROP COLUMN LanguageScoreTmp;
END;
GO

-- verify (dev/synthetic — safe to display): all four trait columns should now be VARCHAR(167).
SELECT name, system_type_id
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.FactAssessmentWriting')
  AND name IN ('IdeasScore', 'OrganizationScore', 'LanguageScore', 'ConventionsScore')
ORDER BY name;
GO


/**********************************************************************
 * 2/9  WritingTraitExclusion.sql
 **********************************************************************/

/*******************************************************************************
 * Table: WritingTraitExclusion
 * Purpose: Data-driven config for which writing TRAIT(s) are NOT assessed for a
 *          given (Grade x ProgramFamily x cycle benchmark month) — so the entry
 *          grid doesn't show that trait's dropdown and the average/reports drop it
 *          (same effect as a Conventions 'SCR'). Grain: one row per excluded trait.
 *          NEVER hardcode this rule in app/proc logic — add/remove rows here.
 * SCD: N/A (reference/config; admin-maintained).
 * Created: 2026-10-02
 * Region: Canada East (PIIDPA compliant)
 *
 * First rule (early French Immersion Primary can't produce enough French writing
 * in the fall to assess Organization): FI · Grade P · benchmark months Sep/Oct/Nov
 * · Organization. BenchmarkMonth is the INT 1-12 that the cycle's window resolves to
 * (DimAssessmentWindow.BenchmarkMonth, else its dominant calendar month).
 * Trait is one of: 'Ideas' | 'Organization' | 'Language' | 'Conventions'.
 *
 * IDEMPOTENT: guarded CREATE (never drops) + NOT-EXISTS seed, so a redeploy keeps
 * any admin-added rows. SELECT granted to the app SP.
 ******************************************************************************/

IF OBJECT_ID('dbo.WritingTraitExclusion', 'U') IS NULL
    EXEC('CREATE TABLE dbo.WritingTraitExclusion (
        WritingTraitExclusionID BIGINT       NOT NULL IDENTITY,
        GradeCode               VARCHAR(10)  NOT NULL,
        ProgramFamily           VARCHAR(50)  NOT NULL,
        BenchmarkMonth          INT          NOT NULL,   -- 1-12
        Trait                   VARCHAR(20)  NOT NULL,   -- Ideas|Organization|Language|Conventions
        ActiveFlag              BIT          NOT NULL,
        LastUpdated             DATETIME2(0) NOT NULL
    )');
GO

-- Seed: FI Primary — Organization not assessed in Sep/Oct/Nov cycles. Idempotent.
INSERT INTO dbo.WritingTraitExclusion (GradeCode, ProgramFamily, BenchmarkMonth, Trait, ActiveFlag, LastUpdated)
SELECT v.GradeCode, v.ProgramFamily, v.BenchmarkMonth, v.Trait, 1, GETDATE()
FROM (VALUES
    ('P', 'French Immersion',  9, 'Organization'),
    ('P', 'French Immersion', 10, 'Organization'),
    ('P', 'French Immersion', 11, 'Organization')
) v (GradeCode, ProgramFamily, BenchmarkMonth, Trait)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.WritingTraitExclusion x
    WHERE x.GradeCode = v.GradeCode AND x.ProgramFamily = v.ProgramFamily
      AND x.BenchmarkMonth = v.BenchmarkMonth AND x.Trait = v.Trait
);
GO

GRANT SELECT ON [dbo].[WritingTraitExclusion] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 3/9  usp_UpsertWritingAssessment.sql
 **********************************************************************/

/*******************************************************************************
 * Procedure: usp_UpsertWritingAssessment
 * Purpose: Web-app / Power Apps wrapper for entering or correcting a single
 *          writing assessment — the four-trait rubric (Ideas, Organization,
 *          Language, Conventions), each scored 1–4 by the teacher. Mirrors
 *          usp_UpsertReadingAssessment's structure and the ongoing-assessment
 *          monthly-window model, but writing has NO reading scale, NO grade
 *          benchmark and NO delta: the teacher's scores ARE the value stored.
 *          The cohort roll-up (average of the four → achievement band) is a
 *          READ-side concern (the writing cohort/history TVFs), not stored here.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Model (same as reading): windows are monthly bins; grain is
 *   (StudentKey, AssessmentWindowID, AssessmentDate). A teacher may record
 *   MULTIPLE dated results per window (each date its own row — prior entries
 *   kept; cohort pulls the latest by AssessmentDate); a same-date re-save is a
 *   correction (UPDATE in place). Closed windows are WRITEABLE (late entry); the
 *   51017 date gate caps the date at MIN(today, window EndDate) so a late entry
 *   bins into that window's month.
 *
 * Parameters:
 *   @StudentNumber      BIGINT       required, provincial 10-digit student #
 *   @AssessmentWindowID VARCHAR(20)  required, must resolve to ActiveFlag=1
 *                                    (BIGINT IDENTITY surfaced as VARCHAR for Power Fx)
 *   @IdeasScore         INT          1–4; required UNLESS excluded for this grade/program/benchmark
 *   @OrganizationScore  INT          month (WritingTraitExclusion) — an excluded trait is passed NULL
 *   @LanguageScore      INT          by the app (dropdown hidden) and STORED as '-' (deliberately NOT
 *                                    assessed), distinct from a true NULL. '-' drops from the average.
 *   @ConventionsScore   VARCHAR(10)  '1'–'4' or 'SCR' (Scribed; omitted from the average); '-' if excluded
 *   @AssessmentDate     DATE         required (effective-date StudentKey resolution + stored)
 *   @AssessmentLanguage VARCHAR(10)  'English'|'French' writing track (part of the grain); NULL ->
 *                                    derive from program family (single-language students)
 *   @CallerUPN          VARCHAR(255) web-app/SP path: signed-in teacher UPN; NULL -> CURRENT_USER
 *
 * THROW codes (writing variants of the shared scheme):
 *   51010  required parameter NULL
 *   51011  @StudentNumber does not resolve to a DimStudent row at @AssessmentDate
 *   51012  @AssessmentWindowID does not resolve to an active window
 *   51015  window AssessmentType is not 'Writing'
 *   51016  student grade (at AssessmentDate) outside window's [MinGrade, MaxGrade]
 *   51017  @AssessmentDate outside [window.StartDate, MIN(today_atlantic, window.EndDate)]
 *   51018  a trait score is outside 1–4
 *   51019  student ProgramFamily does not match the window's (when program-scoped), OR
 *          @AssessmentLanguage invalid for the student (French writing requires French Immersion;
 *          English writing for an immersion student requires grade 3+) — the dual-language track guard
 *   51030  caller not in DimStaff (IsCurrent=1)
 *   51032  window is Upcoming (not yet started)
 *
 * No OUTPUT clause (Fabric Warehouse limitation). Timestamps stored UTC; today
 * computed in Atlantic (DST-aware).
 ******************************************************************************/

DROP PROCEDURE IF EXISTS usp_UpsertWritingAssessment;
GO

CREATE PROCEDURE usp_UpsertWritingAssessment
    @StudentNumber      BIGINT,
    @AssessmentWindowID VARCHAR(20),
    @IdeasScore         INT,
    @OrganizationScore  INT,
    @LanguageScore      INT,
    @ConventionsScore   VARCHAR(10),  -- '1'-'4', or 'SCR' (Scribed) — scribed is omitted from the average
    @AssessmentDate     DATE,
    @AssessmentLanguage VARCHAR(10)  = NULL,  -- 'English' | 'French' writing track; NULL = derive from the student's program family (single-language students)
    @CallerUPN          VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now                    DATETIME2(0)  = GETDATE();
    DECLARE @Today                  DATE          = CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE);
    DECLARE @CallerEmail            VARCHAR(255)  = LOWER(COALESCE(@CallerUPN, CURRENT_USER));
    DECLARE @CallerStaffKey         BIGINT;
    DECLARE @WritingAverage         DECIMAL(4,2);   -- SCR/'-'-aware average, stamped on the fact (as-was)
    -- Store values actually written to the (VARCHAR) trait columns: '1'-'4' | 'SCR' (Conv only) |
    -- '-' (excluded = deliberately NOT assessed) | NULL (never recorded).
    DECLARE @IdeasStore VARCHAR(10), @OrgStore VARCHAR(10), @LangStore VARCHAR(10), @ConvStore VARCHAR(10);
    DECLARE @AssessmentWindowID_BI  BIGINT;
    DECLARE @WindowStartDate        DATE;
    DECLARE @WindowEndDate          DATE;
    DECLARE @WindowMinGrade         VARCHAR(10);
    DECLARE @WindowMaxGrade         VARCHAR(10);
    DECLARE @WindowProgramFamily    VARCHAR(50);
    DECLARE @WindowAssessmentType   VARCHAR(20);
    DECLARE @WindowStatus           VARCHAR(20);
    DECLARE @StudentKey             BIGINT;
    DECLARE @StudentGrade           VARCHAR(10);
    DECLARE @StudentProgramCode     VARCHAR(10);
    DECLARE @StudentProgramFamily   VARCHAR(50);
    DECLARE @StudentGradeOrder      INT;
    DECLARE @MinGradeOrder          INT;
    DECLARE @MaxGradeOrder          INT;
    DECLARE @ExistingAssessmentID   BIGINT;
    DECLARE @WindowBenchmarkMonth   INT;
    DECLARE @EffectiveBenchMonth    INT;
    DECLARE @ExclIdeas BIT = 0, @ExclOrg BIT = 0, @ExclLang BIT = 0, @ExclConv BIT = 0;  -- trait-exclusion flags

    -- 51010: required identifiers (trait requirements are checked below, AFTER the trait-exclusion
    -- rules resolve — a trait excluded for this grade x program x benchmark month may be NULL).
    IF @StudentNumber IS NULL OR @AssessmentWindowID IS NULL OR @AssessmentDate IS NULL
    BEGIN
        ;THROW 51010, 'usp_UpsertWritingAssessment: @StudentNumber, @AssessmentWindowID, and @AssessmentDate are required.', 1;
    END;

    -- (Trait presence/range validation (51010/51018) is exclusion-aware → moved below, after the
    --  student/window/exclusion lookups, since a trait can be legitimately not-assessed for a cell.)

    SET @AssessmentWindowID_BI = CAST(@AssessmentWindowID AS BIGINT);

    -- 51030: caller resolves to a current DimStaff row
    SELECT TOP 1 @CallerStaffKey = StaffKey
    FROM DimStaff WHERE LOWER(Email) = @CallerEmail AND IsCurrent = 1;

    IF @CallerStaffKey IS NULL
    BEGIN
        ;THROW 51030, 'usp_UpsertWritingAssessment: caller does not resolve to a current DimStaff row. Cannot enter assessments without a staff identity.', 1;
    END;

    -- 51012: window resolves and is active
    SELECT
        @WindowStartDate      = StartDate,
        @WindowEndDate        = EndDate,
        @WindowMinGrade       = MinGrade,
        @WindowMaxGrade       = MaxGrade,
        @WindowProgramFamily  = ProgramFamily,
        @WindowAssessmentType = AssessmentType,
        @WindowBenchmarkMonth = BenchmarkMonth
    FROM DimAssessmentWindow
    WHERE AssessmentWindowID = @AssessmentWindowID_BI AND ActiveFlag = 1;

    IF @WindowStartDate IS NULL
    BEGIN
        ;THROW 51012, 'usp_UpsertWritingAssessment: @AssessmentWindowID does not resolve to an active DimAssessmentWindow row.', 1;
    END;

    -- 51015: this proc only handles Writing windows
    IF @WindowAssessmentType <> 'Writing'
    BEGIN
        ;THROW 51015, 'usp_UpsertWritingAssessment: window AssessmentType is not Writing. Use the matching upsert proc for Reading/Math.', 1;
    END;

    -- Window status — block Upcoming (51032). Closed windows stay writeable (late entry).
    SET @WindowStatus =
        CASE WHEN @Today < @WindowStartDate THEN 'Upcoming'
             WHEN @Today > @WindowEndDate   THEN 'Closed'
             WHEN @Today = @WindowEndDate   THEN 'ClosesToday'
             ELSE 'Open' END;

    IF @WindowStatus = 'Upcoming'
    BEGIN
        ;THROW 51032, 'usp_UpsertWritingAssessment: window is Upcoming (not yet started). No entries allowed before the window opens.', 1;
    END;

    -- 51040: GRACE-LOCK (0.7.0). Past EndDate + the cycle's GraceHours (default 168h, from the close
    -- moment = midnight after EndDate), the window is LOCKED: read-only for everyone EXCEPT a caller
    -- holding the Literacy override (StaffAppAccess.CanOverrideLiteracy) or IsSysAdmin. Hour-granular,
    -- so compare the Atlantic NOW timestamp. @IsLocked drives the audit note.
    DECLARE @GraceHours INT, @LockBoundary DATETIME2(0), @IsLocked BIT = 0, @HasOverride BIT = 0;
    SELECT @GraceHours = COALESCE(sc.GraceHours, 168)
    FROM DimAssessmentWindow w
    LEFT JOIN DimShortCycle sc ON sc.CycleGroupID = w.CycleGroupID
    WHERE w.AssessmentWindowID = @AssessmentWindowID_BI;

    SET @LockBoundary = DATEADD(HOUR, COALESCE(@GraceHours, 168), CAST(DATEADD(DAY, 1, @WindowEndDate) AS DATETIME2(0)));
    IF CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATETIME2(0)) > @LockBoundary
        SET @IsLocked = 1;

    IF @IsLocked = 1
    BEGIN
        SELECT @HasOverride = CASE WHEN IsSysAdmin = 1 OR COALESCE(CanOverrideLiteracy, 0) = 1 THEN 1 ELSE 0 END
        FROM StaffAppAccess WHERE LOWER(Email) = @CallerEmail;
        IF @HasOverride = 0
        BEGIN
            ;THROW 51040, 'usp_UpsertWritingAssessment: this cycle is locked (grace period expired). You do not hold the Literacy override to enter data for it.', 1;
        END;
    END;

    -- 51011: student resolves via effective-date join on AssessmentDate
    SELECT TOP 1
        @StudentKey         = s.StudentKey,
        @StudentGrade       = s.Grade,
        @StudentProgramCode = s.ProgramCode
    FROM DimStudent s
    WHERE s.StudentNumber = @StudentNumber
      AND @AssessmentDate BETWEEN s.EffectiveStartDate AND COALESCE(s.EffectiveEndDate, '9999-12-31');

    IF @StudentKey IS NULL
    BEGIN
        ;THROW 51011, 'usp_UpsertWritingAssessment: @StudentNumber does not resolve to a DimStudent row effective at @AssessmentDate.', 1;
    END;

    SELECT @StudentProgramFamily = ProgramFamily FROM DimProgram WHERE ProgramCode = @StudentProgramCode;

    -- 51019: student program family matches the window's (when the window is program-scoped)
    IF @WindowProgramFamily IS NOT NULL AND ISNULL(@StudentProgramFamily, '~') <> @WindowProgramFamily
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: student ProgramFamily does not match the window ProgramFamily (e.g. an English student in a French Immersion window).', 1;
    END;

    -- 51016: student grade within window's [MinGrade, MaxGrade]
    SELECT @StudentGradeOrder = GradeOrder FROM DimGrade WHERE GradeCode = @StudentGrade;
    SELECT @MinGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMinGrade;
    SELECT @MaxGradeOrder     = GradeOrder FROM DimGrade WHERE GradeCode = @WindowMaxGrade;

    IF @StudentGradeOrder IS NULL OR @MinGradeOrder IS NULL OR @MaxGradeOrder IS NULL
       OR @StudentGradeOrder NOT BETWEEN @MinGradeOrder AND @MaxGradeOrder
    BEGIN
        ;THROW 51016, 'usp_UpsertWritingAssessment: student grade at AssessmentDate is outside the window grade range.', 1;
    END;

    -- 51017: AssessmentDate within [WindowStartDate, MIN(today, WindowEndDate)]
    IF @AssessmentDate < @WindowStartDate
       OR @AssessmentDate > CASE WHEN @Today < @WindowEndDate THEN @Today ELSE @WindowEndDate END
    BEGIN
        ;THROW 51017, 'usp_UpsertWritingAssessment: @AssessmentDate is outside this window''s range [StartDate, min(today, EndDate)].', 1;
    END;

    -- Language track: default to the student's program language when not supplied
    -- (single-language students), then validate against the writing tracks (mirrors
    -- usp_MergeStudent Step 6): French writing requires French Immersion; English
    -- writing for an immersion student requires grade >= 3 (ELA).
    IF @AssessmentLanguage IS NULL
        SET @AssessmentLanguage = CASE WHEN @StudentProgramFamily = 'French Immersion' THEN 'French' ELSE 'English' END;

    IF @AssessmentLanguage NOT IN ('English', 'French')
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: @AssessmentLanguage must be ''English'' or ''French''.', 1;
    END;

    IF (@AssessmentLanguage = 'French'  AND @StudentProgramFamily <> 'French Immersion')
       OR (@AssessmentLanguage = 'English' AND @StudentProgramFamily = 'French Immersion' AND @StudentGradeOrder < 3)
    BEGIN
        ;THROW 51019, 'usp_UpsertWritingAssessment: @AssessmentLanguage is not valid for this student (French writing requires French Immersion; English writing for an immersion student requires grade 3+).', 1;
    END;

    -- -------------------------------------------------------------------------
    -- TRAIT-EXCLUSION rules (data-driven: WritingTraitExclusion). A trait listed for this student's
    -- Grade x ProgramFamily x the cycle's benchmark month is NOT assessed: force its value to NULL
    -- (recorded as "not assessed", shown as a dash in the grid/reports) so it drops from the average.
    -- Benchmark month = the window's BenchmarkMonth, else the month its StartDate falls in (monthly bins).
    -- NEVER hardcode which traits — add/remove rows in WritingTraitExclusion.
    -- -------------------------------------------------------------------------
    SET @EffectiveBenchMonth = COALESCE(@WindowBenchmarkMonth, MONTH(@WindowStartDate));
    SELECT @ExclIdeas = COALESCE(MAX(CASE WHEN Trait = 'Ideas'        THEN 1 END), 0),
           @ExclOrg   = COALESCE(MAX(CASE WHEN Trait = 'Organization' THEN 1 END), 0),
           @ExclLang  = COALESCE(MAX(CASE WHEN Trait = 'Language'     THEN 1 END), 0),
           @ExclConv  = COALESCE(MAX(CASE WHEN Trait = 'Conventions'  THEN 1 END), 0)
    FROM WritingTraitExclusion
    WHERE ActiveFlag = 1
      AND GradeCode      = @StudentGrade
      AND ProgramFamily  = @StudentProgramFamily
      AND BenchmarkMonth = @EffectiveBenchMonth;

    -- Store value per trait: an excluded trait is recorded as the intentional '-' (deliberately NOT
    -- assessed this cycle), which is DISTINCT from NULL (never recorded). Non-excluded traits store
    -- their score as text ('1'-'4', or 'SCR' for Conventions). The stored value is authoritative: even
    -- if a crafted request sent a number for an excluded trait, it is overwritten with '-'.
    SET @IdeasStore = CASE WHEN @ExclIdeas = 1 THEN '-' ELSE CAST(@IdeasScore        AS VARCHAR(10)) END;
    SET @OrgStore   = CASE WHEN @ExclOrg   = 1 THEN '-' ELSE CAST(@OrganizationScore AS VARCHAR(10)) END;
    SET @LangStore  = CASE WHEN @ExclLang  = 1 THEN '-' ELSE CAST(@LanguageScore     AS VARCHAR(10)) END;
    SET @ConvStore  = CASE WHEN @ExclConv  = 1 THEN '-' ELSE @ConventionsScore                       END;

    -- 51010 (trait presence): every NON-excluded trait is required.
    IF (@ExclIdeas = 0 AND @IdeasScore        IS NULL)
       OR (@ExclOrg  = 0 AND @OrganizationScore IS NULL)
       OR (@ExclLang = 0 AND @LanguageScore     IS NULL)
       OR (@ExclConv = 0 AND @ConventionsScore  IS NULL)
    BEGIN
        ;THROW 51010, 'usp_UpsertWritingAssessment: every non-excluded trait score is required (no NULLs).', 1;
    END;

    -- 51018 (trait range): non-excluded Ideas/Organization/Language are integers 1-4; Conventions is
    -- '1'-'4' or 'SCR'. Excluded traits are NULL and skipped.
    IF (@ExclIdeas = 0 AND @IdeasScore        NOT BETWEEN 1 AND 4)
       OR (@ExclOrg  = 0 AND @OrganizationScore NOT BETWEEN 1 AND 4)
       OR (@ExclLang = 0 AND @LanguageScore     NOT BETWEEN 1 AND 4)
    BEGIN
        ;THROW 51018, 'usp_UpsertWritingAssessment: Ideas, Organization, and Language must each be an integer 1-4 (unless excluded for this grade/program/month).', 1;
    END;

    IF @ExclConv = 0 AND @ConventionsScore NOT IN ('1', '2', '3', '4', 'SCR')
    BEGIN
        ;THROW 51018, 'usp_UpsertWritingAssessment: Conventions must be ''1''-''4'' or ''SCR'' (Scribed).', 1;
    END;

    -- =========================================================================
    -- UPSERT into FactAssessmentWriting, grain = (StudentKey, AssessmentWindowID,
    -- AssessmentLanguage, AssessmentDate). A student may hold an English AND a French
    -- result in the same cycle (FI grade 3+). Same (language,date) re-save = correction;
    -- a new date = a new row (prior entries kept; cohort pulls the latest date per language).
    -- =========================================================================
    SELECT @ExistingAssessmentID = WritingAssessmentID
    FROM FactAssessmentWriting
    WHERE StudentKey = @StudentKey
      AND AssessmentWindowID = @AssessmentWindowID_BI
      AND AssessmentLanguage = @AssessmentLanguage
      AND AssessmentDate = @AssessmentDate;

    -- Writing average, stamped on the row (as-was) so the exclusion/SCR rules live in the DATA, not
    -- only the read logic: ANY NULL trait (excluded for this cell, or Conventions='SCR') drops from
    -- BOTH numerator and denominator — identical to how the cohort/history reads compute AvgScore.
    -- Average over the numerically-scored traits only. Count a trait ONLY when it is explicitly a
    -- score '1'-'4' — '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
    -- denominator. NB (Fabric gotcha): TRY_CAST('-' AS INT) returns 0, NOT NULL, so we must gate on
    -- an explicit allow-list, never on TRY_CAST being NULL. Computed from the STORE values so it
    -- matches what lands in the columns (and what the read TVFs recompute). All non-scored -> NULL.
    SET @WritingAverage =
        CAST(COALESCE(CASE WHEN @IdeasStore IN ('1','2','3','4') THEN CAST(@IdeasStore AS INT) END, 0)
             + COALESCE(CASE WHEN @OrgStore  IN ('1','2','3','4') THEN CAST(@OrgStore  AS INT) END, 0)
             + COALESCE(CASE WHEN @LangStore IN ('1','2','3','4') THEN CAST(@LangStore AS INT) END, 0)
             + COALESCE(CASE WHEN @ConvStore IN ('1','2','3','4') THEN CAST(@ConvStore AS INT) END, 0) AS DECIMAL(6,4))
        / NULLIF( (CASE WHEN @IdeasStore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @OrgStore   IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @LangStore  IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN @ConvStore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0);

    IF @ExistingAssessmentID IS NOT NULL
    BEGIN
        UPDATE FactAssessmentWriting
        SET IdeasScore          = @IdeasStore,
            OrganizationScore   = @OrgStore,
            LanguageScore       = @LangStore,
            ConventionsScore    = @ConvStore,
            WritingAverage      = @WritingAverage,
            EnteredByStaffKey   = @CallerStaffKey,
            SubmissionTimestamp = @Now,
            LastUpdated         = @Now
        WHERE WritingAssessmentID = @ExistingAssessmentID;
    END
    ELSE
    BEGIN
        INSERT INTO FactAssessmentWriting (
            StudentKey, AssessmentWindowID, AssessmentLanguage, IdeasScore, OrganizationScore,
            LanguageScore, ConventionsScore, WritingAverage, AssessmentDate, EnteredByStaffKey,
            SubmissionTimestamp, LastUpdated
        )
        VALUES (
            @StudentKey, @AssessmentWindowID_BI, @AssessmentLanguage, @IdeasStore, @OrgStore,
            @LangStore, @ConvStore, @WritingAverage, @AssessmentDate, @CallerStaffKey,
            @Now, @Now
        );
    END;

    -- Audit row
    INSERT INTO FactSubmissionAudit (
        RecordType, Source, SubmittedBy, SubmissionTimestamp, Status, Message, RecordCount, LastUpdated
    )
    VALUES (
        'WritingAssessment',
        CASE WHEN @CallerUPN IS NOT NULL THEN 'WebApp' ELSE 'PowerApps' END,
        @CallerEmail,
        @Now,
        'Accepted',
        CONCAT(
            'usp_UpsertWritingAssessment: ',
            CASE WHEN @ExistingAssessmentID IS NULL THEN 'INSERT' ELSE 'UPDATE' END,
            ' | StudentNumber=',      CAST(@StudentNumber AS VARCHAR(20)),
            ' | AssessmentWindowID=', @AssessmentWindowID,
            ' | Language=',           @AssessmentLanguage,
            ' | Scores I/O/L/C=',     CONCAT(@IdeasStore, '/', @OrgStore, '/', @LangStore, '/', @ConvStore),
            CASE WHEN @IsLocked = 1 THEN ' | GRACE-OVERRIDE' ELSE '' END   -- 0.7.0: save into a locked cycle via override
        ),
        1,
        @Now
    );
END;
GO

-- DROP+CREATE drops object grants; re-grant EXECUTE to the web-app SP so a redeploy is self-contained.
GRANT EXECUTE ON [dbo].[usp_UpsertWritingAssessment] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 4/9  tvf_TeacherRosterWriting.sql
 **********************************************************************/

/*******************************************************************************
 * Function: tvf_TeacherRosterWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_TeacherRoster for the web app entry grid.
 *          IDENTICAL scoping — only the per-student entry context differs: the MOST
 *          RECENT writing entry's four trait scores + their average + achievement
 *          band, plus Writing-IPP status. No benchmark / delta (writing has none).
 *          One row per student for the given window + group.
 * Created: 2026-06-25
 * Modified: 2026-09-08 — @GroupKey now matches the stored DimStudent.GroupKey for
 *          homerooms (URL-safe, school-qualified); returns Homeroom + SchoolName.
 *          2026-09-15 — @GroupKey resolution is now lens-agnostic.
 *          2026-09-15b — also resolves a 'GRADE:<SchoolID>:<Grade>' key.
 *          2026-09-17 — DUAL-LANGUAGE writing: @Language ('English'|'French') param
 *          (the EN/FR toggle). Caller MUST pass @Language.
 *          2026-09-18 — @GroupKeys takes a comma-delimited LIST (combined rosters), and the three
 *          role branches were replaced by SECTION-FIRST resolution.
 *          2026-09-23 — MATERIALIZED membership. Reads SectionRosterMembership (rebuilt each ingest
 *          by usp_RebuildRosterMembership) + a live access predicate, replacing the per-request
 *          DimStudent/FactEnrollment/DimSection/DimGrade/DimProgram join. The EN/FR toggle now filters
 *          by the SECTION's language (SectionRosterMembership.SectionLanguage, from
 *          DimCourseAssessment) — the section decides the language, NOT the student's program. The
 *          volatile writing-scores half is unchanged. Membership logic lives in
 *          usp_RebuildRosterMembership — keep the two in lockstep.
 * Region: Canada East (PIIDPA compliant)
 *
 * Band = average mapped to a code (3.50/2.75/1.75) then joined to
 * DimAchievementLevel by code for name + colour. SECURITY: trusts @UPN; SELECT
 * granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_TeacherRosterWriting;
GO

CREATE FUNCTION dbo.tvf_TeacherRosterWriting(@UPN VARCHAR(255), @AssessmentWindowID VARCHAR(20), @GroupKeys VARCHAR(4000), @Language VARCHAR(10))
RETURNS TABLE
AS
RETURN
(
    WITH Caller AS (
        SELECT TOP 1 d.StaffKey, LOWER(d.Email) AS Email, d.AccessLevel
        FROM DimStaff d
        WHERE LOWER(d.Email) = LOWER(@UPN) AND d.IsCurrent = 1
    ),
    WindowEffectiveDates AS (
        SELECT w.AssessmentWindowID, w.AssessmentLanguage, w.BenchmarkMonth, w.StartDate
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1
          AND w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
    ),
    -- MATERIALIZED membership (2026-09-23): pre-joined rows for the requested classes, access
    -- resolved LIVE as a predicate. The EN/FR toggle filters by the SECTION's language.
    Membership AS (
        SELECT m.AssessmentWindowID, m.SectionID, m.SchoolID, m.GroupKey, m.SectionLanguage, m.WindowEffectiveDate,
               m.StudentKey, m.StudentNumber, m.FirstName, m.LastName, m.Grade, m.Homeroom, m.SchoolName
        FROM SectionRosterMembership m
        WHERE m.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          AND (',' + @GroupKeys + ',') LIKE ('%,' + m.GroupKey + ',%')
    ),
    StudentGroups AS (
        SELECT DISTINCT
            m.AssessmentWindowID, m.StudentKey, m.StudentNumber, m.FirstName, m.LastName,
            m.Grade, m.Homeroom, m.SchoolName, m.GroupKey
        FROM Membership m
        CROSS JOIN Caller c
        CROSS JOIN WindowEffectiveDates wed
        WHERE (
                (c.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
                 AND EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                             WHERE ssa.StaffKey = c.StaffKey AND ssa.SchoolID = m.SchoolID))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst   -- teacher, ANY role (dual-role keeps theirs)
                        WHERE fst.SectionID = m.SectionID
                          AND LOWER(fst.TeacherEmail) = c.Email
                          AND m.WindowEffectiveDate BETWEEN fst.EffectiveStartDate
                                                        AND COALESCE(fst.EffectiveEndDate, '9999-12-31')))
          -- Language track = the SECTION's course language. Effective language is the cycle's scope
          -- when set, else the EN/FR toggle. (For a scoped window the base already holds only that
          -- language's sections; the predicate is a harmless no-op then and does the real work when
          -- the window is unscoped and @GroupKeys could span languages.)
          AND m.SectionLanguage = COALESCE(wed.AssessmentLanguage, @Language)
    ),
    -- Most recent writing entry per (student, window) -- multiple dated entries are allowed.
    LatestWritingInWindow AS (
        SELECT
            StudentKey, AssessmentWindowID, IdeasScore, OrganizationScore, LanguageScore, ConventionsScore,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded = deliberately not assessed), 'SCR' (scribed) and NULL all drop from
            -- BOTH the sum and the count (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha):
            -- TRY_CAST('-' AS INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN IdeasScore        IN ('1','2','3','4') THEN CAST(IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN OrganizationScore IN ('1','2','3','4') THEN CAST(OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN LanguageScore     IN ('1','2','3','4') THEN CAST(LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN CAST(ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            AssessmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY StudentKey, AssessmentWindowID
                ORDER BY AssessmentDate DESC, WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting
        WHERE AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)
          -- Show the score for the effective track: the cycle's language when scoped, else the toggle.
          AND AssessmentLanguage = COALESCE(
                (SELECT w.AssessmentLanguage FROM DimAssessmentWindow w
                 WHERE w.AssessmentWindowID = CAST(@AssessmentWindowID AS BIGINT)), @Language)
    )
    SELECT DISTINCT
        CAST(sg.StudentKey AS VARCHAR(20)) AS StudentKey,
        sg.StudentNumber,
        sg.FirstName,
        sg.LastName,
        sg.GroupKey,        -- which of the selected classes this student came from (combined roster headings)
        sg.Grade,
        sg.Homeroom,
        sg.SchoolName,
        faw.IdeasScore         AS ExistingIdeasScore,
        faw.OrganizationScore  AS ExistingOrganizationScore,
        faw.LanguageScore      AS ExistingLanguageScore,
        faw.ConventionsScore   AS ExistingConventionsScore,
        faw.AvgScore           AS ExistingAvgScore,
        faw.AssessmentDate     AS ExistingAssessmentDate,
        ipp.IsIPP              AS WritingIPPStatus,
        CASE WHEN ipp.StudentIPPID IS NOT NULL AND ipp.IsIPP IS NULL
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS WritingIPPNeedsConfirmation,
        -- Writing IPP family follows the effective language track (cycle scope, else toggle).
        -- Achievement band is computed CLIENT-SIDE in WritingRosterEntry (writingBand), so the
        -- DimAchievementLevel join + its columns were dead server work; removed 2026-09-23.
        CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END AS IPPProgramFamily,
        -- Data-driven trait exclusions for this student's grade x ACTUAL program family x the cycle's
        -- benchmark month (WritingTraitExclusion) — the grid hides these dropdowns; the upsert enforces
        -- the NULL. Keyed on the student's real ProgramFamily (matches the upsert), not the language track.
        (SELECT STRING_AGG(wte.Trait, ',')
         FROM WritingTraitExclusion wte
         WHERE wte.ActiveFlag = 1
           AND wte.GradeCode      = sg.Grade
           AND wte.ProgramFamily  = dp.ProgramFamily
           AND wte.BenchmarkMonth = COALESCE(wed.BenchmarkMonth, MONTH(wed.StartDate))) AS ExcludedTraits
    FROM StudentGroups sg
    INNER JOIN WindowEffectiveDates wed ON wed.AssessmentWindowID = sg.AssessmentWindowID
    LEFT JOIN DimStudent ds ON ds.StudentKey = sg.StudentKey AND ds.IsCurrent = 1
    LEFT JOIN DimProgram dp ON dp.ProgramCode = ds.ProgramCode
    LEFT JOIN LatestWritingInWindow faw
           ON faw.AssessmentWindowID = sg.AssessmentWindowID
          AND faw.StudentKey         = sg.StudentKey
          AND faw.rn = 1
    LEFT JOIN FactStudentIPP ipp
           ON ipp.StudentKey    = sg.StudentKey
          AND ipp.Subject       = 'Writing'
          AND ipp.ProgramFamily = CASE WHEN COALESCE(wed.AssessmentLanguage, @Language) = 'French' THEN 'French Immersion' ELSE 'English' END
          AND ipp.IsCurrent     = 1
);
GO

GRANT SELECT ON [dbo].[tvf_TeacherRosterWriting] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 5/9  tvf_StudentCohortWriting.sql
 **********************************************************************/

/*******************************************************************************
 * Function: tvf_StudentCohortWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentCohort for the web app's cohort
 *          screen (Reading|Writing toggle). One row per student in the signed-in
 *          user's scope + their MOST-RECENT writing evidence: the four trait
 *          scores (Ideas/Organization/Language/Conventions), their average, and
 *          the achievement band that average falls in. Plus the Writing-IPP gate.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Achievement band: writing has NO benchmark/delta. The average of the four
 * 1-4 traits maps to a band CODE by fixed cut scores, and that code joins
 * DimAchievementLevel to reuse the SAME band names + colours as reading:
 *     avg >= 3.50 -> 4 Exceeding | >= 2.75 -> 3 Meeting | >= 1.75 -> 2 Approaching | else 1 Not Yet Meeting
 * (No Domain filter needed: we join DimAchievementLevel by code, for name/colour
 * only -- its reading delta bounds are not used here.)
 *
 * Role branches (RegionalAnalyst / Administrator+SpecialistTeacher / Teacher)
 * are identical to tvf_StudentCohort -- caller passed as @UPN. SECURITY: trusts
 * @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortWriting;
GO

CREATE FUNCTION dbo.tvf_StudentCohortWriting(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH LatestWriting AS (
        SELECT
            faw.StudentKey,
            faw.WritingAssessmentID,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
            -- denominator (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha): TRY_CAST('-' AS
            -- INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore,
            ROW_NUMBER() OVER (
                PARTITION BY faw.StudentKey
                ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC
            ) AS rn
        FROM FactAssessmentWriting faw
    ),
    CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        sg.GradeOrder,
        s.SchoolID,
        sch.SchoolName,
        sch.Abbreviation                                        AS SchoolAbbreviation,
        s.ProgramCode,
        p.ProgramFamily,
        s.Gender,
        s.SelfIDAfrican,
        s.SelfIDIndigenous,
        s.Homeroom,
        cwd.IsIPP                                               AS IsIPP_Writing,
        CASE
            WHEN cwd.StudentKey IS NULL THEN 'N/A'
            WHEN cwd.IsIPP IS NULL      THEN 'Unresolved'
            WHEN cwd.IsIPP = 1          THEN 'IPP'
            WHEN cwd.IsIPP = 0          THEN 'Not IPP'
        END                                                     AS IPPStatus_Writing,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        lw.AssessmentDate                                       AS MostRecentAssessmentDate,
        aw.WindowName                                           AS MostRecentWindowName,
        aw.SchoolYear                                           AS MostRecentSchoolYear,
        lw.IdeasScore                                           AS MostRecentIdeasScore,
        lw.OrganizationScore                                    AS MostRecentOrganizationScore,
        lw.LanguageScore                                        AS MostRecentLanguageScore,
        lw.ConventionsScore                                     AS MostRecentConventionsScore,
        lw.AvgScore                                             AS MostRecentAvgScore,
        dal.AchievementLevelCode                                AS MostRecentAchievementLevelCode,
        dal.AchievementLevelName                                AS MostRecentAchievementLevelName,
        dal.HexColor                                            AS MostRecentAchievementHexColor,
        dal.HexColorTint                                        AS MostRecentAchievementHexColorTint
    FROM DimStudent s
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
    LEFT JOIN DimSchool sch ON sch.SchoolID = s.SchoolID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN LatestWriting lw ON lw.StudentKey = s.StudentKey AND lw.rn = 1
    LEFT JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = lw.AssessmentWindowID
    -- Map the average to a band CODE, then reuse DimAchievementLevel's name + colour by code.
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND lw.AvgScore IS NOT NULL
          AND dal.AchievementLevelCode =
              CASE WHEN lw.AvgScore >= 3.50 THEN 4
                   WHEN lw.AvgScore >= 2.75 THEN 3
                   WHEN lw.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.IsCurrent = 1
      AND s.EnrollStatus IN (0, -1)
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortWriting] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 6/9  tvf_StudentAssessmentHistoryWriting.sql
 **********************************************************************/

/*******************************************************************************
 * Function: tvf_StudentAssessmentHistoryWriting  (INLINE table-valued function)
 * Purpose: Writing counterpart of tvf_StudentAssessmentHistory. One row per
 *          (student, writing assessment) for students in the signed-in user's
 *          scope -- the four trait scores, their average, and the achievement
 *          band that average falls in. Powers the per-student detail timeline /
 *          trend line on the Writing tab. Optional @StudentKey scopes to one.
 * Created: 2026-06-25
 * Region: Canada East (PIIDPA compliant)
 *
 * Band: average -> code by fixed cut scores (3.50 / 2.75 / 1.75), joined to
 * DimAchievementLevel by code for name + colour (see tvf_StudentCohortWriting).
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentAssessmentHistoryWriting;
GO

CREATE FUNCTION dbo.tvf_StudentAssessmentHistoryWriting(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH CurrentWritingIPP AS (
        SELECT fsi.StudentKey, fsi.ProgramFamily, fsi.IsIPP
        FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.Subject = 'Writing'
    ),
    WritingRows AS (
        SELECT
            faw.WritingAssessmentID,
            faw.StudentKey,
            faw.AssessmentWindowID,
            faw.IdeasScore,
            faw.OrganizationScore,
            faw.LanguageScore,
            faw.ConventionsScore,
            faw.AssessmentDate,
            -- Average over the NUMERICALLY-SCORED traits only. Count a trait ONLY when it is explicitly
            -- '1'-'4': '-' (excluded), 'SCR' (scribed) and NULL all drop from BOTH numerator and
            -- denominator (never counted as 0). All-dropped -> NULL. NB (Fabric gotcha): TRY_CAST('-' AS
            -- INT) returns 0, NOT NULL — so gate on the explicit allow-list, not TRY_CAST.
            CAST(
                (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                 + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                       + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                AS DECIMAL(5,2)) AS AvgScore
        FROM FactAssessmentWriting faw
    )
    SELECT
        CAST(s.StudentKey AS VARCHAR(20))                       AS StudentKey,
        s.StudentNumber,
        s.FirstName,
        s.LastName,
        s.FirstName + ' ' + s.LastName                          AS FullName,
        s.Grade,
        s.SchoolID,
        p.ProgramFamily                                         AS StudentProgramFamily,
        CAST(
            CASE
                WHEN cwd.StudentKey IS NULL THEN 1
                WHEN cwd.IsIPP = 0          THEN 1
                ELSE 0
            END AS BIT
        )                                                       AS IsChartEligibleWriting,
        CAST(w.WritingAssessmentID AS VARCHAR(20))              AS WritingAssessmentID,
        CAST(w.AssessmentWindowID  AS VARCHAR(20))              AS AssessmentWindowID,
        aw.WindowName,
        aw.AssessmentType,
        aw.SchoolYear                                           AS WindowSchoolYear,
        aw.StartDate                                            AS WindowStartDate,
        aw.EndDate                                              AS WindowEndDate,
        w.AssessmentDate,
        w.IdeasScore,
        w.OrganizationScore,
        w.LanguageScore,
        w.ConventionsScore,
        w.AvgScore,
        dal.AchievementLevelCode,
        dal.AchievementLevelName,
        dal.HexColor                                            AS AchievementHexColor,
        dal.HexColorTint                                        AS AchievementHexColorTint
    FROM WritingRows w
    JOIN DimStudent s ON s.StudentKey = w.StudentKey AND s.IsCurrent = 1
    JOIN DimProgram p ON p.ProgramCode = s.ProgramCode
    JOIN DimAssessmentWindow aw ON aw.AssessmentWindowID = w.AssessmentWindowID
    LEFT JOIN CurrentWritingIPP cwd
           ON cwd.StudentKey    = s.StudentKey
          AND cwd.ProgramFamily = p.ProgramFamily
    LEFT JOIN DimAchievementLevel dal
           ON dal.ActiveFlag = 1
          AND dal.AchievementLevelCode =
              CASE WHEN w.AvgScore >= 3.50 THEN 4
                   WHEN w.AvgScore >= 2.75 THEN 3
                   WHEN w.AvgScore >= 1.75 THEN 2
                   ELSE 1 END
    WHERE s.EnrollStatus IN (0, -1)
      AND (@StudentKey IS NULL OR s.StudentKey = CAST(@StudentKey AS BIGINT))
      AND (
            -- RegionalAnalyst is scoped by StaffSchoolAccess like Admin/SpecialistTeacher (the
            -- buildings in their CanChangeSchool) -- NO region-wide branch. A region-wide analyst
            -- simply has every building in their list.
            EXISTS (
                SELECT 1 FROM StaffSchoolAccess ssa
                WHERE LOWER(ssa.Email) = LOWER(@UPN)
                  AND ssa.SchoolID     = s.SchoolID
                  AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst')
            )
            OR EXISTS (
                SELECT 1
                FROM FactSectionTeachers fst
                JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN)
                  AND fst.IsCurrent = 1
                  AND e.StudentKey  = s.StudentKey
            )
          )
);
GO

GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistoryWriting] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 7/9  tvf_StudentCohortRWM.sql
 **********************************************************************/

/*******************************************************************************
 * Function: tvf_StudentCohortRWM  (INLINE table-valued function)
 * Purpose: READ-ONLY Reading·Writing·Math achievement roll-up for Reports > RWM
 *          (0.7.0, item 5). One row per in-scope Primary-6 student with a 0-3 score:
 *          how many of {Reading, Writing, Math} the student is CURRENTLY meeting or
 *          exceeding (their most-recent result in each area).
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * "Meeting+" per area:
 *   Reading  - most-recent FactAssessmentReading delta -> DimAchievementLevel code IN (3,4).
 *   Writing  - most-recent FactAssessmentWriting trait average -> band code IN (3,4)
 *              (same cut scores as tvf_StudentCohortWriting: avg >= 2.75).
 *   Math     - current-year roll-up = AVERAGE of the student's per-unit averages
 *              (unit avg = AVG(Result) over recorded tasks; blanks are absent rows, so
 *              already excluded) >= 0.75 (Meeting / In-depth).
 *
 * SCOPE: P-6 only (math is P-6; the whole score is defined P-6). EXCLUDES any student
 * with a CONFIRMED IPP (IsIPP = 1) in Reading, Writing, OR Math -- an IPP student is on an
 * individualized plan and isn't measured against these benchmarks. @UPN role gate is the
 * same OR-across-EXISTS branch as the other cohort TVFs (analyst/admin via StaffSchoolAccess;
 * teacher via FactSectionTeachers) -- NO region-wide branch.
 *
 * SECURITY: trusts @UPN; SELECT granted to the SP only. ORDER BY omitted (caller sorts).
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentCohortRWM;
GO

CREATE FUNCTION dbo.tvf_StudentCohortRWM(@UPN VARCHAR(255))
RETURNS TABLE
AS
RETURN
(
    WITH CurYear AS (   -- current school year label (Sep-Aug), matching DimAssessmentWindow.SchoolYear
        SELECT CASE WHEN MONTH(d.Today) >= 9 THEN CONCAT(YEAR(d.Today), '-', YEAR(d.Today) + 1)
                    ELSE CONCAT(YEAR(d.Today) - 1, '-', YEAR(d.Today)) END AS Yr
        FROM (SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today) d
    ),
    MathWins AS (   -- current-year active math windows + their effective benchmark month
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
    ),
    -- In-scope, current, P-6 students (role-gated).
    InScope AS (
        SELECT s.StudentKey, s.StudentNumber, s.FirstName, s.LastName, s.Grade, sg.GradeOrder,
               s.SchoolID, sch.SchoolName, sch.Abbreviation AS SchoolAbbreviation,
               s.ProgramCode, p.ProgramFamily, s.Homeroom
        FROM DimStudent s
        INNER JOIN DimProgram p  ON p.ProgramCode = s.ProgramCode
        INNER JOIN DimGrade   sg ON sg.GradeCode  = s.Grade
        LEFT  JOIN DimSchool  sch ON sch.SchoolID = s.SchoolID
        WHERE s.IsCurrent = 1 AND s.EnrollStatus IN (0, -1) AND sg.GradeOrder BETWEEN 0 AND 6
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment e ON e.SectionKey = sec.SectionKey AND e.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND e.StudentKey = s.StudentKey)
          )
    ),
    -- Any confirmed IPP in ANY of the three subjects removes the student from this report.
    AnyIPP AS (
        SELECT DISTINCT fsi.StudentKey FROM FactStudentIPP fsi
        WHERE fsi.IsCurrent = 1 AND fsi.IsIPP = 1 AND fsi.Subject IN ('Reading', 'Writing', 'Math')
    ),
    -- Most-recent reading -> achievement code (delta mapped through DimAchievementLevel bounds).
    ReadLatest AS (
        SELECT far.StudentKey, far.ReadingDelta, far.AssessmentDate,
               ROW_NUMBER() OVER (PARTITION BY far.StudentKey
                                  ORDER BY far.AssessmentDate DESC, far.ReadingAssessmentID DESC) AS rn
        FROM FactAssessmentReading far
    ),
    ReadAch AS (
        SELECT rl.StudentKey, dal.AchievementLevelCode AS Code
        FROM ReadLatest rl
        LEFT JOIN DimAchievementLevel dal
               ON dal.ActiveFlag = 1
              AND rl.ReadingDelta IS NOT NULL
              AND (dal.LowerBound IS NULL
                   OR (dal.LowerOp = '>=' AND rl.ReadingDelta >= dal.LowerBound)
                   OR (dal.LowerOp = '>'  AND rl.ReadingDelta >  dal.LowerBound)
                   OR (dal.LowerOp = '='  AND rl.ReadingDelta =  dal.LowerBound))
              AND (dal.UpperBound IS NULL
                   OR (dal.UpperOp = '<=' AND rl.ReadingDelta <= dal.UpperBound)
                   OR (dal.UpperOp = '<'  AND rl.ReadingDelta <  dal.UpperBound)
                   OR (dal.UpperOp = '='  AND rl.ReadingDelta =  dal.UpperBound))
        WHERE rl.rn = 1
    ),
    -- Most-recent writing -> trait average -> band code (same cut scores as tvf_StudentCohortWriting).
    -- Traits are VARCHAR: count one ONLY when it is explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
    -- all drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
    -- would hard-CAST '-' and error — so gate on the explicit allow-list.
    WriteLatest AS (
        SELECT faw.StudentKey,
               CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore,
               ROW_NUMBER() OVER (PARTITION BY faw.StudentKey
                                  ORDER BY faw.AssessmentDate DESC, faw.WritingAssessmentID DESC) AS rn
        FROM FactAssessmentWriting faw
    ),
    WriteAch AS (
        SELECT wl.StudentKey,
               CASE WHEN wl.AvgScore IS NULL   THEN NULL
                    WHEN wl.AvgScore >= 3.50   THEN 4
                    WHEN wl.AvgScore >= 2.75   THEN 3
                    WHEN wl.AvgScore >= 1.75   THEN 2
                    ELSE 1 END AS Code
        FROM WriteLatest wl WHERE wl.rn = 1
    ),
    -- Math roll-up: latest result per task (current-year windows) -> per-unit avg -> avg of unit avgs.
    MathLatest AS (
        SELECT fm.StudentKey, fm.MathTaskKey, fm.Result,
               ROW_NUMBER() OVER (PARTITION BY fm.StudentKey, fm.MathTaskKey
                                  ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
        FROM FactAssessmentMath fm
        WHERE fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
    ),
    MathUnit AS (
        SELECT ml.StudentKey, mt.UnitName, AVG(CAST(ml.Result AS FLOAT)) AS UnitAvg
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentKey, mt.UnitName
    ),
    MathRoll AS (   -- blanks EXCLUDED: unit avg over recorded tasks only
        SELECT StudentKey, AVG(UnitAvg) AS RollupPct FROM MathUnit GROUP BY StudentKey
    ),
    -- blanks COUNT-AS-0: denominator = every configured task for the grade's units this year, so an
    -- un-recorded task counts as a miss. Universe = active tasks at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
    ),
    MathUnitOnes AS (   -- recorded 1s per (student, unit)
        SELECT ml.StudentKey, mt.GradeCode, mt.UnitName, SUM(CAST(ml.Result AS INT)) AS Ones
        FROM MathLatest ml
        INNER JOIN DimMathTask mt ON mt.MathTaskKey = ml.MathTaskKey AND mt.ActiveFlag = 1
        WHERE ml.rn = 1
        GROUP BY ml.StudentKey, mt.GradeCode, mt.UnitName
    ),
    MathZeroUnit AS (   -- one row per (student, configured unit): ones / configured (fully-blank unit = 0)
        SELECT isc.StudentKey,
               CAST(COALESCE(mo.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
        FROM InScope isc
        INNER JOIN TaskUniverse tu ON tu.GradeCode = isc.Grade
        LEFT  JOIN MathUnitOnes mo ON mo.StudentKey = isc.StudentKey AND mo.GradeCode = isc.Grade AND mo.UnitName = tu.UnitName
    ),
    MathZeroRoll AS (
        SELECT StudentKey, AVG(UnitAvg) AS RollupPct FROM MathZeroUnit GROUP BY StudentKey
    )
    SELECT
        CAST(isc.StudentKey AS VARCHAR(20))            AS StudentKey,
        isc.StudentNumber,
        isc.FirstName,
        isc.LastName,
        isc.FirstName + ' ' + isc.LastName             AS FullName,
        isc.Grade,
        isc.GradeOrder,
        isc.SchoolID,
        isc.SchoolName,
        isc.SchoolAbbreviation,
        isc.ProgramCode,
        isc.ProgramFamily,
        isc.Homeroom,
        ra.Code                                        AS ReadingCode,
        wa.Code                                        AS WritingCode,
        CAST(mr.RollupPct AS DECIMAL(5,4))             AS MathRollupPct,      -- blanks excluded
        CAST(mz.RollupPct AS DECIMAL(5,4))             AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS ReadingMeeting,
        CAST(CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)          AS WritingMeeting,
        CAST(CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)       AS MathMeeting,
        -- 0-3: how many areas are currently meeting/exceeding.
        (CASE WHEN ra.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wa.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mr.RollupPct >= 0.75 THEN 1 ELSE 0 END)               AS RWMScore,
        -- "has any evidence" per area, so the UI can tell "not meeting" from "no result yet".
        CAST(CASE WHEN ra.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasReading,
        CAST(CASE WHEN wa.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasWriting,
        CAST(CASE WHEN mr.StudentKey IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS HasMath
    FROM InScope isc
    LEFT JOIN ReadAch   ra ON ra.StudentKey = isc.StudentKey
    LEFT JOIN WriteAch  wa ON wa.StudentKey = isc.StudentKey
    LEFT JOIN MathRoll  mr ON mr.StudentKey = isc.StudentKey
    LEFT JOIN MathZeroRoll mz ON mz.StudentKey = isc.StudentKey
    WHERE NOT EXISTS (SELECT 1 FROM AnyIPP ai WHERE ai.StudentKey = isc.StudentKey)
);
GO

GRANT SELECT ON [dbo].[tvf_StudentCohortRWM] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 8/9  tvf_StudentRWMHistory.sql
 **********************************************************************/

/*******************************************************************************
 * Function: tvf_StudentRWMHistory  (INLINE table-valued function)
 * Purpose: Per-cycle RWM trend for the Reports > RWM individual page (0.7.0, item 5).
 *          One row per monthly SCoR cycle in the current school year, carrying the
 *          student's AS-OF standing in each area (most-recent result up to the end of
 *          that month) and the resulting 0-3 RWM score. Powers the per-cycle table +
 *          the trend graph.
 * Created: 2026-09-24
 * Region: Canada East (PIIDPA compliant)
 *
 * A "cycle" here is a calendar month that has >=1 active assessment window this school
 * year (Reading, Writing and Math windows for the same month collapse to one cycle).
 * For each cycle we take the student's most-recent evidence in each area DATED on or
 * before the end of that month, so the 0-3 score is cumulative and reads as a trend.
 * "Meeting+" definitions match tvf_StudentCohortRWM (reading/writing code IN (3,4),
 * math roll-up >= 0.75). @StudentKey passed as VARCHAR to dodge Power Fx BIGINT loss.
 *
 * SECURITY: trusts @UPN; only returns rows when the student is visible to @UPN (same
 * OR-across-EXISTS role gate as the cohort TVFs). SELECT granted to the SP only.
 ******************************************************************************/

DROP FUNCTION IF EXISTS dbo.tvf_StudentRWMHistory;
GO

CREATE FUNCTION dbo.tvf_StudentRWMHistory(@UPN VARCHAR(255), @StudentKey VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    WITH Env AS (
        SELECT CAST(GETDATE() AT TIME ZONE 'UTC' AT TIME ZONE 'Atlantic Standard Time' AS DATE) AS Today
    ),
    CurYear AS (
        SELECT CASE WHEN MONTH(e.Today) >= 9 THEN CONCAT(YEAR(e.Today), '-', YEAR(e.Today) + 1)
                    ELSE CONCAT(YEAR(e.Today) - 1, '-', YEAR(e.Today)) END AS Yr
        FROM Env e
    ),
    MathWins AS (
        SELECT w.AssessmentWindowID,
               COALESCE(w.BenchmarkMonth,
                   (SELECT TOP 1 dc.Month FROM DimCalendar dc
                    WHERE dc.Date BETWEEN w.StartDate AND w.EndDate
                    GROUP BY dc.Month ORDER BY COUNT(*) DESC, dc.Month)) AS BenchMonth
        FROM DimAssessmentWindow w CROSS JOIN CurYear cy
        WHERE w.AssessmentType = 'Math' AND w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
    ),
    -- The student, with grade (drives the count-as-0 task universe).
    Stu AS (
        SELECT s.StudentKey, s.Grade
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.StudentKey = CAST(@StudentKey AS BIGINT)
    ),
    -- Count-as-0 universe: active tasks per (grade, unit) at the current-year math months.
    TaskUniverse AS (
        SELECT mt.GradeCode, mt.UnitName, COUNT(*) AS ConfiguredCount
        FROM DimMathTask mt
        WHERE mt.ActiveFlag = 1 AND mt.AssessmentMonth IN (SELECT BenchMonth FROM MathWins)
        GROUP BY mt.GradeCode, mt.UnitName
    ),
    -- Only proceed when the caller can see this student.
    Visible AS (
        SELECT s.StudentKey
        FROM DimStudent s
        WHERE s.IsCurrent = 1 AND s.StudentKey = CAST(@StudentKey AS BIGINT)
          AND (
                EXISTS (SELECT 1 FROM StaffSchoolAccess ssa
                        WHERE LOWER(ssa.Email) = LOWER(@UPN) AND ssa.SchoolID = s.SchoolID
                          AND ssa.AccessLevel IN ('Administrator', 'SpecialistTeacher', 'RegionalAnalyst'))
             OR EXISTS (SELECT 1 FROM FactSectionTeachers fst
                        INNER JOIN DimSection sec ON sec.SectionID = fst.SectionID AND sec.IsCurrent = 1
                        INNER JOIN FactEnrollment en ON en.SectionKey = sec.SectionKey AND en.ActiveFlag = 1
                        WHERE LOWER(fst.TeacherEmail) = LOWER(@UPN) AND fst.IsCurrent = 1 AND en.StudentKey = s.StudentKey)
          )
    ),
    -- Monthly cycles this school year, up to the current month (no empty future cycles).
    Cycles AS (
        SELECT DISTINCT
               DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1) AS CycleDate,
               EOMONTH(DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1)) AS CycleEnd
        FROM DimAssessmentWindow w
        CROSS JOIN CurYear cy
        CROSS JOIN Env e
        WHERE w.ActiveFlag = 1 AND w.SchoolYear = cy.Yr
          AND DATEFROMPARTS(YEAR(w.StartDate), MONTH(w.StartDate), 1) <= DATEFROMPARTS(YEAR(e.Today), MONTH(e.Today), 1)
    ),
    -- Reading events (dated) with their achievement code.
    ReadEvents AS (
        SELECT far.AssessmentDate, far.ReadingAssessmentID, dal.AchievementLevelCode AS Code
        FROM FactAssessmentReading far
        LEFT JOIN DimAchievementLevel dal
               ON dal.ActiveFlag = 1
              AND far.ReadingDelta IS NOT NULL
              AND (dal.LowerBound IS NULL
                   OR (dal.LowerOp = '>=' AND far.ReadingDelta >= dal.LowerBound)
                   OR (dal.LowerOp = '>'  AND far.ReadingDelta >  dal.LowerBound)
                   OR (dal.LowerOp = '='  AND far.ReadingDelta =  dal.LowerBound))
              AND (dal.UpperBound IS NULL
                   OR (dal.UpperOp = '<=' AND far.ReadingDelta <= dal.UpperBound)
                   OR (dal.UpperOp = '<'  AND far.ReadingDelta <  dal.UpperBound)
                   OR (dal.UpperOp = '='  AND far.ReadingDelta =  dal.UpperBound))
        WHERE far.StudentKey = CAST(@StudentKey AS BIGINT)
    ),
    -- Writing events (dated) with their band code.
    WriteEvents AS (
        SELECT faw.AssessmentDate, faw.WritingAssessmentID,
               CASE WHEN avg4.AvgScore IS NULL THEN NULL
                    WHEN avg4.AvgScore >= 3.50 THEN 4
                    WHEN avg4.AvgScore >= 2.75 THEN 3
                    WHEN avg4.AvgScore >= 1.75 THEN 2
                    ELSE 1 END AS Code
        FROM FactAssessmentWriting faw
        -- Traits are VARCHAR: count one ONLY when explicitly '1'-'4'; '-' (excluded), 'SCR' and NULL
        -- drop. NB (Fabric gotcha): TRY_CAST('-' AS INT) = 0 (not NULL), and a bare COALESCE(IdeasScore,0)
        -- would hard-CAST '-' and error — so gate on the explicit allow-list.
        CROSS APPLY (SELECT CAST(
                   (COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
                    + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0)) * 1.0
                   / NULLIF((CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                          + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0)
                   AS DECIMAL(5,2)) AS AvgScore) avg4
        WHERE faw.StudentKey = CAST(@StudentKey AS BIGINT)
    )
    SELECT
        c.CycleDate,
        DATENAME(MONTH, c.CycleDate) + ' ' + CAST(YEAR(c.CycleDate) AS VARCHAR(4)) AS CycleLabel,
        rc.Code               AS ReadingCode,
        wc.Code               AS WritingCode,
        CAST(mc.RollupPct  AS DECIMAL(5,4)) AS MathRollupPct,      -- blanks excluded
        CAST(mcz.RollupPct AS DECIMAL(5,4)) AS MathRollupPctZero,  -- blanks count as 0
        CAST(CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS ReadingMeeting,
        CAST(CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END AS BIT)     AS WritingMeeting,
        CAST(CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END AS BIT)  AS MathMeeting,
        (CASE WHEN rc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN wc.Code IN (3, 4) THEN 1 ELSE 0 END
         + CASE WHEN mc.RollupPct >= 0.75 THEN 1 ELSE 0 END)          AS RWMScore
    FROM Cycles c
    CROSS JOIN Visible v      -- no rows if the student isn't visible to @UPN
    CROSS JOIN Stu st
    -- most-recent reading on/before this cycle's month end
    OUTER APPLY (
        SELECT TOP 1 re.Code
        FROM ReadEvents re
        WHERE re.AssessmentDate <= c.CycleEnd
        ORDER BY re.AssessmentDate DESC, re.ReadingAssessmentID DESC
    ) rc
    OUTER APPLY (
        SELECT TOP 1 we.Code
        FROM WriteEvents we
        WHERE we.AssessmentDate <= c.CycleEnd
        ORDER BY we.AssessmentDate DESC, we.WritingAssessmentID DESC
    ) wc
    -- math roll-up as-of this cycle: latest result per task on/before month end -> unit avgs -> mean
    OUTER APPLY (
        SELECT AVG(u.UnitAvg) AS RollupPct
        FROM (
            SELECT mt.UnitName, AVG(CAST(x.Result AS FLOAT)) AS UnitAvg
            FROM (
                SELECT fm.MathTaskKey, fm.Result,
                       ROW_NUMBER() OVER (PARTITION BY fm.MathTaskKey
                                          ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
                FROM FactAssessmentMath fm
                WHERE fm.StudentKey = CAST(@StudentKey AS BIGINT)
                  AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
                  AND fm.AssessmentDate <= c.CycleEnd
            ) x
            INNER JOIN DimMathTask mt ON mt.MathTaskKey = x.MathTaskKey AND mt.ActiveFlag = 1
            WHERE x.rn = 1
            GROUP BY mt.UnitName
        ) u
    ) mc
    -- math roll-up as-of this cycle, blanks COUNT-AS-0: ones-so-far / configured, over the grade's
    -- full-year unit universe (fully-blank units = 0), averaged.
    OUTER APPLY (
        SELECT AVG(z.UnitAvg) AS RollupPct
        FROM (
            SELECT tu.UnitName,
                   CAST(COALESCE(o.Ones, 0) AS FLOAT) / NULLIF(tu.ConfiguredCount, 0) AS UnitAvg
            FROM TaskUniverse tu
            LEFT JOIN (
                SELECT mt.UnitName, SUM(CAST(x.Result AS INT)) AS Ones
                FROM (
                    SELECT fm.MathTaskKey, fm.Result,
                           ROW_NUMBER() OVER (PARTITION BY fm.MathTaskKey
                                              ORDER BY fm.AssessmentDate DESC, fm.MathAssessmentID DESC) AS rn
                    FROM FactAssessmentMath fm
                    WHERE fm.StudentKey = CAST(@StudentKey AS BIGINT)
                      AND fm.AssessmentWindowID IN (SELECT AssessmentWindowID FROM MathWins)
                      AND fm.AssessmentDate <= c.CycleEnd
                ) x
                INNER JOIN DimMathTask mt ON mt.MathTaskKey = x.MathTaskKey AND mt.ActiveFlag = 1
                WHERE x.rn = 1
                GROUP BY mt.UnitName
            ) o ON o.UnitName = tu.UnitName
            WHERE tu.GradeCode = st.Grade
        ) z
    ) mcz
);
GO

GRANT SELECT ON [dbo].[tvf_StudentRWMHistory] TO [StudentDataAssessment];
GO


/**********************************************************************
 * 9/9  remediate_writing_trait_exclusion.sql
 **********************************************************************/

/*******************************************************************************
 * Script: remediate_writing_trait_exclusion
 * Purpose: Reconcile EXISTING FactAssessmentWriting rows to the WritingTraitExclusion
 *          config. For any stored row whose (grade x program family x cycle benchmark
 *          month) matches an active exclusion rule, record the excluded trait as the
 *          intentional '-' (deliberately NOT assessed — distinct from NULL = never
 *          recorded) and recompute the stored WritingAverage over the scored traits.
 *
 *          WHY: the upsert proc enforces exclusions only at WRITE time (new/corrected
 *          entries store '-' + a '-'/'SCR'/NULL-aware average). Rows written BEFORE a
 *          rule existed — or seeded/imported directly — still carry a numeric value
 *          under the now-excluded trait, so every recompute-from-traits read (entry
 *          grid, cohort & history TVFs) would keep counting it. This brings stored
 *          data in line and marks those cells with the '-' sentinel.
 *
 *          RUN THIS: once after first deploying WritingTraitExclusion (AND after
 *          migrate_FactWriting_traits_varchar.sql — the trait columns must be VARCHAR
 *          to hold '-'), and again each time an exclusion rule is ADDED/activated for a
 *          grade/program/month that may already hold entries.
 *
 * Reads:   WritingTraitExclusion (ActiveFlag=1), DimStudent (by frozen StudentKey —
 *          the surrogate already pins the grade/program as-of the assessment),
 *          DimProgram, DimAssessmentWindow.
 * Writes:  FactAssessmentWriting — IdeasScore / OrganizationScore / LanguageScore /
 *          ConventionsScore (set to '-' where excluded) + WritingAverage + LastUpdated.
 *
 * IDEMPOTENT: the trait updates are guarded by "value is not already '-'", and the
 *          average recompute lands the same value on a second run — re-running on
 *          clean data changes 0 rows.
 * SAFETY:   affects ONLY rows matching an ACTIVE exclusion rule. Non-matching rows
 *          (any other grade/program/month) are untouched. Depends on VARCHAR trait
 *          columns — run migrate_FactWriting_traits_varchar.sql FIRST.
 * Region:  Canada East (PIIDPA compliant)
 *
 * Benchmark month for a row = its window's BenchmarkMonth, else the window StartDate's
 * calendar month (the monthly-bin fallback) — identical to the proc and roster TVF.
 ******************************************************************************/

SET NOCOUNT ON;

-- A row matches a rule when the frozen DimStudent version for its StudentKey has the
-- rule's grade + program family, and the row's window resolves to the rule's benchmark
-- month. One guarded UPDATE per trait (only Organization has a rule today; the other
-- three are no-ops until a rule names them). Guard "<> '-' OR IS NULL" so an already
-- remediated cell is skipped (idempotent) but a stale numeric or a true NULL is set to '-'.

-- Ideas
UPDATE faw
SET faw.IdeasScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.IdeasScore IS NULL OR faw.IdeasScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Ideas'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Organization
UPDATE faw
SET faw.OrganizationScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.OrganizationScore IS NULL OR faw.OrganizationScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Organization'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Language
UPDATE faw
SET faw.LanguageScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.LanguageScore IS NULL OR faw.LanguageScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Language'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));

-- Conventions (also carries 'SCR'; an exclusion rule still overrides to '-')
UPDATE faw
SET faw.ConventionsScore = '-',
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE (faw.ConventionsScore IS NULL OR faw.ConventionsScore <> '-')
  AND EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1 AND wte.Trait = 'Conventions'
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));
GO

-- Recompute the stored WritingAverage over the scored traits, for every row that matches ANY
-- active exclusion rule. Same formula as usp_UpsertWritingAssessment and the read TVFs: count a
-- trait ONLY when it is explicitly '1'-'4' — '-' (excluded), 'SCR' (scribed) and NULL all drop
-- from BOTH numerator and denominator. All-dropped -> NULL. NB (Fabric gotcha): TRY_CAST('-' AS
-- INT) returns 0, NOT NULL, so gating on TRY_CAST would wrongly count '-' as a scored 0.
UPDATE faw
SET faw.WritingAverage =
        CAST(COALESCE(CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN CAST(faw.IdeasScore        AS INT) END, 0)
             + COALESCE(CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN CAST(faw.OrganizationScore AS INT) END, 0)
             + COALESCE(CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN CAST(faw.LanguageScore     AS INT) END, 0)
             + COALESCE(CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN CAST(faw.ConventionsScore  AS INT) END, 0) AS DECIMAL(6,4))
        / NULLIF( (CASE WHEN faw.IdeasScore        IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN faw.OrganizationScore IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN faw.LanguageScore     IN ('1','2','3','4') THEN 1 ELSE 0 END)
                + (CASE WHEN faw.ConventionsScore  IN ('1','2','3','4') THEN 1 ELSE 0 END), 0),
    faw.LastUpdated = GETDATE()
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
WHERE EXISTS (SELECT 1 FROM WritingTraitExclusion wte
              WHERE wte.ActiveFlag = 1
                AND wte.GradeCode      = ds.Grade
                AND wte.ProgramFamily  = dp.ProgramFamily
                AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)));
GO

-- Verify: after remediation this should return 0 rows (no excluded trait still holds a real
-- score '1'-'4' — each matching cell now reads '-'). NB: test membership in the score allow-list,
-- NOT "TRY_CAST(... ) IS NOT NULL" — on Fabric TRY_CAST('-' AS INT) = 0, which would false-flag
-- every correctly-remediated '-' cell.
SELECT faw.WritingAssessmentID, ds.Grade, dp.ProgramFamily,
       COALESCE(w.BenchmarkMonth, MONTH(w.StartDate)) AS BenchMonth,
       faw.IdeasScore, faw.OrganizationScore, faw.LanguageScore, faw.ConventionsScore, faw.WritingAverage
FROM FactAssessmentWriting faw
JOIN DimStudent         ds ON ds.StudentKey        = faw.StudentKey
JOIN DimProgram         dp ON dp.ProgramCode       = ds.ProgramCode
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = faw.AssessmentWindowID
JOIN WritingTraitExclusion wte
      ON wte.ActiveFlag = 1
     AND wte.GradeCode      = ds.Grade
     AND wte.ProgramFamily  = dp.ProgramFamily
     AND wte.BenchmarkMonth = COALESCE(w.BenchmarkMonth, MONTH(w.StartDate))
WHERE (wte.Trait = 'Ideas'        AND faw.IdeasScore        IN ('1','2','3','4'))
   OR (wte.Trait = 'Organization' AND faw.OrganizationScore IN ('1','2','3','4'))
   OR (wte.Trait = 'Language'     AND faw.LanguageScore     IN ('1','2','3','4'))
   OR (wte.Trait = 'Conventions'  AND faw.ConventionsScore  IN ('1','2','3','4'));
GO
