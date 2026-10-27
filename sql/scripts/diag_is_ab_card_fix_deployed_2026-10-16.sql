/*******************************************************************************
 * Script: diag_is_ab_card_fix_deployed_2026-10-16.sql   (LIVE — READ ONLY; metadata only, no data)
 * Purpose: Settle whether the A+B card-count / current-teacher fix
 *          (sql/deploy/live_1.2.0/deploy_card_section_stable_teacher_current_2026-10-13.sql) was
 *          actually deployed to the live warehouse. That patch redeployed 6 objects, each stamped with
 *          a comment marker UNIQUE to the A+B change (not present in the earlier section-stable roster
 *          patch). This checks the LIVE object definitions for those markers.
 *
 *          Reading the result:
 *            - every row 'A+B PRESENT'            -> the fix IS live; nothing to deploy (just confirm the
 *                                                    changelog bullet stands).
 *            - any row 'A+B MISSING'              -> that object is still the older pre-A+B version ->
 *                                                    the A+B patch has NOT been (fully) deployed; run it.
 *            - any row 'OBJECT NOT FOUND'         -> name/schema mismatch — tell me and I'll adjust.
 *
 * Reads:  sys.objects, sys.sql_modules (object definitions only — NO student/staff data).
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

SELECT
    mk.obj AS ObjectName,
    CASE
        WHEN o.object_id IS NULL                                  THEN 'OBJECT NOT FOUND'
        WHEN m.definition LIKE '%' + mk.marker + '%'              THEN 'A+B PRESENT'
        ELSE                                                           'A+B MISSING (older version live)'
    END AS Status
FROM (VALUES
    -- Markers MUST live inside the module body (after CREATE). A marker in the file's leading header
    -- comment is stripped from sys.sql_modules.definition (the module is stored from CREATE onward), so
    -- it reads as a false MISSING — that's what bit the first two rows in the 2026-10-16 run.
    ('usp_RebuildRosterMembership', 'CURRENT teacher gets the fast-path for EVERY cycle'),
    ('tvf_UserAssessmentWindows',   'the current teacher sees every cycle of the year for their'),
    ('tvf_TeacherGroups',           'the current teacher of a section sees EVERY cycle'),
    ('tvf_TeacherRoster',           'CURRENT teacher sees every cycle'),
    ('tvf_TeacherRosterWriting',    'CURRENT teacher sees every cycle'),
    ('tvf_TeacherRosterMath',       'CURRENT teacher sees every cycle')
) AS mk(obj, marker)
LEFT JOIN sys.objects     o ON o.name = mk.obj AND o.schema_id = SCHEMA_ID('dbo')
LEFT JOIN sys.sql_modules m ON m.object_id = o.object_id
ORDER BY mk.obj;
GO
