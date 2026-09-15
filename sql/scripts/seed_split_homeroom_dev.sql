/*******************************************************************************
 * Script: seed_split_homeroom_dev.sql   (DEV / SYNTHETIC ONLY — never run on live)
 * Purpose: Turn the DEVSEED Drumlin Primary homeroom (from
 *          seed_primary_homeroom_dev.sql) into a MULTI-GRADE split so the grade
 *          filter's grade-span behaviour can be tested: a homeroom card that
 *          contains more than one grade must surface under EACH of its grades.
 *          Flips a handful of the 20 grade-P students to grades 1 and 2, keeping
 *          the same GroupKey/Homeroom, giving a P / 1 / 2 split (3 grades).
 *
 * Prereq: run seed_primary_homeroom_dev.sql first (creates the 20 DEVSEED
 *          students 8000000001-8000000020). This script only re-grades them.
 * To view: impersonate an oversight role (e.g. a RegionalAnalyst) -> Data Entry
 *          -> a Reading/Writing cycle -> "All groups" Homeroom lens. The Drumlin
 *          "Primary Homeroom PA" card now carries grades P,1,2 and appears when
 *          ANY of P / 1 / 2 is checked in the grade filter.
 * Reset:  the RESET block at the bottom puts every DEVSEED student back to 'P'.
 *
 * Note: DimStudent is SCD Type 2, but this is a synthetic test fixture — a blunt
 *       in-place Grade UPDATE is intentional (we're not exercising SCD here).
 ******************************************************************************/

DECLARE @Now DATETIME2(0) = GETDATE();

IF NOT EXISTS (
    SELECT 1 FROM DimStudent
    WHERE SourceSystemID = 'DEVSEED' AND IsCurrent = 1
      AND StudentNumber BETWEEN 8000000001 AND 8000000020
)
BEGIN
    ;THROW 60010, 'seed_split_homeroom_dev: DEVSEED Primary homeroom not found. Run seed_primary_homeroom_dev.sql first.', 1;
END;

-- 5 students -> grade 1
UPDATE DimStudent
   SET Grade = '1', LastUpdated = @Now
 WHERE SourceSystemID = 'DEVSEED' AND IsCurrent = 1
   AND StudentNumber BETWEEN 8000000014 AND 8000000018;

-- 2 students -> grade 2
UPDATE DimStudent
   SET Grade = '2', LastUpdated = @Now
 WHERE SourceSystemID = 'DEVSEED' AND IsCurrent = 1
   AND StudentNumber BETWEEN 8000000019 AND 8000000020;

-- verify the split (synthetic — safe to display)
SELECT s.GroupKey, s.Homeroom,
       STRING_AGG(CONVERT(VARCHAR(10), s.Grade), ',') WITHIN GROUP (ORDER BY g.GradeOrder) AS GradesPresent,
       COUNT(*) AS Students
FROM DimStudent s
LEFT JOIN DimGrade g ON g.GradeCode = s.Grade
WHERE s.SourceSystemID = 'DEVSEED' AND s.IsCurrent = 1
GROUP BY s.GroupKey, s.Homeroom;
GO

/* ============================================================================
 * RESET — put every DEVSEED student back to grade P (Dev only).
 * ============================================================================
-- UPDATE DimStudent
--    SET Grade = 'P', LastUpdated = GETDATE()
--  WHERE SourceSystemID = 'DEVSEED' AND IsCurrent = 1
--    AND StudentNumber BETWEEN 8000000001 AND 8000000020;
-- GO
 * ========================================================================== */
