/*******************************************************************************
 * Script: seed_teacher_handover_fixture_dev.sql
 * Purpose: DEV ONLY (Assessment_Warehouse_Dev). Build the two FactSectionTeachers
 *          fixtures the Missing-results historic-teacher checks need (testing plan
 *          1.4.0 §1), using Morgan Hazel's two base-ELEM sections at school 0079:
 *
 *          1. MID-CYCLE HANDOVER — section ELA-45-EN:
 *             Morgan Hazel (teach.elem.en.45@tcrce.ca) Primary 2026-09-01→2026-10-14,
 *             then NEW synthetic teacher Rowan Aspen (handover.teacher.0079@tcrce.ca)
 *             Primary 2026-10-15→current.
 *             EXPECT: Sep cycle lists ELA-45-EN under Morgan Hazel; the Nov cycle
 *             (and later) lists it under Rowan Aspen.
 *
 *          2. NO LEAD TEACHER — section MAT-45-EN:
 *             Morgan's Primary row is DELETED (no Primary overlaps ANY cycle).
 *             EXPECT: MAT-45-EN under the visible "No lead teacher" node, every cycle.
 *
 * Writes:
 *   DimStaff            — +1 identity row (Rowan Aspen, Teacher, school 0079) if absent
 *   FactSectionTeachers — ELA-45-EN: Morgan's Primary row re-dated/closed + Rowan's
 *                         Primary row inserted; MAT-45-EN: Morgan's Primary row DELETED
 * Reads: DimSection (resolve the two SectionIDs by CourseCode at school 0079),
 *        DimAssessmentWindow (verification preview only).
 *
 * Idempotent: every write is guarded; a re-run changes nothing.
 * SELF-REVERTING: the next dev staff/section ingest rebuilds FactSectionTeachers from
 *   staging — Morgan comes back as current Primary on both sections and Rowan's
 *   assignment closes (he stays as a harmless inactive DimStaff identity). No manual
 *   revert needed; to revert sooner, just re-run the ingest cycle.
 * SIDE EFFECT while active: Morgan Hazel loses CURRENT entry access to these two
 *   sections (entry visibility reads FactSectionTeachers live); Rowan gains ELA-45-EN.
 *   Dev-only and intended — it is exactly the condition under test.
 *
 * Created: 2026-11-13   Region: Canada East (PIIDPA compliant) — synthetic, no real PII
 ******************************************************************************/

DECLARE @MorganEmail  VARCHAR(255) = 'teach.elem.en.45@tcrce.ca';
DECLARE @RowanEmail   VARCHAR(255) = 'handover.teacher.0079@tcrce.ca';
DECLARE @School       VARCHAR(10)  = '0079';
DECLARE @HandoverEnd  DATE         = '2026-10-14';  -- Morgan's last day on ELA-45-EN
DECLARE @HandoverNew  DATE         = '2026-10-15';  -- Rowan's first day
DECLARE @SeasonStart  DATE         = '2026-09-01';  -- forced start of Morgan's closed stint

DECLARE @ElaSection VARCHAR(50) =
    (SELECT SectionID FROM DimSection
     WHERE CourseCode = 'ELA-45-EN' AND SchoolID = @School AND IsCurrent = 1);
DECLARE @MatSection VARCHAR(50) =
    (SELECT SectionID FROM DimSection
     WHERE CourseCode = 'MAT-45-EN' AND SchoolID = @School AND IsCurrent = 1);

-- ---- 0. Guard: both sections must resolve --------------------------------------
IF @ElaSection IS NULL OR @MatSection IS NULL
BEGIN
    SELECT 'ABORT - section not found (ELA-45-EN / MAT-45-EN at 0079); nothing changed. '
         + 'ELA=' + COALESCE(@ElaSection, 'NULL') + ' MAT=' + COALESCE(@MatSection, 'NULL')
           AS Result;
END
ELSE
BEGIN
    -- ---- 1. Rowan Aspen identity row (Teacher: AccessLevel NULL) -----------------
    INSERT INTO DimStaff
        (Email, FirstName, LastName, Title, HomeSchoolID, CanChangeSchool, IsDistrictLevel,
         ActiveFlag, AccessLevel, EffectiveStartDate, EffectiveEndDate, IsCurrent, LastUpdated)
    SELECT @RowanEmail, 'Rowan', 'Aspen', 'Teacher', @School, NULL, 0,
           1, NULL, @HandoverNew, NULL, 1, GETDATE()
    WHERE NOT EXISTS (SELECT 1 FROM DimStaff WHERE Email = @RowanEmail AND IsCurrent = 1);

    -- ---- 2. HANDOVER on ELA-45-EN: close Morgan 09-01..10-14 ----------------------
    -- (Start is forced too, so the stint overlaps the Sep cycle regardless of what the
    --  last ingest stamped as the row's start date.)
    UPDATE FactSectionTeachers
    SET EffectiveStartDate = @SeasonStart, EffectiveEndDate = @HandoverEnd,
        IsCurrent = 0, LastUpdated = GETDATE()
    WHERE SectionID = @ElaSection AND TeacherEmail = @MorganEmail
      AND TeacherRole = 'Primary' AND IsCurrent = 1;

    -- ---- 3. Rowan takes ELA-45-EN from 10-15 --------------------------------------
    INSERT INTO FactSectionTeachers
        (SectionID, TeacherEmail, TeacherRole, EffectiveStartDate, EffectiveEndDate,
         IsCurrent, SourceSystemID, LastUpdated)
    SELECT @ElaSection, @RowanEmail, 'Primary', @HandoverNew, NULL, 1, 'DEV-HANDOVER', GETDATE()
    WHERE NOT EXISTS (SELECT 1 FROM FactSectionTeachers
                      WHERE SectionID = @ElaSection AND TeacherEmail = @RowanEmail
                        AND TeacherRole = 'Primary' AND IsCurrent = 1);

    -- ---- 4. NO-LEAD on MAT-45-EN: delete the Primary row --------------------------
    -- (Deleted, not closed: a closed stint would still overlap whichever cycle covered
    --  it. The next ingest re-inserts the triple from staging, restoring normality.)
    DELETE FROM FactSectionTeachers
    WHERE SectionID = @MatSection AND TeacherEmail = @MorganEmail
      AND TeacherRole = 'Primary';

    -- ---- 5. Verify: the raw rows -----------------------------------------------
    SELECT 'FST rows' AS Src, fst.SectionID, ds.CourseCode, fst.TeacherEmail,
           fst.TeacherRole, fst.EffectiveStartDate, fst.EffectiveEndDate, fst.IsCurrent
    FROM FactSectionTeachers fst
    INNER JOIN DimSection ds ON ds.SectionID = fst.SectionID AND ds.IsCurrent = 1
    WHERE fst.SectionID IN (@ElaSection, @MatSection)
    ORDER BY fst.SectionID, fst.EffectiveStartDate;

    -- ---- 6. Verify: per-cycle resolution preview (mirrors tvf_MissingDataAll's
    --         LeadTeacher logic). EXPECT per cycle:
    --           ELA-45-EN — Sep cycle: Morgan Hazel; Nov cycle onward: Rowan Aspen
    --           MAT-45-EN — every cycle: 'No lead teacher'
    WITH Cycles AS (
        SELECT w.CycleGroupID, MIN(w.StartDate) AS CycleStart, MAX(w.EndDate) AS CycleEnd
        FROM DimAssessmentWindow w
        WHERE w.ActiveFlag = 1 AND w.CycleGroupID IS NOT NULL
        GROUP BY w.CycleGroupID
    ),
    Fixture AS (
        SELECT @ElaSection AS SectionID UNION ALL SELECT @MatSection
    ),
    Resolved AS (
        SELECT c.CycleGroupID, c.CycleStart, c.CycleEnd, f.SectionID, fst.TeacherEmail,
               ROW_NUMBER() OVER (PARTITION BY c.CycleGroupID, f.SectionID
                                  ORDER BY fst.EffectiveStartDate DESC, fst.TeacherEmail) AS rn
        FROM Cycles c
        CROSS JOIN Fixture f
        LEFT JOIN FactSectionTeachers fst
               ON fst.SectionID = f.SectionID AND fst.TeacherRole = 'Primary'
              AND fst.EffectiveStartDate <= c.CycleEnd
              AND (fst.EffectiveEndDate IS NULL OR fst.EffectiveEndDate >= c.CycleStart)
    )
    SELECT r.CycleGroupID, r.CycleStart, r.CycleEnd, ds.CourseCode,
           COALESCE(r.TeacherEmail, 'No lead teacher') AS ResolvedLeadTeacher
    FROM Resolved r
    INNER JOIN DimSection ds ON ds.SectionID = r.SectionID AND ds.IsCurrent = 1
    WHERE r.rn = 1
    ORDER BY r.CycleStart, ds.CourseCode;
END
