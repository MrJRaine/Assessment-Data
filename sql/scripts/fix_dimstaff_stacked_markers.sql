/*******************************************************************************
 * Script: fix_dimstaff_stacked_markers.sql   (LIVE + DEV data remediation)
 * Purpose: Collapse stacked current DimStaff rows to ONE per email, clearing the
 *          DQ "multiple IsCurrent=1 rows" (#18) and "overlapping windows" (#29)
 *          checks. Companion to the usp_MergeStaff 4c guard (2026-09-08): repeat
 *          same-day ingests after a teacher was deactivated stacked duplicate
 *          [today, NULL] deactivation markers; the proc guard stops NEW stacking,
 *          this cleans what already stacked.
 * Created: 2026-09-05  (rev 2026-09-08: delete surplus CURRENT markers)
 * Region:  Canada East (PIIDPA compliant).
 *
 * Fix: keep the newest current row per email (max StaffKey), delete the surplus
 * ones -- self-gated so it only removes a row that NO fact references (never
 * orphans FactStaffAssignment / StaffSchoolAccess / assessment EnteredBy). A
 * single current row per email is untouched. Idempotent. If the pre-check shows
 * any surplus row with a reference count > 0, STOP and tell me.
 *
 * DEPLOY the usp_MergeStaff 4c guard FIRST, then run this -- otherwise the next
 * same-day ingest re-stacks.
 ******************************************************************************/

-- 0) Pre-check: every current row for any email that has more than one, with the
--    surplus rows' fact-reference counts. StaffKey is a surrogate int (not PII).
--    The MAX-StaffKey row per email is the KEEPER; the rest are deletion targets.
SELECT
    d.StaffKey, d.EffectiveStartDate, d.EffectiveEndDate, d.IsCurrent, d.ActiveFlag,
    CASE WHEN d.StaffKey = (SELECT MAX(c.StaffKey) FROM DimStaff c
                            WHERE c.Email = d.Email AND c.IsCurrent = 1)
         THEN 'KEEP' ELSE 'delete' END AS Disposition,
    (SELECT COUNT(*) FROM FactStaffAssignment   f WHERE f.StaffKey        = d.StaffKey) AS AssignRows,
    (SELECT COUNT(*) FROM StaffSchoolAccess     a WHERE a.StaffKey        = d.StaffKey) AS SsaRows,
    (SELECT COUNT(*) FROM FactAssessmentReading r WHERE r.EnteredByStaffKey = d.StaffKey) AS EnteredReading,
    (SELECT COUNT(*) FROM FactAssessmentWriting  w WHERE w.EnteredByStaffKey = d.StaffKey) AS EnteredWriting
FROM DimStaff d
WHERE d.IsCurrent = 1
  AND d.Email IN (SELECT Email FROM DimStaff WHERE IsCurrent = 1 GROUP BY Email HAVING COUNT(*) > 1)
ORDER BY d.StaffKey;

-- 1) Delete the surplus current rows (keep max StaffKey per email) -- ONLY when unreferenced.
DELETE FROM DimStaff
WHERE IsCurrent = 1
  AND StaffKey < (SELECT MAX(c.StaffKey) FROM DimStaff c
                  WHERE c.Email = DimStaff.Email AND c.IsCurrent = 1)
  AND NOT EXISTS (SELECT 1 FROM FactStaffAssignment   f WHERE f.StaffKey        = DimStaff.StaffKey)
  AND NOT EXISTS (SELECT 1 FROM StaffSchoolAccess     a WHERE a.StaffKey        = DimStaff.StaffKey)
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentReading r WHERE r.EnteredByStaffKey = DimStaff.StaffKey)
  AND NOT EXISTS (SELECT 1 FROM FactAssessmentWriting  w WHERE w.EnteredByStaffKey = DimStaff.StaffKey);

-- Verify 1 -- duplicate current rows: expect ZERO.
SELECT Email, COUNT(*) AS CurrentRows
FROM DimStaff WHERE IsCurrent = 1 GROUP BY Email HAVING COUNT(*) > 1;

-- Verify 2 -- overlapping windows: expect ZERO.
SELECT a.Email
FROM DimStaff a
INNER JOIN DimStaff b ON b.Email = a.Email AND a.StaffKey < b.StaffKey
WHERE a.EffectiveStartDate <= COALESCE(b.EffectiveEndDate, '9999-12-31')
  AND COALESCE(a.EffectiveEndDate, '9999-12-31') >= b.EffectiveStartDate;
