/*******************************************************************************
 * Diagnostic: reading/writing report "Couldn't load data" (2026-10-30 evening)
 * READ-ONLY. Two probes:
 *   1. INVENTORY — every object the report pages call, with PRESENT/MISSING.
 *      A MISSING row is the outage (Msg 208 server-side).
 *   2. STOWAWAY SCAN — any stored procedure whose compiled body contains a
 *      DROP statement (the usp_MergeStaff failure mode: a fused batch hides a
 *      DROP inside a proc and every execution deletes an object). Our procs
 *      legitimately contain NO DROPs, so any hit names the culprit.
 * Run on LIVE. Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ---------------------------------------------------------------------------
-- 1) INVENTORY of report-critical objects
-- ---------------------------------------------------------------------------
SELECT exp.name AS ObjectName,
       CASE WHEN o.object_id IS NULL THEN '*** MISSING ***' ELSE 'present' END AS Status,
       o.modify_date
FROM (VALUES
    ('tvf_StudentCohort'),
    ('tvf_StudentCohortWriting'),
    ('tvf_StudentCohortReadingAll'),
    ('tvf_StudentCohortReadingGroup'),
    ('tvf_StudentCohortWritingAll'),
    ('tvf_StudentCohortWritingGroup'),
    ('tvf_StudentCohortMathAll'),
    ('tvf_StudentCohortMath'),
    ('tvf_StudentCohortRWM'),
    ('vw_StudentReadingStartingPoint'),
    ('tvf_TeacherGroups'),
    ('usp_RebuildRosterMembership'),
    ('usp_MergeStaff'),
    ('usp_RunDataQualityChecks')
) AS exp(name)
LEFT JOIN sys.objects o ON o.name = exp.name
ORDER BY CASE WHEN o.object_id IS NULL THEN 0 ELSE 1 END, exp.name;

-- ---------------------------------------------------------------------------
-- 2) STOWAWAY SCAN — procs whose body contains a DROP (expect ZERO rows)
-- ---------------------------------------------------------------------------
SELECT o.name AS ProcWithEmbeddedDrop,
       o.modify_date
FROM sys.sql_modules m
INNER JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.type = 'P'
  AND (m.definition LIKE '%DROP FUNCTION%'
    OR m.definition LIKE '%DROP VIEW%'
    OR m.definition LIKE '%DROP PROCEDURE%'
    OR m.definition LIKE '%DROP TABLE%')
ORDER BY o.name;
