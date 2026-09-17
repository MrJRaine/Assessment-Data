/*******************************************************************************
 * Script: migrate_FactWriting_conventions_varchar.sql
 * Purpose: Change FactAssessmentWriting.ConventionsScore from INT to VARCHAR(10)
 *          so it can hold the "SCR" (Scribed) code alongside '1'-'4'. Fabric has no
 *          ALTER COLUMN (type change) and we avoid a full table rebuild, so this does
 *          a multi-step column swap that PRESERVES existing data and the column NAME:
 *            add temp VARCHAR -> copy INT->VARCHAR -> drop INT col -> re-add VARCHAR
 *            under the original name -> copy back -> drop temp.
 *          Each step is its own batch (GO) so the parser only sees existing columns
 *          (see the fabric-warehouse-sql skill: catalog-check-in-same-batch gotcha).
 * SCR = Scribed on Conventions only (someone else physically wrote for the student, so
 *          conventions aren't the student's own production). SCR is OMITTED from the
 *          writing average (sum/count over the SCORED traits) — see the reads + proc.
 * Created: 2026-09-17
 * Region: Canada East (PIIDPA compliant)
 *
 * RUN ONCE per warehouse (dev, then live at the 0.5.0 release). Ideas/Organization/
 * Language stay INT. Safe on an empty table too (the UPDATEs just touch 0 rows).
 ******************************************************************************/

-- 1) temp VARCHAR column, seeded from the existing INT.
ALTER TABLE FactAssessmentWriting ADD ConventionsScoreTmp VARCHAR(10) NULL;
GO
UPDATE FactAssessmentWriting
   SET ConventionsScoreTmp = CAST(ConventionsScore AS VARCHAR(10))
 WHERE ConventionsScore IS NOT NULL;
GO

-- 2) drop the INT column, re-add it as VARCHAR (same name).
ALTER TABLE FactAssessmentWriting DROP COLUMN ConventionsScore;
GO
ALTER TABLE FactAssessmentWriting ADD ConventionsScore VARCHAR(10) NULL;
GO

-- 3) copy back and drop the temp.
UPDATE FactAssessmentWriting
   SET ConventionsScore = ConventionsScoreTmp
 WHERE ConventionsScoreTmp IS NOT NULL;
GO
ALTER TABLE FactAssessmentWriting DROP COLUMN ConventionsScoreTmp;
GO

-- verify (dev/synthetic — safe to display): distinct conventions values now include codes.
SELECT ConventionsScore, COUNT(*) AS Rows
FROM FactAssessmentWriting
GROUP BY ConventionsScore
ORDER BY ConventionsScore;
GO
