/*******************************************************************************
 * Script: diag_staff_email_reconcile_check_dev.sql   (DEV only — READ ONLY)
 * Purpose: Verify §7.2 — a corrected staff email RENAMES the account in place
 *          (same person, access intact) rather than spawning a NULL-access ghost.
 *          Run AFTER editing Pat Willow's email in StaffExport.csv + re-ingesting.
 * Reads:  DimStaff, FactStaffAssignment, StaffSchoolAccess, FactSubmissionAudit.
 * Created: 2026-10-26 · Region: Canada East (PIIDPA compliant) · SYNTHETIC dev only.
 ******************************************************************************/

IF DB_NAME() NOT LIKE '%[_]Dev%'
BEGIN
    ;THROW 50000, 'diag_staff_email_reconcile_check_dev is DEV ONLY. Current DB is not a _Dev warehouse — aborting.', 1;
END;

-- A. All DimStaff rows for Pat Willow (current + historical). EXPECT: exactly ONE IsCurrent=1 row,
--    under the NEW email, with a non-NULL AccessLevel. A second current row or a NULL-access row under
--    the OLD email = a ghost (reconciliation failed).
SELECT 'A. DimStaff rows' AS Stage, StaffKey, Email, AccessLevel, IsCurrent, ActiveFlag,
       EffectiveStartDate, EffectiveEndDate
FROM dbo.DimStaff
WHERE FirstName = 'Pat' AND LastName = 'Willow'
ORDER BY IsCurrent DESC, EffectiveStartDate DESC;

-- B. The PS staff record id the rename keys on (SourceSystemID should still be 82001, now tied to the
--    new email's StaffKey — the shared id is how the merge knows it's the same person).
SELECT 'B. assignment' AS Stage, fsa.SourceSystemID, d.Email, fsa.SchoolID, fsa.RoleCode, fsa.IsCurrent
FROM dbo.FactStaffAssignment fsa
JOIN dbo.DimStaff d ON d.StaffKey = fsa.StaffKey
WHERE fsa.SourceSystemID = '82001'
ORDER BY fsa.IsCurrent DESC;

-- C. School access for the current Pat Willow — should be intact (non-zero), not stranded on the old email.
SELECT 'C. school access' AS Stage, ssa.Email, COUNT(*) AS Schools
FROM dbo.StaffSchoolAccess ssa
JOIN dbo.DimStaff d ON d.StaffKey = ssa.StaffKey AND d.IsCurrent = 1
WHERE d.FirstName = 'Pat' AND d.LastName = 'Willow'
GROUP BY ssa.Email;

-- D. Latest staff-merge audit line — EXPECT 'N email(s) reconciled in place (corrected address)' with N>=1.
SELECT TOP 5 'D. audit' AS Stage, SubmissionTimestamp, Status, Message
FROM dbo.FactSubmissionAudit
WHERE Message LIKE '%email(s) reconciled in place%'
ORDER BY SubmissionTimestamp DESC;
