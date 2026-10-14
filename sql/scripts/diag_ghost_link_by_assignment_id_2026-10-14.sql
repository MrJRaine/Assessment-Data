/*******************************************************************************
 * Script: diag_ghost_link_by_assignment_id_2026-10-14.sql   (LIVE diagnostic — READ ONLY)
 * Purpose: Prove the assignment-ID lineage links each NULL-access ghost (retired old email) to its
 *          REAL current person via a SHARED FactStaffAssignment.SourceSystemID — definitively, and
 *          disambiguating the two-same-name LeBlanc case that a name match can't. This is the link
 *          the one-time ghost cleanup + the usp_MergeStaff email-change pre-pass would use.
 *
 * Reads:  DimStaff, FactStaffAssignment. Staff email/name are NOT PII. No student PII.
 * Writes: NOTHING.
 * Region: Canada East (PIIDPA compliant)
 *
 * Read it: a ghost with a MatchedCurrentEmail + SharedAssignmentIDs >= 1 is a confirmed email change
 *   (link old->new by ID). A ghost with NO match = genuine departure (no assignment came back). If a
 *   ghost matches MORE THAN ONE current person, that's a real collision to flag (shouldn't happen if
 *   an assignment ID is unique to one individual, per the design).
 ******************************************************************************/

SET NOCOUNT ON;

;WITH Ghost AS (   -- retired, current-version, NULL-access rows
    SELECT StaffKey, Email, FirstName, LastName
    FROM DimStaff
    WHERE IsCurrent = 1 AND ActiveFlag = 0 AND AccessLevel IS NULL
),
GhostAsg AS (      -- the assignment IDs that ever belonged to each ghost (any bridge version)
    SELECT DISTINCT g.StaffKey AS GhostKey, g.Email AS GhostEmail, g.FirstName, g.LastName,
           f.SourceSystemID
    FROM Ghost g
    INNER JOIN FactStaffAssignment f ON f.StaffKey = g.StaffKey
    WHERE f.SourceSystemID IS NOT NULL
),
CurAsg AS (        -- assignment IDs on CURRENT, ACTIVE people
    SELECT DISTINCT d.StaffKey, d.Email, d.AccessLevel, f.SourceSystemID
    FROM DimStaff d
    INNER JOIN FactStaffAssignment f ON f.StaffKey = d.StaffKey
    WHERE d.IsCurrent = 1 AND d.ActiveFlag = 1 AND f.SourceSystemID IS NOT NULL
)
SELECT
    ga.GhostEmail,
    ga.FirstName, ga.LastName,
    ca.Email           AS MatchedCurrentEmail,
    ca.AccessLevel     AS MatchedAccessLevel,
    COUNT(DISTINCT ga.SourceSystemID) AS SharedAssignmentIDs,
    COUNT(DISTINCT ca.StaffKey) OVER (PARTITION BY ga.GhostKey) AS DistinctMatchesForGhost
FROM GhostAsg ga
INNER JOIN CurAsg ca
        ON ca.SourceSystemID = ga.SourceSystemID
       AND ca.StaffKey <> ga.GhostKey
GROUP BY ga.GhostKey, ga.GhostEmail, ga.FirstName, ga.LastName, ca.StaffKey, ca.Email, ca.AccessLevel
ORDER BY ga.LastName, ga.FirstName, SharedAssignmentIDs DESC;
GO
