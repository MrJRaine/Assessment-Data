/*******************************************************************************
 * Script: diag_live_deployed_proc_versions.sql   (LIVE or DEV — read-only metadata)
 * Purpose: Verify that the ACTUALLY-DEPLOYED proc definitions in the warehouse carry the
 *          expected version fingerprints — because a mass/bundle deploy can silently skip an
 *          object, and "it's in GitHub" does not prove "it ran on live." Reads each proc's
 *          stored definition from sys.sql_modules and checks for a distinctive marker string.
 *
 * Reads: sys.objects, sys.sql_modules ONLY (catalog metadata). No app tables, no writes, no PII.
 *
 * HOW TO READ Status:
 *   PRESENT                  -> the expected version IS deployed here.
 *   OLD/UNEXPECTED VERSION   -> the proc exists but its definition lacks the marker -> an older
 *                               version is live (got missed in the deploy).
 *   PROC MISSING             -> no such proc in this warehouse at all.
 *
 * NOTE on EXPECTED state at 2026-10-07: the 51014 reading fix (v1.0.1) is only expected on live
 *   AFTER you deploy usp_UpsertReadingAssessment.sql there — until then "OLD/UNEXPECTED VERSION"
 *   for that row is correct, not a defect. The #1119 loaders (Workspace Identity) and the math
 *   grace-lock are already live, so those should read PRESENT.
 *
 * Collation note: the warehouse is BIN2 (case-sensitive) — markers below match the exact case in
 *   the source. If sys.sql_modules is unavailable, swap to OBJECT_DEFINITION(o.object_id).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

-- (ProcName, Marker = distinctive string the DEPLOYED version must contain, Meaning)
WITH Expected AS (
    SELECT * FROM (VALUES
        ('usp_UpsertReadingAssessment', '%COALESCE(@WindowScaleSystem%', '51014 instance-based scale fix (v1.0.1) — late-immersion English reading'),
        ('usp_UpsertMathAssessment',    '%CanOverrideMath%',             'math grace-lock override (0.7.0+)'),
        ('usp_UpsertWritingAssessment', '%AssessmentLanguage%',          'writing carries AssessmentLanguage (dual-language)'),
        ('usp_LoadStudentsStaging',     '%Workspace Identity%',          '#1119 WI credential on loader'),
        ('usp_LoadStaffStaging',        '%Workspace Identity%',          '#1119 WI credential on loader'),
        ('usp_LoadSectionStaging',      '%Workspace Identity%',          '#1119 WI credential on loader'),
        ('usp_LoadEnrollmentStaging',   '%Workspace Identity%',          '#1119 WI credential on loader'),
        ('usp_LoadCoTeacherStaging',    '%Workspace Identity%',          '#1119 WI credential on loader')
    ) v(ProcName, Marker, Meaning)
)
SELECT
    e.ProcName,
    e.Meaning,
    CASE
        WHEN o.object_id IS NULL          THEN 'PROC MISSING'
        WHEN m.definition LIKE e.Marker   THEN 'PRESENT'
        ELSE 'OLD/UNEXPECTED VERSION'
    END AS Status,
    o.modify_date AS LastAltered   -- when this proc was last (re)created on THIS warehouse
FROM Expected e
LEFT JOIN sys.objects     o ON o.name = e.ProcName AND o.type_desc = 'SQL_STORED_PROCEDURE'
LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id
ORDER BY e.ProcName;
