/*******************************************************************************
 * Script: diag_staff_record_doucette_2026-10-19.sql   (LIVE — READ ONLY; staff name/email are public, not PII)
 * Purpose: Full record for one staff member from DimStaff (ALL versions, current + historical) and from
 *          the raw staging table (Stg_Staff — one row per assignment). Useful for an email-reconciliation
 *          / ghost investigation: compare what's in the dimension vs what PowerSchool last sent.
 *
 * Reads:  DimStaff, Stg_Staff. Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

SET NOCOUNT ON;

DECLARE @Email VARCHAR(255) = 'ricky.doucette@tcrce.ca';   -- lowercased to match DimStaff.Email

-- r1: DimStaff — every version for this email, newest first. IsCurrent=1 is the live row;
--     ActiveFlag=0 + AccessLevel NULL = a deactivation/ghost marker.
SELECT *
FROM DimStaff
WHERE LOWER(Email) = @Email
ORDER BY IsCurrent DESC, EffectiveStartDate DESC, StaffKey DESC;
GO

-- r2: Stg_Staff — the raw staging rows from the most recent ingest (one per assignment).
--     Empty here while DimStaff still has the person = they've dropped out of the latest export
--     (departed, or their email changed in PowerSchool — check the new address's staging rows).
DECLARE @Email2 VARCHAR(255) = 'ricky.doucette@tcrce.ca';
SELECT *
FROM Stg_Staff
WHERE LOWER(Email_Addr) = @Email2
ORDER BY ID;
GO
