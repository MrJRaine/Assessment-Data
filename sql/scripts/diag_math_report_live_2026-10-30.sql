/*******************************************************************************
 * Diagnostic: live /reports/math "Couldn't load data" (2026-10-30)
 * READ-ONLY. No student rows returned — counts and object metadata only.
 * Run on LIVE. Each part is independent; run top to bottom and note which part
 * errors or hangs — that IS the finding.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ---------------------------------------------------------------------------
-- 1) Is the deployed TVF the 1.3.0 (TAUGHT-arm) version, and does the drill
--    TVF exist? Returns one row per object with a version marker.
-- ---------------------------------------------------------------------------
SELECT o.name,
       o.modify_date,
       CASE WHEN m.definition LIKE '%TAUGHT%' THEN '1.3.0 (taught arm present)'
            ELSE 'pre-1.3.0 (oversight only)' END AS VersionMarker,
       LEN(m.definition) AS DefinitionLength
FROM sys.objects o
INNER JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name IN ('tvf_StudentCohortMathAll', 'tvf_StudentCohortMath');

-- ---------------------------------------------------------------------------
-- 2) Does the tree feed RUN, and how long does it take? COUNT only — no PII.
--    Uses the project lead's UPN (sysadmin/analyst scope = the heavy case).
--    If this errors, the message is the root cause. If it runs but takes
--    tens of seconds, the app side is timing out — note the elapsed time.
-- ---------------------------------------------------------------------------
DECLARE @t0 DATETIME2(3) = SYSDATETIME();
SELECT COUNT(*) AS TreeRows
FROM dbo.tvf_StudentCohortMathAll('jeffrey.raine@tcrce.ca', NULL);
SELECT DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS ElapsedMs_All;

-- ---------------------------------------------------------------------------
-- 3) Same check for a single-cycle call (the page may pass a cycle id).
--    Picks the most recent ACTIVE math cycle automatically.
-- ---------------------------------------------------------------------------
DECLARE @Cycle VARCHAR(36);
SELECT TOP 1 @Cycle = CycleGroupID
FROM DimAssessmentWindow
WHERE AssessmentType = 'Math' AND ActiveFlag = 1 AND CycleGroupID IS NOT NULL
ORDER BY StartDate DESC;

SELECT @Cycle AS CycleTested;

DECLARE @t1 DATETIME2(3) = SYSDATETIME();
SELECT COUNT(*) AS TreeRowsCycle
FROM dbo.tvf_StudentCohortMathAll('jeffrey.raine@tcrce.ca', @Cycle);
SELECT DATEDIFF(MILLISECOND, @t1, SYSDATETIME()) AS ElapsedMs_Cycle;
