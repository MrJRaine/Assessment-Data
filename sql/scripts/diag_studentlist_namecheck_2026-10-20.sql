/*******************************************************************************
 * DIAGNOSTIC (read-only) — is the "duplicate student" look in the stacked reading list a
 * synthetic NAME COLLISION, or a real duplication bug? Run on dev. No writes.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- 1) NAME COLLISION: synthetic names shared by MORE THAN ONE distinct student (StudentNumber).
--    If this returns rows (e.g. "Ash, Avery" -> 3 students), the stacked list is correct — those
--    same-named rows are DIFFERENT students, which is why their levels differ and they don't merge.
SELECT LastName, FirstName, COUNT(DISTINCT StudentNumber) AS DistinctStudents
FROM DimStudent
WHERE IsCurrent = 1 AND EnrollStatus IN (0, -1)
GROUP BY LastName, FirstName
HAVING COUNT(DISTINCT StudentNumber) > 1
ORDER BY DistinctStudents DESC, LastName, FirstName;

-- 2) STACKED-CURRENT guard: a real bug would be the SAME StudentNumber having >1 IsCurrent=1 row
--    (stacked SCD markers), which WOULD multiply rows. Expect ZERO rows.
SELECT StudentNumber, COUNT(*) AS CurrentRows
FROM DimStudent
WHERE IsCurrent = 1
GROUP BY StudentNumber
HAVING COUNT(*) > 1;

-- 3) DUP-LANGUAGE guard: does any single StudentNumber have >1 reading result of the SAME scale among
--    current-year windows (which the TVF's PARTITION BY (StudentNumber, ScaleSystem) rn=1 should collapse
--    to one)? Expect ZERO — if non-zero, the latest-pick isn't deduping (a real TVF bug to chase).
SELECT far.StudentNumber, drs.ScaleSystem, COUNT(*) AS Results
FROM FactAssessmentReading far
JOIN DimReadingScale drs ON drs.ReadingScaleID = far.ReadingScaleID
JOIN DimAssessmentWindow w ON w.AssessmentWindowID = far.AssessmentWindowID AND w.AssessmentType = 'Reading' AND w.ActiveFlag = 1
GROUP BY far.StudentNumber, drs.ScaleSystem
HAVING COUNT(*) > 1
ORDER BY Results DESC;
-- NB: query 3 counting >1 is EXPECTED/fine (a student can have several EN results across the year);
-- the TVF keeps only the latest. It's only a problem if query 1 returns NOTHING yet the UI still shows
-- two same-named rows with different levels — then dig into the TVF. Query 1 returning rows = collision = not a bug.
